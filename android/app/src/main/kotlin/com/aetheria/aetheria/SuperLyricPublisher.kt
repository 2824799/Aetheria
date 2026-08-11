package com.aetheria.aetheria

import com.hchen.superlyricapi.SuperLyricData
import com.hchen.superlyricapi.SuperLyricHelper
import com.hchen.superlyricapi.SuperLyricLine
import com.hchen.superlyricapi.SuperLyricWord

internal object SuperLyricPublisher {
    @Volatile
    private var registered = false

    @Synchronized
    fun initialize(): Boolean = ensureRegistered()

    fun publish(payload: Map<String, Any?>): Boolean {
        if (!ensureRegistered()) {
            return false
        }

        val lineText = payload.string("line")
        if (lineText.isNullOrBlank()) {
            return stop(payload)
        }

        return try {
            val data = buildMetadata(payload)
            val startTime = payload.long("startTimeMs")
            val endTime = payload.long("endTimeMs")
            val words = buildWords(payload)
            data.setLyric(buildLine(lineText, words, startTime, endTime))

            payload.string("secondary")
                ?.takeIf(String::isNotBlank)
                ?.let { data.setSecondary(buildLine(it, null, startTime, endTime)) }
            payload.string("translation")
                ?.takeIf(String::isNotBlank)
                ?.let { data.setTranslation(buildLine(it, null, startTime, endTime)) }

            SuperLyricHelper.sendLyric(data)
            true
        } catch (_: Throwable) {
            registered = false
            false
        }
    }

    fun stop(payload: Map<String, Any?> = emptyMap()): Boolean {
        if (!ensureRegistered()) {
            return false
        }

        return try {
            SuperLyricHelper.sendStop(buildMetadata(payload))
            true
        } catch (_: Throwable) {
            registered = false
            false
        }
    }

    @Synchronized
    fun dispose() {
        if (!registered) {
            return
        }

        try {
            SuperLyricHelper.sendStop(SuperLyricData())
            SuperLyricHelper.unregisterPublisher()
        } catch (_: Throwable) {
        } finally {
            registered = false
        }
    }

    @Synchronized
    private fun ensureRegistered(): Boolean {
        if (registered) {
            return true
        }

        return try {
            if (!SuperLyricHelper.isAvailable()) {
                false
            } else {
                if (!SuperLyricHelper.isPublisherRegistered()) {
                    SuperLyricHelper.registerPublisher()
                }
                SuperLyricHelper.isPublisherRegistered().also { isRegistered ->
                    registered = isRegistered
                    if (isRegistered) {
                        // Aetheria already sends explicit stop events. SuperLyric 3.3's
                        // service implementation treats `true` as publisher-managed
                        // playback state and excludes this package from its MediaSession
                        // auto-stop listener, despite the API method's historical name.
                        SuperLyricHelper.setSystemPlayStateListenerEnabled(true)
                    }
                }
            }
        } catch (_: Throwable) {
            registered = false
            false
        }
    }

    private fun buildMetadata(payload: Map<String, Any?>): SuperLyricData {
        val data = SuperLyricData()
        payload.string("title")
            ?.takeIf(String::isNotBlank)
            ?.let { data.setTitle(it) }
        payload.string("artist")
            ?.takeIf(String::isNotBlank)
            ?.let { data.setArtist(it) }
        payload.string("album")
            ?.takeIf(String::isNotBlank)
            ?.let { data.setAlbum(it) }
        return data
    }

    private fun buildLine(
        text: String,
        words: Array<SuperLyricWord>?,
        startTime: Long?,
        endTime: Long?,
    ): SuperLyricLine {
        if (startTime == null || endTime == null) {
            return SuperLyricLine(text)
        }

        val safeStart = startTime.coerceAtLeast(0L)
        val safeEnd = endTime.coerceAtLeast(safeStart + 1L)
        return SuperLyricLine(text, words, safeStart, safeEnd)
    }

    private fun buildWords(payload: Map<String, Any?>): Array<SuperLyricWord>? {
        val rawWords = payload["words"] as? List<*> ?: return null
        val words = rawWords.mapNotNull { rawWord ->
            val wordPayload = rawWord as? Map<*, *> ?: return@mapNotNull null
            val text = wordPayload.string("text")
            val startTime = wordPayload.long("startTimeMs")
            val endTime = wordPayload.long("endTimeMs")
            if (text.isNullOrEmpty() || startTime == null || endTime == null) {
                return@mapNotNull null
            }

            val safeStart = startTime.coerceAtLeast(0L)
            val safeEnd = endTime.coerceAtLeast(safeStart + 1L)
            SuperLyricWord(text, safeStart, safeEnd)
        }
        return words.takeIf(List<SuperLyricWord>::isNotEmpty)?.toTypedArray()
    }

    private fun Map<*, *>.string(key: String): String? =
        this[key]?.toString()

    private fun Map<*, *>.long(key: String): Long? =
        (this[key] as? Number)?.toLong()
}
