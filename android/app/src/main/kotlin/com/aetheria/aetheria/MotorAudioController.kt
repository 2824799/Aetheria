package com.aetheria.aetheria

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.annotation.RequiresApi
import java.util.ArrayDeque
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Experimental Android 16 motor-audio renderer.
 *
 * The Rust output callback reduces live PCM into amplitude and coarse frequency
 * control points. Android's waveform-envelope API then renders those points on
 * the device vibrator while the regular speaker stream is silenced.
 */
class MotorAudioController(context: Context) {
    private data class Capabilities(
        val supported: Boolean,
        val reason: String,
        val minControlPointMs: Int = 10,
        val maxControlPointMs: Int = 1000,
        val maxDurationMs: Int = 1000,
        val maxSize: Int = 0,
        val minFrequencyHz: Float = 0f,
        val maxFrequencyHz: Float = 0f,
        val resonantFrequencyHz: Float = 0f,
        val hasAmplitudeControl: Boolean = false,
    )

    private data class MotorPoint(
        val amplitude: Float,
        val frequencyPosition: Float,
        val durationMs: Int,
    )

    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val points = ArrayDeque<MotorPoint>()
    private var enabled = false
    private var running = false
    private var lastError: String? = null
    private var cachedCapabilities: Capabilities? = null

    private val scheduleNext = Runnable {
        running = false
        scheduleNextChunk()
    }

    fun getCapabilities(): Map<String, Any> {
        val capabilities = resolveCapabilities()
        val runtimeError = lastError
        return mapOf(
            "supported" to capabilities.supported,
            "reason" to (runtimeError ?: capabilities.reason),
            "sdkInt" to Build.VERSION.SDK_INT,
            "minControlPointMs" to capabilities.minControlPointMs,
            "maxControlPointMs" to capabilities.maxControlPointMs,
            "maxDurationMs" to capabilities.maxDurationMs,
            "maxSize" to capabilities.maxSize,
            "minFrequencyHz" to capabilities.minFrequencyHz.toDouble(),
            "maxFrequencyHz" to capabilities.maxFrequencyHz.toDouble(),
            "resonantFrequencyHz" to capabilities.resonantFrequencyHz.toDouble(),
            "hasAmplitudeControl" to capabilities.hasAmplitudeControl,
        )
    }

    fun setEnabled(value: Boolean): Boolean {
        if (!value) {
            enabled = false
            stopOutput()
            return true
        }

        val capabilities = resolveCapabilities()
        if (!capabilities.supported) {
            enabled = false
            stopOutput()
            return false
        }

        lastError = null
        enabled = true
        stopOutput()
        return true
    }

    fun pushEnvelope(
        amplitudes: List<Double>,
        frequencyPositions: List<Double>,
        sourcePointDurationMs: Int,
    ): Int {
        if (!enabled || Build.VERSION.SDK_INT < 36) {
            return 0
        }
        val capabilities = resolveCapabilities()
        if (!capabilities.supported || amplitudes.isEmpty()) {
            return 0
        }

        val count = min(amplitudes.size, frequencyPositions.size)
        if (count == 0) {
            return 0
        }
        val sourceDuration = sourcePointDurationMs.coerceAtLeast(1)
        val groupSize = max(
            1,
            ceil(capabilities.minControlPointMs.toDouble() / sourceDuration).toInt(),
        )
        val pointDuration = (groupSize * sourceDuration).coerceIn(
            capabilities.minControlPointMs,
            capabilities.maxControlPointMs,
        )

        var accepted = 0
        var index = 0
        while (index < count) {
            val end = min(index + groupSize, count)
            var amplitudeSum = 0.0
            var amplitudePeak = 0.0
            var weightedFrequency = 0.0
            var weight = 0.0
            for (sampleIndex in index until end) {
                val amplitude = amplitudes[sampleIndex].coerceIn(0.0, 1.0)
                val frequency = frequencyPositions[sampleIndex].coerceIn(0.0, 1.0)
                amplitudeSum += amplitude
                amplitudePeak = max(amplitudePeak, amplitude)
                val sampleWeight = max(0.02, amplitude)
                weightedFrequency += frequency * sampleWeight
                weight += sampleWeight
            }
            val averageAmplitude = amplitudeSum / (end - index)
            val resolvedAmplitude = (amplitudePeak * 0.58 + averageAmplitude * 0.42)
                .coerceIn(0.0, 1.0)
                .toFloat()
            val resolvedFrequency = if (weight > 0.0) {
                (weightedFrequency / weight).coerceIn(0.0, 1.0).toFloat()
            } else {
                0.5f
            }
            points.addLast(
                MotorPoint(
                    amplitude = resolvedAmplitude,
                    frequencyPosition = resolvedFrequency,
                    durationMs = pointDuration,
                ),
            )
            accepted += 1
            index = end
        }

        trimBacklog(capabilities)
        if (!running && points.size >= startupPointCount(capabilities)) {
            scheduleNextChunk()
        }
        return if (enabled) accepted else 0
    }

