package com.example.scan_documnet_app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "scan_documnet_app/public_files"
    }

    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveToDownloads") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val sourcePath = call.argument<String>("sourcePath")
            val fileName = call.argument<String>("fileName")
            val mimeType = call.argument<String>("mimeType")
            if (sourcePath == null || fileName == null) {
                result.error("BAD_ARGS", "sourcePath and fileName are required", null)
                return@setMethodCallHandler
            }
            ioExecutor.execute {
                val savedPath = runCatching {
                    saveToDownloads(sourcePath, fileName, mimeType)
                }.getOrNull()
                runOnUiThread { result.success(savedPath) }
            }
        }
    }

    private fun saveToDownloads(sourcePath: String, fileName: String, mimeType: String?): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType ?: "application/octet-stream")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return null
            resolver.openOutputStream(uri)?.use { out ->
                File(sourcePath).inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        }

        // Android 9 and below: the manifest declares WRITE_EXTERNAL_STORAGE
        // (maxSdkVersion 28), so a direct write into the public Downloads
        // directory works when that legacy permission is granted.
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists() && !dir.mkdirs()) return null
        val dest = File(dir, fileName)
        File(sourcePath).copyTo(dest, overwrite = true)
        return dest.absolutePath
    }
}