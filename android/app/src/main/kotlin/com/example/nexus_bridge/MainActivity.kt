package com.example.nexus_bridge

import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.util.Log
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.nexus_bridge.NearbyBridgeModule
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.nexus_bridge/downloads"
    private var nearbyBridgeModule: NearbyBridgeModule? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "indexMediaStore" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath != null) {
                            indexMediaStore(filePath)
                            result.success("File indexed")
                        } else {
                            result.error("INVALID_PATH", "File path is null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        nearbyBridgeModule = NearbyBridgeModule(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        nearbyBridgeModule?.cleanup()
        super.onDestroy()
    }

    private fun indexMediaStore(filePath: String) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                return
            }

            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, file.name)
                put(MediaStore.Downloads.MIME_TYPE, getMimeType(file.name))
                put(MediaStore.Downloads.DATA, filePath)
                put(MediaStore.Downloads.SIZE, file.length())
                put(MediaStore.Downloads.DATE_ADDED, System.currentTimeMillis() / 1000)
                put(MediaStore.Downloads.IS_PENDING, 0)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // For Android 10+, use MediaStore.Downloads
                contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            } else {
                // For older Android, just scan the file
                sendBroadcast(Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE).apply {
                    data = android.net.Uri.fromFile(file)
                })
            }

            println("[MEDIASTORE] File indexed: $filePath")
        } catch (e: Exception) {
            println("[MEDIASTORE] Error: ${e.message}")
        }
    }

    private fun getMimeType(filename: String): String {
        return when {
            filename.endsWith(".pdf") -> "application/pdf"
            filename.endsWith(".doc") -> "application/msword"
            filename.endsWith(".docx") -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            filename.endsWith(".xls") -> "application/vnd.ms-excel"
            filename.endsWith(".xlsx") -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            filename.endsWith(".txt") -> "text/plain"
            filename.endsWith(".zip") -> "application/zip"
            filename.endsWith(".apk") -> "application/vnd.android.package-archive"
            filename.endsWith(".mp3") -> "audio/mpeg"
            filename.endsWith(".mp4") -> "video/mp4"
            filename.endsWith(".jpg") || filename.endsWith(".jpeg") -> "image/jpeg"
            filename.endsWith(".png") -> "image/png"
            filename.endsWith(".gif") -> "image/gif"
            filename.endsWith(".webp") -> "image/webp"
            else -> "application/octet-stream"
        }
    }
}
