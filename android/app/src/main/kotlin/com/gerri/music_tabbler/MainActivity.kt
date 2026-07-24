package com.gerri.music_tabbler

import android.view.View
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "music_tabbler/performance_mode"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "setActive") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val active = call.arguments as? Boolean
            if (active == null) {
                result.error("invalid_argument", "setActive expects a boolean", null)
                return@setMethodCallHandler
            }
            runOnUiThread {
                if (active) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    @Suppress("DEPRECATION")
                    window.decorView.systemUiVisibility =
                        View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                            View.SYSTEM_UI_FLAG_FULLSCREEN or
                            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    @Suppress("DEPRECATION")
                    window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
                }
                result.success(null)
            }
        }
    }
}
