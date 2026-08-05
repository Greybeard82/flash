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
        model?.close()
        model = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable"   -> checkAvailability(result)
            "summarize"     -> {
                val title   = call.argument<String>("title") ?: ""
                val content = call.argument<String>("content") ?: ""
                val locale  = call.argument<String>("locale") ?: "en"
                summarize(title, content, locale, result)
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
        return "Write a summary of a news article in approximately 120 words, based on the key points " +
            "below. $langInstruction Begin with a single sentence stating the focal point — the one thing " +
            "that matters most, cutting through any clickbait or misleading framing in the title. If the " +
            "key points list contains only one substantive point, write the whole summary as a short " +
            "paragraph and use no bullet points at all. Only if there are several genuinely distinct points " +
            "should you present them as short bullets (using \"- \") after the opening sentence. Prefer " +
            "prose. Be factual and neutral. No preamble.\n\nTitle: $title\n\n$source\n\nSummary:"
    }

    // Streams chunks back to Flutter via reverse invokeMethod calls so text
    // appears as it generates rather than waiting for the full response.
    private fun summarize(title: String, body: String, locale: String, result: MethodChannel.Result) {
        // Acknowledge immediately so Flutter's await returns
        result.success(null)
        scope.launch {
            try {
                // 6000 chars (~1500 tokens) covers a full extracted article body,
                // not just an RSS teaser, while staying within Nano's context window.
                val trimmed = body.take(6000)
                val langInstruction = langInstructionFor(locale)

                // Pass 1 — read (non-streaming). Extract key points; never shown to the user.
                var keyPoints: String? = null
                try {
                    withTimeout(45_000) {
                        val readPrompt =
                            "Read the following article and list the key factual points it contains, one " +
                            "per line, in order of importance. Do not write a summary. Do not add " +
                            "commentary. If the article makes only one substantive point, list only that " +
                            "one point.\n\nTitle: $title\n\nContent: $trimmed\n\nKey points:"
                        val response = getModel().generateContent(readPrompt)
                        keyPoints = response.candidates.firstOrNull()?.text?.trim()
                    }
                } catch (_: Exception) {
                    keyPoints = null
                }

                // Pass 2 — write (streaming). Feed it the key points, or fall back to the
                // raw article directly if pass 1 timed out or returned nothing.
                val writeSource = if (!keyPoints.isNullOrBlank()) {
                    "Key points:\n$keyPoints"
                } else {
                    "Content: $trimmed"
                }
                val prompt = writePrompt(title, langInstruction, writeSource)

                withTimeout(45_000) {
                    getModel().generateContentStream(prompt).collect { response ->
                        val chunk = response.candidates.firstOrNull()?.text ?: ""
                        if (chunk.isNotEmpty()) {
                            mainThread { channel.invokeMethod("summaryChunk", chunk) }
                        }
                    }
                }
                mainThread { channel.invokeMethod("summaryDone", null) }
            } catch (e: Exception) {
                mainThread { channel.invokeMethod("summaryError", e.message ?: "Unknown error") }
            }
        }
    }

    private fun mainThread(block: () -> Unit) {
        android.os.Handler(android.os.Looper.getMainLooper()).post(block)
    }
}
