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
1. The headline makes a promise. Deliver it in the first line. If the headline
   names a count of things ("4 games", "three changes"), list exactly those
   things, one per line, before anything else.
2. Facts only: names, numbers, dates, prices, versions, outcomes, who did what.
   Every line must contain at least one concrete fact.
3. Never write filler such as "aims to", "is expected to", "will likely",
   "is set to", "generating excitement", "fans are eager", "remains to be seen",
   or "details are scarce". If a thing is not stated, leave it out entirely.
4. Do not restate the headline. Do not describe what the article is about.
   Report what it says.
5. Never infer, guess, or fill gaps with general knowledge.
6. 120 words maximum. Shorter is always better. Stop when the facts run out.
7. No preamble, no sign-off, no headers, no markdown bold.

FORMAT
Line 1: the single most important fact, one sentence.
Then up to 5 lines, each starting with "- ", each a distinct fact.
If the article names specific items, one line per item:
  - Name — what it is, under 12 words.

IF THE TEXT IS THIN
If the text below is only a teaser and lacks the details the headline promises,
output the facts that are present and then stop. Do not compensate for missing
detail by writing longer.

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
