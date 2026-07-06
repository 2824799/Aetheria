package com.aetheria.aetheria

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.text.TextPaint
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlin.math.max
import kotlin.math.min

class FloatingLyricService : Service() {
    private var windowManager: WindowManager? = null
    private var lyricView: FloatingLyricView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var style = FloatingLyricStyle()

    companion object {
        private const val CHANNEL_ID = "floating_lyrics"
        private const val NOTIFICATION_ID = 1002
        private const val ACTION_SHOW = "com.aetheria.aetheria.floating_lyrics.SHOW"
        private const val ACTION_HIDE = "com.aetheria.aetheria.floating_lyrics.HIDE"

        private val mainHandler = Handler(Looper.getMainLooper())
        private var instance: FloatingLyricService? = null
        private var pendingStyle = FloatingLyricStyle()
        private var pendingFrame = FloatingLyricFrame()

        fun show(context: Context) {
            val intent = Intent(context, FloatingLyricService::class.java).apply {
                action = ACTION_SHOW
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun hide(context: Context) {
            val intent = Intent(context, FloatingLyricService::class.java).apply {
                action = ACTION_HIDE
            }
            context.startService(intent)
        }

        fun updateStyle(context: Context, payload: Map<String, Any?>) {
            pendingStyle = FloatingLyricStyle.fromPayload(payload, pendingStyle)
            if (instance == null) {
                show(context)
            }
            mainHandler.post {
                instance?.applyStyle(pendingStyle)
            }
        }

        fun updateLyrics(context: Context, payload: Map<String, Any?>) {
            pendingFrame = FloatingLyricFrame.fromPayload(payload)
            if (instance == null) {
                show(context)
            }
            mainHandler.post {
                instance?.applyFrame(pendingFrame)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        applyStyle(pendingStyle)
        applyFrame(pendingFrame)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_HIDE -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                ensureView()
                applyStyle(pendingStyle)
                applyFrame(pendingFrame)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        removeView()
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureView() {
        if (!canDrawOverlays()) {
            return
        }
        if (lyricView != null) {
            return
        }
        val manager = windowManager ?: return
        val view = FloatingLyricView(this)
        view.onMove = move@ { dx, dy ->
            val params = layoutParams ?: return@move
            params.x += dx
            params.y += dy
            manager.updateViewLayout(view, params)
        }
        view.onBoundsChanged = bounds@ {
            val params = layoutParams ?: return@bounds
            MainActivity.dispatchFloatingLyricBounds(
                params.x,
                params.y,
                params.width,
                params.height,
            )
        }
        lyricView = view
        layoutParams = buildLayoutParams()
        manager.addView(view, layoutParams)
    }

    private fun removeView() {
        val manager = windowManager ?: return
        lyricView?.let {
            try {
                manager.removeView(it)
            } catch (_: Exception) {
            }
        }
        lyricView = null
        layoutParams = null
    }

    private fun applyStyle(newStyle: FloatingLyricStyle) {
        style = newStyle
        ensureView()
        lyricView?.style = newStyle
        lyricView?.invalidate()
        updateLayoutParams()
    }

    private fun applyFrame(frame: FloatingLyricFrame) {
        ensureView()
        lyricView?.frame = frame
        lyricView?.alpha = if (frame.fade) (style.opacity * 0.22f) else style.opacity
        lyricView?.invalidate()
    }

    private fun updateLayoutParams() {
        val manager = windowManager ?: return
        val view = lyricView ?: return
        val params = layoutParams ?: return
        val metrics = resources.displayMetrics
        params.width = style.windowWidth
            .takeIf { it > 0 }
            ?.toInt()
            ?.coerceIn(dp(80), max(dp(80), metrics.widthPixels - dp(16)))
            ?: (metrics.widthPixels - dp(32))
        params.height = style.windowHeight
            .takeIf { it > 0 }
            ?.toInt()
            ?.coerceIn(dp(28), dp(260))
            ?: dp(112)
        params.flags = buildWindowFlags(style.locked)
        if (style.windowX >= 0 && style.windowY >= 0) {
            params.x = style.windowX.toInt()
            params.y = style.windowY.toInt()
        }
        try {
            manager.updateViewLayout(view, params)
        } catch (_: Exception) {
        }
    }

    private fun buildLayoutParams(): WindowManager.LayoutParams {
        val metrics = resources.displayMetrics
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        return WindowManager.LayoutParams(
            min(metrics.widthPixels - dp(32), style.windowWidth.toInt().coerceAtLeast(dp(80))),
            style.windowHeight.toInt().coerceAtLeast(dp(28)),
            type,
            buildWindowFlags(style.locked),
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (style.windowX >= 0) style.windowX.toInt() else dp(16)
            y = if (style.windowY >= 0) style.windowY.toInt() else dp(120)
        }
    }

    private fun buildWindowFlags(locked: Boolean): Int {
        var flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        if (locked) {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        return flags
    }

    private fun canDrawOverlays(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "悬浮歌词",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持桌面/悬浮歌词显示"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = android.app.PendingIntent.getActivity(
            this,
            42,
            intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) android.app.PendingIntent.FLAG_IMMUTABLE else 0),
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentTitle("Aetheria 悬浮歌词")
            .setContentText("正在显示当前播放歌词")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}

private data class FloatingLyricStyle(
    val locked: Boolean = false,
    val alwaysOnTop: Boolean = true,
    val showTranslation: Boolean = true,
    val showNextLine: Boolean = true,
    val boldCurrentLine: Boolean = true,
    val zoomCurrentLine: Boolean = true,
    val compactMultiline: Boolean = false,
    val textShadowEnabled: Boolean = true,
    val align: String = "center",
    val fontSize: Float = 30f,
    val lineGap: Float = 8f,
    val opacity: Float = 0.95f,
    val unplayedColor: Int = Color.WHITE,
    val playedColor: Int = Color.rgb(34, 197, 94),
    val shadowColor: Int = 0x99000000.toInt(),
    val windowX: Float = -1f,
    val windowY: Float = -1f,
    val windowWidth: Float = 760f,
    val windowHeight: Float = 150f,
) {
    companion object {
        fun fromPayload(payload: Map<String, Any?>, fallback: FloatingLyricStyle): FloatingLyricStyle {
            return FloatingLyricStyle(
                locked = payload.bool("locked") ?: fallback.locked,
                alwaysOnTop = payload.bool("alwaysOnTop") ?: fallback.alwaysOnTop,
                showTranslation = payload.bool("showTranslation") ?: fallback.showTranslation,
                showNextLine = payload.bool("showNextLine") ?: fallback.showNextLine,
                boldCurrentLine = payload.bool("boldCurrentLine") ?: fallback.boldCurrentLine,
                zoomCurrentLine = payload.bool("zoomCurrentLine") ?: fallback.zoomCurrentLine,
                compactMultiline = payload.bool("compactMultiline") ?: fallback.compactMultiline,
                textShadowEnabled = payload.bool("textShadowEnabled") ?: fallback.textShadowEnabled,
                align = payload.string("align") ?: fallback.align,
                fontSize = payload.float("fontSize") ?: fallback.fontSize,
                lineGap = payload.float("lineGap") ?: fallback.lineGap,
                opacity = payload.float("opacity") ?: fallback.opacity,
                unplayedColor = payload.int("unplayedColor") ?: fallback.unplayedColor,
                playedColor = payload.int("playedColor") ?: fallback.playedColor,
                shadowColor = payload.int("shadowColor") ?: fallback.shadowColor,
                windowX = payload.float("windowX") ?: fallback.windowX,
                windowY = payload.float("windowY") ?: fallback.windowY,
                windowWidth = payload.float("windowWidth") ?: fallback.windowWidth,
                windowHeight = payload.float("windowHeight") ?: fallback.windowHeight,
            )
        }
    }
}

private data class FloatingLyricFrame(
    val line: String = "暂无歌词",
    val translation: String = "",
    val nextLine: String = "",
    val contextLines: List<String> = emptyList(),
    val progress: Float = 0f,
    val isPlaying: Boolean = false,
    val fade: Boolean = false,
) {
    companion object {
        fun fromPayload(payload: Map<String, Any?>): FloatingLyricFrame {
            return FloatingLyricFrame(
                line = payload.string("line") ?: "暂无歌词",
                translation = payload.string("translation") ?: "",
                nextLine = payload.string("nextLine") ?: "",
                contextLines = payload.stringList("contextLines"),
                progress = (payload.float("progress") ?: 0f).coerceIn(0f, 1f),
                isPlaying = payload.bool("isPlaying") ?: false,
                fade = payload.bool("fade") ?: false,
            )
        }
    }
}

private class FloatingLyricView(context: Context) : View(context) {
    var style = FloatingLyricStyle()
    var frame = FloatingLyricFrame()
    var onMove: ((Int, Int) -> Unit)? = null
    var onBoundsChanged: (() -> Unit)? = null
    private val paint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var downRawX = 0f
    private var downRawY = 0f
    private var movedX = 0
    private var movedY = 0
    private var dragging = false

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (style.locked) {
            return false
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downRawX = event.rawX
                downRawY = event.rawY
                movedX = 0
                movedY = 0
                dragging = true
                invalidate()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = (event.rawX - downRawX).toInt() - movedX
                val dy = (event.rawY - downRawY).toInt() - movedY
                movedX += dx
                movedY += dy
                onMove?.invoke(dx, dy)
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                dragging = false
                invalidate()
                onBoundsChanged?.invoke()
                return true
            }
        }
        return true
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        val density = resources.displayMetrics.scaledDensity
        if (dragging && !style.locked) {
            bgPaint.color = Color.argb(34, 0, 0, 0)
            canvas.drawRoundRect(RectF(0f, 0f, w, h), 14f, 14f, bgPaint)
        }

        val currentSize = style.fontSize * density * if (style.zoomCurrentLine) 1.06f else 1f
        val subSize = currentSize * 0.43f
        val nextSize = currentSize * 0.55f
        val gap = style.lineGap * density
        val hasTranslation = style.showTranslation && frame.translation.isNotBlank()
        val compactLines = if (style.compactMultiline) {
            frame.contextLines.filter { it.isNotBlank() }.take(3)
        } else {
            emptyList()
        }
        val hasNext = style.showNextLine && (frame.nextLine.isNotBlank() || compactLines.isNotEmpty())

        var totalHeight = textHeight(currentSize)
        if (hasTranslation) totalHeight += gap * 0.55f + textHeight(subSize)
        if (hasNext) totalHeight += gap + textHeight(nextSize)
        if (compactLines.isNotEmpty()) {
            totalHeight += compactLines.drop(1).size * (textHeight(nextSize * 0.88f) + gap * 0.28f)
        }
        var baseline = h / 2f - totalHeight / 2f - paint.ascentFor(currentSize)

        drawProgressText(
            canvas = canvas,
            text = frame.line.ifBlank { "暂无歌词" },
            y = baseline,
            size = currentSize,
            progress = frame.progress,
            playedColor = style.playedColor,
            unplayedColor = style.unplayedColor,
            bold = style.boldCurrentLine,
        )
        baseline += textHeight(currentSize)

        if (hasTranslation) {
            baseline += gap * 0.55f
            drawSingleText(
                canvas = canvas,
                text = frame.translation,
                y = baseline - paint.ascentFor(subSize),
                size = subSize,
                color = applyAlpha(style.unplayedColor, 0.78f),
                bold = false,
            )
            baseline += textHeight(subSize)
        }

        if (hasNext) {
            baseline += gap
            drawSingleText(
                canvas = canvas,
                text = frame.nextLine.ifBlank { compactLines.firstOrNull().orEmpty() },
                y = baseline - paint.ascentFor(nextSize),
                size = nextSize,
                color = applyAlpha(style.unplayedColor, 0.68f),
                bold = false,
            )
            var contextBaseline = baseline + textHeight(nextSize)
            val extraLines = if (frame.nextLine.isBlank()) compactLines.drop(1) else compactLines
            for (line in extraLines.take(3)) {
                contextBaseline += gap * 0.28f
                val contextSize = nextSize * 0.88f
                drawSingleText(
                    canvas = canvas,
                    text = line,
                    y = contextBaseline - paint.ascentFor(contextSize),
                    size = contextSize,
                    color = applyAlpha(style.unplayedColor, 0.52f),
                    bold = false,
                )
                contextBaseline += textHeight(contextSize)
            }
        }
    }

    private fun drawProgressText(
        canvas: Canvas,
        text: String,
        y: Float,
        size: Float,
        progress: Float,
        playedColor: Int,
        unplayedColor: Int,
        bold: Boolean,
    ) {
        val displayText = ellipsize(text, size, bold)
        val textWidth = measure(displayText, size, bold)
        val x = alignedX(textWidth)

        setupPaint(size, unplayedColor, bold)
        canvas.drawText(displayText, x, y, paint)

        val save = canvas.save()
        canvas.clipRect(x, 0f, x + textWidth * progress.coerceIn(0f, 1f), height.toFloat())
        setupPaint(size, playedColor, bold)
        canvas.drawText(displayText, x, y, paint)
        canvas.restoreToCount(save)
    }

    private fun drawSingleText(
        canvas: Canvas,
        text: String,
        y: Float,
        size: Float,
        color: Int,
        bold: Boolean,
    ) {
        val displayText = ellipsize(text, size, bold)
        val textWidth = measure(displayText, size, bold)
        setupPaint(size, color, bold)
        canvas.drawText(displayText, alignedX(textWidth), y, paint)
    }

    private fun ellipsize(text: String, size: Float, bold: Boolean): String {
        setupPaint(size, Color.WHITE, bold)
        return TextUtils.ellipsize(
            text,
            paint,
            max(1f, width - paddingHorizontal() * 2),
            TextUtils.TruncateAt.END,
        ).toString()
    }

    private fun setupPaint(size: Float, color: Int, bold: Boolean) {
        paint.textSize = size
        paint.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        paint.color = color
        if (style.textShadowEnabled) {
            paint.setShadowLayer(3.2f, 0f, 1.2f, style.shadowColor)
        } else {
            paint.clearShadowLayer()
        }
    }

    private fun measure(text: String, size: Float, bold: Boolean): Float {
        setupPaint(size, Color.WHITE, bold)
        return paint.measureText(text)
    }

    private fun textHeight(size: Float): Float {
        paint.textSize = size
        val fm = paint.fontMetrics
        return fm.descent - fm.ascent
    }

    private fun Paint.ascentFor(size: Float): Float {
        textSize = size
        return fontMetrics.ascent
    }

    private fun alignedX(textWidth: Float): Float {
        return when (style.align) {
            "left" -> paddingHorizontal()
            "right" -> width - paddingHorizontal() - textWidth
            else -> (width - textWidth) / 2f
        }.coerceAtLeast(paddingHorizontal())
    }

    private fun paddingHorizontal(): Float = 18f * resources.displayMetrics.density

    private fun applyAlpha(color: Int, alphaScale: Float): Int {
        val alpha = (Color.alpha(color) * alphaScale).toInt().coerceIn(0, 255)
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
    }
}

private fun Map<String, Any?>.string(key: String): String? = this[key]?.toString()

private fun Map<String, Any?>.bool(key: String): Boolean? = this[key] as? Boolean

private fun Map<String, Any?>.float(key: String): Float? {
    val value = this[key]
    return when (value) {
        is Double -> value.toFloat()
        is Float -> value
        is Int -> value.toFloat()
        is Long -> value.toFloat()
        else -> null
    }
}

private fun Map<String, Any?>.int(key: String): Int? {
    val value = this[key]
    return when (value) {
        is Int -> value
        is Long -> value.toInt()
        is Double -> value.toInt()
        else -> null
    }
}

private fun Map<String, Any?>.stringList(key: String): List<String> {
    val value = this[key]
    if (value !is List<*>) {
        return emptyList()
    }
    return value.mapNotNull { it?.toString()?.takeIf { text -> text.isNotBlank() } }
}
