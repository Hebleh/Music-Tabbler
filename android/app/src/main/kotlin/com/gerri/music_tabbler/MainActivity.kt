package com.gerri.music_tabbler

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "music_tabbler/performance_mode"
    private val externalUrlChannelName = "music_tabbler/external_url"
    private val incomingPdfChannelName = "music_tabbler/incoming_pdf"
    private var incomingPdfChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (isPdfShare(intent)) {
            incomingPdfChannel?.invokeMethod("sharedPdfAvailable", null)
        }
    }

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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            externalUrlChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.arguments as? String
            val uri = url?.let(Uri::parse)
            if (uri == null || (uri.scheme != "https" && uri.scheme != "http")) {
                result.error("invalid_url", "Only http and https URLs can be opened.", null)
                return@setMethodCallHandler
            }
            try {
                startActivity(Intent(Intent.ACTION_VIEW, uri))
                result.success(null)
            } catch (error: Exception) {
                result.error("open_failed", error.message, null)
            }
        }
        incomingPdfChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            incomingPdfChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "takePendingPdf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val pending = intent
                if (!isPdfShare(pending)) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val uri = sharedUri(pending)
                if (uri == null) {
                    result.error("missing_pdf", "The shared PDF has no readable content URI.", null)
                    return@setMethodCallHandler
                }
                try {
                    val bytes = contentResolver.openInputStream(uri)?.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(64 * 1024)
                        var total = 0
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            total += count
                            if (total > 100 * 1024 * 1024) {
                                throw IllegalArgumentException("Shared PDFs are limited to 100 MB.")
                            }
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    } ?: throw IllegalArgumentException("The shared PDF could not be opened.")
                    setIntent(Intent(Intent.ACTION_MAIN))
                    result.success(
                        mapOf(
                            "bytes" to bytes,
                            "fileName" to displayName(uri),
                        ),
                    )
                } catch (error: Exception) {
                    result.error("read_failed", error.message, null)
                }
            }
        }
    }

    private fun isPdfShare(candidate: Intent?): Boolean =
        candidate?.action == Intent.ACTION_SEND &&
            (candidate.type == "application/pdf" || candidate.type?.endsWith("/pdf") == true)

    @Suppress("DEPRECATION")
    private fun sharedUri(candidate: Intent): Uri? =
        candidate.getParcelableExtra(Intent.EXTRA_STREAM) ?: candidate.clipData?.getItemAt(0)?.uri

    private fun displayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return uri.lastPathSegment
    }
}
