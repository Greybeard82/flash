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

    // Streams chunks back to Flutter via reverse invokeMethod calls so text
    // appears as it generates rather than waiting for the full response.
    private fun summarize(title: String, body: String, locale: String, result: MethodChannel.Result) {
        // Acknowledge immediately so Flutter's await returns
        result.success(null)
        scope.launch {
            try {
                // 3000 chars (~750 tokens) gives the model enough of the article
                // to extract buried facts, while staying well within Nano's window.
                val trimmed = body.take(3000)
                val langInstruction = when (locale) {
                    "es" -> "Write the summary in Spanish."
                    "fr" -> "Write the summary in French."
                    "de" -> "Write the summary in German."
                    "it" -> "Write the summary in Italian."
                    else -> "Write the summary in English."
                }
                val prompt =
                    "You summarize news articles for a reader who wants only the substance. $langInstruction\n" +
                    "Rules:\n" +
                    "- Total length: strictly under 60 words. Never exceed this.\n" +
                    "- Line 1: one sentence stating the single most important fact, finding, or decision in the " +
                    "article. If the title teases, exaggerates, or withholds information (clickbait), this " +
                    "sentence must state the actual answer or payoff directly.\n" +
                    "- Then 2 to 3 bullet points, each starting with \"- \" and under 13 words, covering the " +
                    "remaining substantive facts: numbers, names, dates, findings, decisions, consequences.\n" +
                    "- Use only information present in the article. Do not add opinions or speculation.\n" +
                    "- Do not restate the headline. No filler such as \"This article discusses\" or \"In summary\".\n\n" +
                    "Title: $title\n\nContent: $trimmed\n\nSummary:"
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
