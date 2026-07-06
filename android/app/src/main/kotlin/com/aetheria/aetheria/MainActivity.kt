package com.aetheria.aetheria

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.wifi.WifiManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.MediaStore
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
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
    private var mediaSession: MediaSessionCompat? = null
    private var cachedArtworkPath: String? = null
    private var cachedArtworkBitmap: Bitmap? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    private external fun initAudioContext(context: Context)

    companion object {
        const val ACTION_PREVIOUS = "com.aetheria.aetheria.action.PREVIOUS"
        const val ACTION_TOGGLE = "com.aetheria.aetheria.action.TOGGLE"
        const val ACTION_NEXT = "com.aetheria.aetheria.action.NEXT"

        private var notificationChannelBridge: MethodChannel? = null
        private val pendingNotificationActions = mutableListOf<String>()

        init {
            System.loadLibrary("rust_lib_aetheria")
        }

        fun dispatchPlaybackAction(action: String) {
            val bridge = notificationChannelBridge
            if (bridge == null) {
                synchronized(pendingNotificationActions) {
                    pendingNotificationActions.add(action)
                }
                return
            }
            Handler(Looper.getMainLooper()).post {
                bridge.invokeMethod("notificationAction", mapOf("action" to action))
            }
        }

        fun dispatchFloatingLyricBounds(x: Int, y: Int, width: Int, height: Int) {
            val bridge = notificationChannelBridge ?: return
            Handler(Looper.getMainLooper()).post {
                bridge.invokeMethod(
                    "floatingLyricsEvent",
                    mapOf(
                        "type" to "boundsChanged",
                        "x" to x,
                        "y" to y,
                        "width" to width,
                        "height" to height,
                    ),
                )
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setHighRefreshRate()
        initAudioContext(applicationContext)
    }

    override fun onDestroy() {
        releaseMulticastLock()
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channelBridge = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        notificationChannelBridge = channelBridge
        flushPendingNotificationActions()

        channelBridge.setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Aetheria"
                    val artist = call.argument<String>("artist") ?: "未知歌手"
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val positionMs = call.argument<Int>("positionMs") ?: 0
                    val durationMs = call.argument<Int>("durationMs") ?: 0
                    val hasPrevious = call.argument<Boolean>("hasPrevious") ?: false
                    val hasNext = call.argument<Boolean>("hasNext") ?: false
                    val audioPath = call.argument<String>("audioPath")
                    showPlaybackNotification(
                        title,
                        artist,
                        isPlaying,
                        positionMs,
                        durationMs,
                        hasPrevious,
                        hasNext,
                        audioPath,
                    )
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
                "acquireMulticastLock" -> {
                    acquireMulticastLock()
                    result.success(null)
                }
                "releaseMulticastLock" -> {
                    releaseMulticastLock()
                    result.success(null)
                }
                "getDeviceName" -> {
                    result.success(resolveDeviceName())
                }
                "canDrawOverlays" -> {
                    result.success(canDrawOverlays())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "showFloatingLyrics" -> {
                    FloatingLyricService.show(applicationContext)
                    result.success(null)
                }
                "hideFloatingLyrics" -> {
                    FloatingLyricService.hide(applicationContext)
                    result.success(null)
                }
                "updateFloatingLyricsStyle" -> {
                    @Suppress("UNCHECKED_CAST")
                    FloatingLyricService.updateStyle(
                        applicationContext,
                        call.arguments as? Map<String, Any?> ?: emptyMap(),
                    )
                    result.success(null)
                }
                "updateFloatingLyrics" -> {
                    @Suppress("UNCHECKED_CAST")
                    FloatingLyricService.updateLyrics(
                        applicationContext,
                        call.arguments as? Map<String, Any?> ?: emptyMap(),
                    )
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun acquireMulticastLock() {
        try {
            if (multicastLock?.isHeld == true) {
                return
            }
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifiManager.createMulticastLock("aetheria_lan_sync").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
        } catch (_: Exception) {
        } finally {
            multicastLock = null
        }
    }

    private fun resolveDeviceName(): String {
        val model = Build.MODEL?.trim().orEmpty()
        val manufacturer = Build.MANUFACTURER?.trim().orEmpty()
        val fallback = "Android 设备"
        if (model.isEmpty()) {
            return fallback
        }
        if (manufacturer.isEmpty() || model.lowercase().contains(manufacturer.lowercase())) {
            return model
        }
        return "$manufacturer $model"
    }

    private fun flushPendingNotificationActions() {
        val bridge = notificationChannelBridge ?: return
        val actionsToDispatch = synchronized(pendingNotificationActions) {
            val copy = pendingNotificationActions.toList()
            pendingNotificationActions.clear()
            copy
        }
        Handler(Looper.getMainLooper()).post {
            for (action in actionsToDispatch) {
                bridge.invokeMethod("notificationAction", mapOf("action" to action))
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

    private fun showPlaybackNotification(
        title: String,
        artist: String,
        isPlaying: Boolean,
        positionMs: Int,
        durationMs: Int,
        hasPrevious: Boolean,
        hasNext: Boolean,
        audioPath: String?,
    ) {
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

        val previousIntent = buildPlaybackActionIntent(ACTION_PREVIOUS, 1)
        val toggleIntent = buildPlaybackActionIntent(ACTION_TOGGLE, 2)
        val nextIntent = buildPlaybackActionIntent(ACTION_NEXT, 3)
        val safeDurationMs = durationMs.coerceAtLeast(0)
        val safePositionMs = if (safeDurationMs > 0) {
            positionMs.coerceIn(0, safeDurationMs)
        } else {
            positionMs.coerceAtLeast(0)
        }
        val session = ensureMediaSession()
        val artwork = loadEmbeddedArtwork(audioPath)
        updateMediaSession(
            session,
            title,
            artist,
            isPlaying,
            safePositionMs,
            safeDurationMs,
            hasPrevious,
            hasNext,
            artwork,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
            )
            .setContentTitle(title)
            .setContentText(artist)
            .setOngoing(isPlaying)
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setLargeIcon(artwork)
            .addAction(
                android.R.drawable.ic_media_previous,
                if (hasPrevious) "上一首" else "上一首（队列头部）",
                previousIntent,
            )
            .addAction(
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (isPlaying) "暂停" else "播放",
                toggleIntent,
            )
            .addAction(
                android.R.drawable.ic_media_next,
                if (hasNext) "下一首" else "下一首（队列尾部）",
                nextIntent,
            )
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )

        if (safeDurationMs > 0) {
            builder
                .setProgress(safeDurationMs, safePositionMs, false)
                .setSubText("${formatDuration(safePositionMs)} / ${formatDuration(safeDurationMs)}")
        } else {
            builder
                .setProgress(0, 0, true)
                .setSubText("正在解析音频时长")
        }

        notificationManager.notify(NOTIFICATION_ID, builder.build())
    }

    private fun loadEmbeddedArtwork(audioPath: String?): Bitmap? {
        if (audioPath.isNullOrBlank()) {
            cachedArtworkPath = null
            cachedArtworkBitmap = null
            return null
        }
        if (cachedArtworkPath == audioPath) {
            return cachedArtworkBitmap
        }

        cachedArtworkPath = audioPath
        cachedArtworkBitmap = null
        val file = File(audioPath)
        if (!file.exists()) {
            return null
        }

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val pictureData = retriever.embeddedPicture ?: return null
            decodeArtworkBitmap(pictureData).also { bitmap ->
                cachedArtworkBitmap = bitmap
            }
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun decodeArtworkBitmap(data: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)

        var sampleSize = 1
        val maxEdge = 512
        while (bounds.outWidth / sampleSize > maxEdge || bounds.outHeight / sampleSize > maxEdge) {
            sampleSize *= 2
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
        }
        return BitmapFactory.decodeByteArray(data, 0, data.size, options)
    }

    private fun ensureMediaSession(): MediaSessionCompat {
        mediaSession?.let {
            it.isActive = true
            return it
        }

        val session = MediaSessionCompat(this, "AetheriaPlayback").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    MainActivity.dispatchPlaybackAction("toggle")
                }

                override fun onPause() {
                    MainActivity.dispatchPlaybackAction("toggle")
                }

                override fun onSkipToPrevious() {
                    MainActivity.dispatchPlaybackAction("previous")
                }

                override fun onSkipToNext() {
                    MainActivity.dispatchPlaybackAction("next")
                }

                override fun onSeekTo(pos: Long) {
                    MainActivity.dispatchPlaybackAction("seek:${pos.coerceAtLeast(0L)}")
                }
            })
            isActive = true
        }
        mediaSession = session
        return session
    }

    private fun updateMediaSession(
        session: MediaSessionCompat,
        title: String,
        artist: String,
        isPlaying: Boolean,
        positionMs: Int,
        durationMs: Int,
        hasPrevious: Boolean,
        hasNext: Boolean,
        artwork: Bitmap?,
    ) {
        val actions = PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_SEEK_TO or
            (if (hasPrevious) PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS else 0L) or
            (if (hasNext) PlaybackStateCompat.ACTION_SKIP_TO_NEXT else 0L)

        val metadataBuilder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs.toLong())
        if (artwork != null) {
            metadataBuilder
                .putBitmap(MediaMetadataCompat.METADATA_KEY_ART, artwork)
                .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, artwork)
        }
        session.setMetadata(metadataBuilder.build())
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(
                    if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    positionMs.toLong(),
                    if (isPlaying) 1.0f else 0.0f,
                )
                .build()
        )
    }

    private fun buildPlaybackActionIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, PlaybackActionReceiver::class.java).apply {
            this.action = action
            `package` = packageName
        }
        return PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0),
        )
    }

    private fun formatDuration(durationMs: Int): String {
        val totalSeconds = (durationMs / 1000).coerceAtLeast(0)
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format("%02d:%02d", minutes, seconds)
    }

    private fun hidePlaybackNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
        mediaSession?.isActive = false
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
    }

    private fun canDrawOverlays(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)) {
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
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

class PlaybackActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            MainActivity.ACTION_PREVIOUS -> MainActivity.dispatchPlaybackAction("previous")
            MainActivity.ACTION_TOGGLE -> MainActivity.dispatchPlaybackAction("toggle")
            MainActivity.ACTION_NEXT -> MainActivity.dispatchPlaybackAction("next")
        }
    }
}
