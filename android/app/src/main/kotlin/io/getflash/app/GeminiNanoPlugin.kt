package io.getflash.app

import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

class GeminiNanoPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var model: GenerativeModel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "io.getflash.app/gemini_nano")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // Stop in-flight generation *before* closing the model. A coroutine
        // launched by summarize() runs under a 20s withTimeout and would
        // otherwise keep collecting from a model closed out from under it,
        // then post invokeMethod calls to a channel whose handler is gone
        // and whose engine is being torn down.
        scope.cancel()
        model?.close()
        model = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable"   -> checkAvailability(result)
            "summarize"     -> {
                val title     = call.argument<String>("title") ?: ""
                val content   = call.argument<String>("content") ?: ""
                val locale    = call.argument<String>("locale") ?: "en"
                val requestId = call.argument<Int>("requestId") ?: 0
                summarize(requestId, title, content, locale, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun getModel(): GenerativeModel {
        if (model == null) model = Generation.getClient()
        return model!!
    }

    private fun checkAvailability(result: MethodChannel.Result) {
        scope.launch {
            try {
                val status = getModel().checkStatus()
                when (status) {
                    FeatureStatus.AVAILABLE -> mainThread { result.success(true) }
                    FeatureStatus.DOWNLOADABLE -> {
                        scope.launch {
                            try { getModel().download().collect {} } catch (_: Exception) {}
                        }
                        mainThread {
                            result.error("NANO_DOWNLOADING",
                                "Gemini Nano model is downloading. Try again in a moment.", null)
                        }
                    }
                    FeatureStatus.DOWNLOADING -> mainThread {
                        result.error("NANO_DOWNLOADING",
                            "Gemini Nano model is still downloading. Try again in a moment.", null)
                    }
                    else -> mainThread {
                        result.error("NANO_UNAVAILABLE", "Feature status: $status", null)
                    }
                }
            } catch (e: Exception) {
                mainThread { result.error("NANO_UNAVAILABLE", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun langInstructionFor(locale: String): String = when (locale) {
        "es" -> "Write the summary in Spanish."
        "fr" -> "Write the summary in French."
        "de" -> "Write the summary in German."
        "it" -> "Write the summary in Italian."
        else -> "Write the summary in English."
    }

    private fun writePrompt(title: String, langInstruction: String, source: String): String {
        return """
You are a ruthless news summariser. Report only what the article text states.

$langInstruction

RULES
1. First, judge what kind of article this is. A short factual item — a
   single announcement, a spec sheet, a price, a release date, a plain
   yes/no fact, with little real narrative around it — needs far less than
   a substantive piece (analysis, explainer, a real news story with
   multiple points). Match the length to what's actually there. Never pad
   a short factual article to sound longer than it is. Never compress a
   substantive article down to one vague line.
2. If the headline promises something specific — a number of items ("5
   reasons", "3 hidden skills"), a withheld name ("the browser Apple wants
   you to stop using", "her secret method"), or poses a direct question —
   the summary must resolve it explicitly. Name the actual reasons, the
   actual skills, the actual browser, the actual answer. A summary that
   leaves the headline's tease unresolved has failed at the one thing a
   summary is for.
3. Facts only: names, numbers, dates, prices, versions, outcomes, who did
   what. Every sentence must contain at least one concrete fact.
4. Never write filler such as "aims to", "is expected to", "will likely",
   "is set to", "generating excitement", "fans are eager", "remains to be
   seen", or "details are scarce". If a thing is not stated, leave it out
   entirely.
5. Do not restate the headline as a sentence. Do not describe what the
   article is about in the abstract ("this article discusses..."). Report
   what it actually says.
6. Never infer, guess, or fill gaps with general knowledge.
7. 250 words is the hard ceiling across the whole response. Short factual
   articles should use far less than that — don't stretch to fill it.
8. No preamble, no sign-off, no headers, no markdown bold.

FORMAT

Case A — short factual article (a single fact, spec, price, release date,
or yes/no answer, with little else to say): one or two sentences stating
the core fact in plain readable prose, then — if there's more than one
discrete data point worth listing separately (e.g. several specs, a price
and a date) — bullet them below. Do not force this into a long
paragraph it doesn't need.

Case B — substantive article (news, analysis, explainer, a real narrative):
a paragraph of 75–100 words capturing the actual substance — not just the
headline's single most obvious point, the real shape of what happened and
why it matters. Then, if the headline promises a specific list or count of
things, OR the article has genuinely distinct, separately-listable points
beyond what fits naturally in the paragraph — add up to 5 bullets below the
paragraph, each naming the actual specific thing with a real descriptive
clause, not a vague restatement. If nothing earns a bullet, the paragraph
alone is complete and correct — don't force one.

Bullets, when used, each start with "- " on their own line, after a blank
line following the paragraph.

Examples of resolving a headline's tease correctly (illustrative, not
literal templates):
- Headline promises "5 reasons X will happen" → each of the 5 reasons
  becomes its own bullet, named specifically, not "the author gives
  several reasons why."
- Headline references "hidden skills" in a game → the summary names the
  actual skills (e.g. "blocking, sneak attacks, and archery bonuses"), not
  "the game has some secret skills."
- Headline says a company "warns against" something without naming it →
  the summary names the actual thing and the actual stated reason, not
  "Apple issued a warning about a product."

IF THE TEXT IS THIN
If the text below is only a teaser and lacks the detail the headline
promises, write as full a response as the available material genuinely
supports — even a single short sentence — rather than padding with filler
or inventing detail to reach either length target above.

ARTICLE
Title: $title

$source

Summary:
""".trimIndent()
    }

    // Streams chunks back to Flutter via reverse invokeMethod calls so text
    // appears as it generates rather than waiting for the full response.
    //
    // Every callback carries the requestId it belongs to. Dismissing the sheet
    // can't stop this coroutine, so Flutter uses the id to discard anything
    // arriving from a generation the user has already moved on from.
    private fun summarize(
        requestId: Int,
        title: String,
        body: String,
        locale: String,
        result: MethodChannel.Result,
    ) {
        // Acknowledge immediately so Flutter's await returns
        result.success(null)
        scope.launch {
            try {
                // 2500 chars covers the lede and substantive middle of a news
                // article — where list-type payloads live — and cuts
                // time-to-first-token materially versus sending the whole body.
                val trimmed = body.take(2500)
                val langInstruction = langInstructionFor(locale)
                val prompt = writePrompt(title, langInstruction, "Content: $trimmed")

                withTimeout(20_000) {
                    getModel().generateContentStream(prompt).collect { response ->
                        val chunk = response.candidates.firstOrNull()?.text ?: ""
                        if (chunk.isNotEmpty()) {
                            reply("summaryChunk", requestId, chunk)
                        }
                    }
                }
                reply("summaryDone", requestId, null)
            } catch (e: Exception) {
                reply("summaryError", requestId, e.message ?: "Unknown error")
            }
        }
    }

    private fun reply(method: String, requestId: Int, value: Any?) {
        mainThread {
            channel.invokeMethod(method, mapOf("requestId" to requestId, "value" to value))
        }
    }

    private fun mainThread(block: () -> Unit) {
        android.os.Handler(android.os.Looper.getMainLooper()).post(block)
    }
}
