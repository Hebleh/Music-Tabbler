package com.gerri.music_tabbler

import android.app.Activity
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
    private val platformFileChannelName = "music_tabbler/platform_file"
    private val portableFileChannelName = "music_tabbler/portable_file"
    private var incomingPdfChannel: MethodChannel? = null
    private var pendingPortableSaveResult: MethodChannel.Result? = null
    private var pendingPortableSaveBytes: ByteArray? = null

    companion object {
        private const val PORTABLE_SAVE_REQUEST_CODE = 41032
        private const val MAX_PORTABLE_FILE_BYTES = 128 * 1024 * 1024
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (isPdfShare(intent)) {
            incomingPdfChannel?.invokeMethod("sharedPdfAvailable", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PORTABLE_SAVE_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPortableSaveResult
        val bytes = pendingPortableSaveBytes
        pendingPortableSaveResult = null
        pendingPortableSaveBytes = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null || bytes == null) {
            result.error("save_failed", "Android did not return a writable document.", null)
            return
        }
        try {
            contentResolver.openOutputStream(uri, "w")?.use { output ->
                output.write(bytes)
                output.flush()
            } ?: throw IllegalArgumentException("The selected document could not be opened.")
            result.success(uri.toString())
        } catch (error: Exception) {
            result.error(
                "save_failed",
                error.message ?: "Android could not save the portable file.",
                null,
            )
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            platformFileChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "readBytes") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val identifier = call.arguments as? String
            val uri = identifier?.let(Uri::parse)
            if (uri == null || (uri.scheme != "content" && uri.scheme != "file")) {
                result.error(
                    "invalid_identifier",
                    "The selected file has no readable Android content URI.",
                    null,
                )
                return@setMethodCallHandler
            }
            try {
                result.success(
                    readUriBytes(
                        uri,
                        128 * 1024 * 1024,
                        "Selected files are limited to 128 MB.",
                    ),
                )
            } catch (error: Exception) {
                result.error(
                    "read_failed",
                    error.message ?: "Android could not read the selected file.",
                    null,
                )
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            portableFileChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingPortableSaveResult != null) {
                result.error("save_in_progress", "Another portable file is already being saved.", null)
                return@setMethodCallHandler
            }
            val arguments = call.arguments as? Map<*, *>
            val fileName = arguments?.get("fileName") as? String
            val bytes = arguments?.get("bytes") as? ByteArray
            if (fileName.isNullOrBlank() || bytes == null) {
                result.error("invalid_argument", "saveFile expects a name and bytes.", null)
                return@setMethodCallHandler
            }
            if (bytes.isEmpty() || bytes.size > MAX_PORTABLE_FILE_BYTES) {
                result.error("invalid_size", "Portable files must be between 1 byte and 128 MB.", null)
                return@setMethodCallHandler
            }
            pendingPortableSaveResult = result
            pendingPortableSaveBytes = bytes
            try {
                startActivityForResult(
                    Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    },
                    PORTABLE_SAVE_REQUEST_CODE,
                )
            } catch (error: Exception) {
                pendingPortableSaveResult = null
                pendingPortableSaveBytes = null
                result.error(
                    "save_failed",
                    error.message ?: "Android could not open a document saver.",
                    null,
                )
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
                    val bytes = readUriBytes(
                        uri,
                        100 * 1024 * 1024,
                        "Shared PDFs are limited to 100 MB.",
                    )
                    setIntent(Intent(Intent.ACTION_MAIN))
                    result.success(
                        mapOf(
                            "bytes" to bytes,
                            "fileName" to displayName(uri),
                        ),
                    )
                } catch (error: Exception) {
                    result.error(
                        "read_failed",
                        error.message ?: "Android could not read the shared PDF.",
                        null,
                    )
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

    private fun readUriBytes(uri: Uri, maxBytes: Int, sizeMessage: String): ByteArray =
        contentResolver.openInputStream(uri)?.use { input ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            var total = 0
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                if (total > maxBytes) throw IllegalArgumentException(sizeMessage)
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        } ?: throw IllegalArgumentException("The selected file could not be opened.")
}