    fun stopOutput() {
        handler.removeCallbacks(scheduleNext)
        running = false
        points.clear()
        resolveVibrator()?.cancel()
    }

    fun release() {
        enabled = false
        stopOutput()
    }

    private fun startupPointCount(capabilities: Capabilities): Int {
        val duration = capabilities.minControlPointMs.coerceAtLeast(1)
        return (80 / duration).coerceIn(2, 8)
    }

    private fun trimBacklog(capabilities: Capabilities) {
        val maxBufferedPoints = (800 / capabilities.minControlPointMs.coerceAtLeast(1))
            .coerceIn(16, 96)
        while (points.size > maxBufferedPoints) {
            points.pollFirst()
        }
    }

    private fun scheduleNextChunk() {
        if (!enabled || Build.VERSION.SDK_INT < 36) {
            running = false
            return
        }
        val capabilities = resolveCapabilities()
        if (!capabilities.supported || points.isEmpty()) {
            running = false
            return
        }

        try {
            scheduleNextChunkApi36(capabilities)
        } catch (error: Throwable) {
            lastError = "马达包络输出失败: ${error.message ?: error.javaClass.simpleName}"
            enabled = false
            stopOutput()
        }
    }

    @RequiresApi(36)
    private fun scheduleNextChunkApi36(capabilities: Capabilities) {
        val vibrator = resolveVibrator() ?: return
        val terminalDuration = capabilities.minControlPointMs
        val maxPayloadPoints = min(capabilities.maxSize - 1, 32).coerceAtLeast(1)
        val chunk = ArrayList<MotorPoint>(maxPayloadPoints)
        var totalDuration = terminalDuration
        while (chunk.size < maxPayloadPoints && points.isNotEmpty()) {
            val next = points.peekFirst() ?: break
            if (chunk.isNotEmpty() &&
                totalDuration + next.durationMs > capabilities.maxDurationMs
            ) {
                break
            }
            points.pollFirst()
            chunk.add(next)
            totalDuration += next.durationMs
        }
        if (chunk.isEmpty()) {
            running = false
            return
        }

        val firstFrequency = mapFrequency(chunk.first().frequencyPosition, capabilities)
        val builder = VibrationEffect.WaveformEnvelopeBuilder()
            .setInitialFrequencyHz(firstFrequency)
        var lastFrequency = firstFrequency
        for (point in chunk) {
            val frequency = mapFrequency(point.frequencyPosition, capabilities)
            val amplitude = point.amplitude
                .coerceIn(0f, 1f)
                .pow(0.82f)
                .times(0.92f)
                .coerceIn(0f, 1f)
            builder.addControlPoint(amplitude, frequency, point.durationMs.toLong())
            lastFrequency = frequency
        }
        builder.addControlPoint(0f, lastFrequency, terminalDuration.toLong())

        val effect = builder.build()
        vibrator.vibrate(
            effect,
            VibrationAttributes.createForUsage(VibrationAttributes.USAGE_MEDIA),
        )
        running = true
        handler.postDelayed(
            scheduleNext,
            (totalDuration - 1).coerceAtLeast(1).toLong(),
        )
    }

