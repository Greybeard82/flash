package io.getflash.app

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "io.getflash.app/device"

    private companion object {
        // Must match lib/theme/app_theme.dart: `darkBg`. Only the fallback for
        // a first-ever launch, before Dart has told us which theme is active.
        const val DEFAULT_BG = "#0D1B2A"

        const val PREFS = "flash_window"
        const val KEY_BG = "window_background"
    }

    /// The window background is driven by the *app's* theme, never by the OS
    /// uiMode.
    ///
    /// This used to read `resources.configuration.uiMode` and paint white
    /// whenever the OS was in light mode. With the app set to Dark and the OS
    /// on light — the default when night mode is `auto` and it's daytime —
    /// that painted a white window behind a dark UI. Any moment the Flutter
    /// surface didn't fully cover it (overscroll stretch, IME resize, the
    /// launch cross-fade) leaked white through, and `onWindowFocusChanged`
    /// re-applied it on every return to the app.
    ///
    /// Dart pushes the resolved colour whenever the effective theme changes;
    /// it is persisted so the next cold start can paint the right colour
    /// before the Flutter engine has produced a frame.
    private fun applyStoredBackground() {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val hex = prefs.getString(KEY_BG, DEFAULT_BG) ?: DEFAULT_BG
        val color = try {
            Color.parseColor(hex)
        } catch (_: IllegalArgumentException) {
            Color.parseColor(DEFAULT_BG)
        }
        window.setBackgroundDrawable(ColorDrawable(color))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Before the first Flutter frame, so the launch cross-fade composites
        // over the right colour.
        applyStoredBackground()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(GeminiNanoPlugin())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTV" -> {
                        val mgr = getSystemService(Context.UI_MODE_SERVICE) as android.app.UiModeManager
                        result.success(mgr.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    "setWindowBackground" -> {
                        val hex = call.argument<String>("color")
                        if (hex == null) {
                            result.error("BAD_ARGS", "color is required", null)
                        } else {
                            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                                .edit()
                                .putString(KEY_BG, hex)
                                .apply()
                            runOnUiThread { applyStoredBackground() }
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // uiMode is in configChanges, so the Activity never restarts on a
    // dark/light toggle and the background set at launch can go stale.
    // Re-apply the app's own colour — not the OS's — on every refocus.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyStoredBackground()
    }
}
