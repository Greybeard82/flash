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
                // A finished prompt, built in Dart. Nothing here shapes it:
                // the cloud fallback shares the same builder, and a second
                // copy of those rules living on this side is exactly how the
                // two would drift apart.
                val prompt    = call.argument<String>("prompt") ?: ""
                val requestId = call.argument<Int>("requestId") ?: 0
                summarize(requestId, prompt, result)
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
    //
    // Every callback carries the requestId it belongs to. Dismissing the sheet
    // can't stop this coroutine, so Flutter uses the id to discard anything
    // arriving from a generation the user has already moved on from.
    private fun summarize(
        requestId: Int,
        prompt: String,
        result: MethodChannel.Result,
    ) {
        // Acknowledge immediately so Flutter's await returns
        result.success(null)
        scope.launch {
            try {
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