    private fun mapFrequency(position: Float, capabilities: Capabilities): Float {
        val minFrequency = capabilities.minFrequencyHz
        val maxFrequency = capabilities.maxFrequencyHz
        if (maxFrequency <= minFrequency) {
            return capabilities.resonantFrequencyHz
        }

        val resonance = capabilities.resonantFrequencyHz.coerceIn(
            minFrequency,
            maxFrequency,
        )
        val availableSpan = maxFrequency - minFrequency
        val usefulSpan = availableSpan * 0.42f
        val usefulMin = max(minFrequency, resonance - usefulSpan * 0.55f)
        val usefulMax = min(maxFrequency, resonance + usefulSpan * 0.45f)
        return usefulMin + position.coerceIn(0f, 1f) * (usefulMax - usefulMin)
    }

    private fun resolveVibrator(): Vibrator? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return null
        }
        val manager = appContext.getSystemService(VibratorManager::class.java)
        return manager?.defaultVibrator
    }

    private fun resolveCapabilities(): Capabilities {
        cachedCapabilities?.let { return it }
        val resolved = if (Build.VERSION.SDK_INT < 36) {
            Capabilities(
                supported = false,
                reason = "需要 Android 16（API 36）或更高版本",
            )
        } else {
            resolveCapabilitiesApi36()
        }
        cachedCapabilities = resolved
        return resolved
    }

    @RequiresApi(36)
    private fun resolveCapabilitiesApi36(): Capabilities {
        val vibrator = resolveVibrator()
            ?: return Capabilities(false, "系统未提供振动器服务")
        if (!vibrator.hasVibrator()) {
            return Capabilities(false, "设备没有可用振动马达")
        }
        if (!vibrator.areEnvelopeEffectsSupported()) {
            return Capabilities(false, "设备不支持 Android 16 振动包络效果")
        }

        val info = vibrator.envelopeEffectInfo
        val profile = vibrator.frequencyProfile
            ?: return Capabilities(false, "设备未公开马达频率档案")
        val minFrequency = profile.minFrequencyHz
        val maxFrequency = profile.maxFrequencyHz
        val rawResonance = vibrator.resonantFrequency
        val resonance = when {
            rawResonance.isFinite() && rawResonance > 0f -> rawResonance
            minFrequency.isFinite() &&
                maxFrequency.isFinite() &&
                maxFrequency >= minFrequency -> (minFrequency + maxFrequency) * 0.5f
            else -> 0f
        }
        val validFrequencyRange =
            minFrequency.isFinite() &&
                maxFrequency.isFinite() &&
                minFrequency > 0f &&
                maxFrequency >= minFrequency &&
                resonance > 0f
        if (!validFrequencyRange) {
            return Capabilities(false, "设备未公开可用的马达频率范围")
        }

        val minControlPointMs = info.minControlPointDurationMillis
            .coerceAtLeast(1)
            .coerceAtMost(Int.MAX_VALUE.toLong())
            .toInt()
        val maxControlPointMs = info.maxControlPointDurationMillis
            .coerceAtLeast(minControlPointMs.toLong())
            .coerceAtMost(Int.MAX_VALUE.toLong())
            .toInt()
        val maxDurationMs = info.maxDurationMillis
            .coerceAtLeast((minControlPointMs * 3).toLong())
            .coerceAtMost(Int.MAX_VALUE.toLong())
            .toInt()
        val maxSize = info.maxSize
        if (maxSize < 3) {
            return Capabilities(false, "设备允许的包络控制点数量不足")
        }

        return Capabilities(
            supported = true,
            reason = "支持 Android 16 波形包络输出",
            minControlPointMs = minControlPointMs,
            maxControlPointMs = maxControlPointMs,
            maxDurationMs = maxDurationMs,
            maxSize = maxSize,
            minFrequencyHz = minFrequency,
            maxFrequencyHz = maxFrequency,
            resonantFrequencyHz = resonance.coerceIn(minFrequency, maxFrequency),
            hasAmplitudeControl = vibrator.hasAmplitudeControl(),
        )
    }
}
