package io.getflash.app

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "io.getflash.app/device"

    private companion object {
        // Must match lib/theme/app_theme.dart: `darkBg` and the light theme's
        // scaffoldBackgroundColor. Dart owns the real palette; these exist only
        // to paint the window before the first Flutter frame and on refocus.
        // Change one, change the other, or the launch background flashes the
        // wrong colour against the rendered UI.
        const val DARK_BG = "#0D1B2A"
        const val LIGHT_BG = "#FFFFFF"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(GeminiNanoPlugin())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTV" -> {
                        val mgr = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        result.success(mgr.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Re-apply the correct window background whenever the app regains focus
    // (e.g. returning from browser). Since uiMode is in configChanges the
    // Activity never restarts on dark/light toggle, so the background set at
    // launch can go stale. This keeps it in sync.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            val isNight = (resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            window.setBackgroundDrawable(
                ColorDrawable(Color.parseColor(if (isNight) DARK_BG else LIGHT_BG))
            )
        }
    }
}
