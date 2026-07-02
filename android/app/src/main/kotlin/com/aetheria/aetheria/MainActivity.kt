package com.aetheria.aetheria

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aetheria.app/notification"
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "music_playback"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setHighRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Aetheria"
                    val artist = call.argument<String>("artist") ?: "未知歌手"
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    showPlaybackNotification(title, artist, isPlaying)
                    result.success(null)
                }
                "hideNotification" -> {
                    hidePlaybackNotification()
                    result.success(null)
                }
                "requestPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                "saveToDownloads" -> {
                    val filePath = call.argument<String>("filePath")
                    val fileName = call.argument<String>("fileName")
                    if (filePath == null || fileName == null) {
                        result.error("INVALID_ARGUMENT", "filePath or fileName is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val savedPath = saveFileToDownloads(filePath, fileName)
                        if (savedPath != null) {
                            result.success(savedPath)
                        } else {
                            result.error("SAVE_FAILED", "Failed to save file to downloads", null)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val window = window
            val display = display ?: return
            val modes = display.supportedModes
            if (modes.isEmpty()) return
            
            var bestMode = modes[0]
            for (mode in modes) {
                if (mode.refreshRate > bestMode.refreshRate) {
                    bestMode = mode
                } else if (mode.refreshRate == bestMode.refreshRate) {
                    if (mode.physicalWidth > bestMode.physicalWidth) {
                        bestMode = mode
                    }
                }
            }
            
            val layoutParams = window.attributes
            layoutParams.preferredDisplayModeId = bestMode.modeId
            window.attributes = layoutParams
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val window = window
            val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val display = windowManager.defaultDisplay
            val modes = display.supportedModes
            if (modes.isNotEmpty()) {
                var bestMode = modes[0]
                for (mode in modes) {
                    if (mode.refreshRate > bestMode.refreshRate) {
                        bestMode = mode
                    }
                }
                val layoutParams = window.attributes
                layoutParams.preferredDisplayModeId = bestMode.modeId
                window.attributes = layoutParams
            }
        }
    }

    private fun showPlaybackNotification(title: String, artist: String, isPlaying: Boolean) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "播放状态",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "显示当前播放的歌曲信息"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val iconRes = android.R.drawable.ic_media_play

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(iconRes)
            .setContentTitle(title)
            .setContentText(artist)
            .setOngoing(isPlaying)
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        notificationManager.notify(NOTIFICATION_ID, builder.build())
    }

    private fun hidePlaybackNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
    }

    private fun saveFileToDownloads(filePath: String, fileName: String): String? {
        val file = File(filePath)
        if (!file.exists()) return null

        val resolver = contentResolver
        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            val ext = fileName.substringAfterLast('.', "").lowercase()
            val mime = when (ext) {
                "mp3" -> "audio/mpeg"
                "flac" -> "audio/flac"
                "wav" -> "audio/wav"
                "m4a" -> "audio/mp4"
                "ogg" -> "audio/ogg"
                else -> "audio/*"
            }
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/Aetheria")
            }
        }

        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
        } else {
            val destDir = File(android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS), "Aetheria")
            if (!destDir.exists()) destDir.mkdirs()
            val destFile = File(destDir, fileName)
            try {
                FileInputStream(file).use { inputStream ->
                    FileOutputStream(destFile).use { outputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }
                return destFile.absolutePath
            } catch (e: Exception) {
                throw e
            }
        } ?: return null
        
        try {
            resolver.openOutputStream(uri)?.use { outputStream ->
                FileInputStream(file).use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            }
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }
}
