package dev.riflay.riflay

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.system.OsConstants
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.ostrichbat2k.usbdac.UsbAudioManager
import org.ostrichbat2k.usbdac.UsbAudioManagerImpl
import org.ostrichbat2k.usbdac.UsbDacPreferences
import org.ostrichbat2k.usbdac.streaming.RoutingAudioSink
import java.io.DataInputStream
import java.io.EOFException
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder

// Direct USB (Settings > Sound > Output & quality): bit-perfect to a USB DAC on any phone, not only one whose
// maker offers Android 14's bit-perfect mixer. mpv writes the decoded song (ao=pcm, a WAV header per stream) into
// a FIFO; this reads it and hands the samples to libusbdac's RoutingAudioSink, which claims the DAC's USB
// interface and streams to it itself, or, for a format the DAC can't take, plays through Android as usual.
//
// One per process, not per activity: the activity is recreated (see-through) while the music plays on in the
// shared engine, and mpv waits on the FIFO for a reader, so the reader must never go away with an activity.
object DirectUsb {
    private const val TAG = "DirectUsb"

    private var context: Context? = null
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var manager: UsbAudioManager? = null
    private var worker: Thread? = null
    @Volatile private var running = false
    // Not paused until told: a paused mpv writes nothing anyway, and Direct USB may start mid-song.
    @Volatile private var paused = false
    @Volatile private var flushWanted = false
    /** The song's own bit depth when it is narrower than the container mpv writes (24 in 32). */
    @Volatile private var sourceBits: Int? = null

    // What the screens show (Signal path, Settings): updated from the reader and the library.
    @Volatile private var streamFormat: String? = null
    @Volatile private var lastError: String? = null
    @Volatile private var route: String = "none"
    @Volatile private var routeFormat: String? = null
    @Volatile private var underruns = 0
    @Volatile private var log: List<String> = emptyList()

    private val prefs = object : UsbDacPreferences {
        private val listeners = mutableSetOf<UsbDacPreferences.Listener>()
        override val enabled get() = running
        override val bitPerfectMode get() = true
        override var volumeDb: Int? = null
        override val abxTestMode get() = false
        override val volumeStepPercent get() = 5
        override fun registerListener(listener: UsbDacPreferences.Listener) {
            listeners += listener
        }
        override fun unregisterListener(listener: UsbDacPreferences.Listener) {
            listeners -= listener
        }
        fun changed() = listeners.toList().forEach { it.onUsbEnabledChanged() }
    }

    fun fifo(context: Context) = File(context.cacheDir, "direct_usb.fifo")

    fun attach(context: Context, messenger: BinaryMessenger) {
        this.context = context.applicationContext
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, "riflay/direct_usb").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "state" -> result.success(state())
                    "enable" -> result.success(enable(call.arguments as? Boolean ?: false))
                    "play" -> {
                        paused = false
                        result.success(null)
                    }
                    "pause" -> {
                        paused = true
                        result.success(null)
                    }
                    "flush" -> {
                        flushWanted = true
                        result.success(null)
                    }
                    "sourceBits" -> {
                        sourceBits = call.arguments as? Int
                        result.success(null)
                    }
                    "requestPermission" -> {
                        manager?.devices?.value?.firstOrNull { !it.hasPermission }?.let { manager?.requestPermission(it.device) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun changed() = main.post { channel?.invokeMethod("changed", state()) }

    private fun state(): Map<String, Any?> {
        val devices = manager?.devices?.value.orEmpty()
        return mapOf(
            "running" to running,
            "fifo" to context?.let { fifo(it).path },
            "devices" to devices.map { mapOf("name" to it.displayName, "permission" to it.hasPermission) },
            "route" to route,
            "routeFormat" to routeFormat,
            "streamFormat" to streamFormat,
            "underruns" to underruns,
            "error" to lastError,
            "log" to log.take(12),
        )
    }

    /** Turns Direct USB on (the reader waits on the FIFO for mpv) or off. Returns the FIFO's path, or null. */
    private fun enable(on: Boolean): String? {
        val ctx = context ?: return null
        if (!on) {
            stop(ctx)
            return null
        }
        if (running) return fifo(ctx).path
        try {
            val f = fifo(ctx)
            if (f.exists()) f.delete()
            Os.mkfifo(f.path, OsConstants.S_IRUSR or OsConstants.S_IWUSR)
        } catch (e: Exception) {
            lastError = "Couldn't make the audio pipe: ${e.message}"
            Log.w(TAG, lastError!!)
            changed()
            return null
        }
        // mpv hands 24-bit songs over in a 32-bit container: say so, and they go out on the DAC's 24-bit format.
        val m = manager ?: UsbAudioManagerImpl(ctx, prefs, realBitsPerSample = { f ->
            if (f.pcmEncoding == C.ENCODING_PCM_32BIT && sourceBits == 24) 24 else null
        }).also {
            manager = it
            it.start()
            watch(it)
        }
        running = true
        prefs.changed()
        // Ask for the DAC right away, so the first song doesn't start before permission is there.
        m.devices.value.firstOrNull { !it.hasPermission }?.let { m.requestPermission(it.device) }
        worker = Thread({ read(ctx, m) }, "riflay-direct-usb").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
        changed()
        return fifo(ctx).path
    }

    private fun stop(ctx: Context) {
        if (!running) return
        running = false
        prefs.changed()
        // The reader may be waiting for mpv to open the FIFO: opening it for writing here lets it go.
        try {
            FileOutputStream(fifo(ctx)).close()
        } catch (_: IOException) {
        }
        worker?.join(2000)
        worker = null
        manager?.releaseClaim(0)
        route = "none"
        changed()
    }

    private fun watch(m: UsbAudioManager) {
        scope.launch {
            combine(m.devices, m.playbackRoute, m.pipelineStats, m.diagnosticLog) { _, r, stats, entries ->
                route = when (r) {
                    is UsbAudioManager.PlaybackRoute.Direct -> "direct"
                    is UsbAudioManager.PlaybackRoute.Fallback -> "fallback"
                    else -> "none"
                }
                routeFormat = when (r) {
                    is UsbAudioManager.PlaybackRoute.Direct -> "${r.bitDepth ?: "?"}-bit / ${r.sampleRateHz} Hz"
                    is UsbAudioManager.PlaybackRoute.Fallback -> "${r.bitDepth ?: "?"}-bit / ${r.sampleRateHz} Hz"
                    else -> null
                }
                underruns = stats?.underrunCount ?: underruns
                log = entries
            }.collect { changed() }
        }
    }

    // ── The reader ──────────────────────────────────────────────────────────────────────────────

    private class Wav(val encoding: Int, val channels: Int, val rate: Int, val frameBytes: Int, val label: String)

    private fun read(ctx: Context, m: UsbAudioManager) {
        Looper.prepare()
        val sink: AudioSink = RoutingAudioSink(m, DefaultAudioSink.Builder(ctx).build())
        var current: Wav? = null
        var framesWritten = 0L
        val chunk = ByteArray(16 * 1024)
        val buffer = ByteBuffer.allocateDirect(chunk.size).order(ByteOrder.LITTLE_ENDIAN)
        try {
            while (running) {
                // Blocks until mpv opens it for writing (a new output, after a format change or a reload).
                val input = try {
                    DataInputStream(FileInputStream(fifo(ctx)))
                } catch (e: IOException) {
                    lastError = "Couldn't open the audio pipe: ${e.message}"
                    changed()
                    Thread.sleep(500)
                    continue
                }
                input.use { stream ->
                    val wav = try {
                        header(stream)
                    } catch (_: EOFException) {
                        null
                    } ?: return@use
                    if (current == null || current!!.label != wav.label) {
                        sink.flush()
                        sink.configure(format(wav), 0, null)
                        current = wav
                        framesWritten = 0
                        streamFormat = wav.label
                        lastError = null
                        changed()
                    }
                    var playing = false
                    while (running) {
                        if (flushWanted) {
                            flushWanted = false
                            // What mpv wrote before the seek is still in the pipe: drop it with what the sink holds.
                            while (stream.available() > 0) stream.skip(stream.available().toLong())
                            sink.flush()
                            framesWritten = 0
                            playing = false
                        }
                        if (paused) {
                            if (playing) {
                                sink.pause()
                                playing = false
                            }
                            Thread.sleep(20)
                            continue
                        }
                        val n = stream.read(chunk, 0, chunk.size - chunk.size % wav.frameBytes)
                        if (n < 0) break
                        if (n == 0) continue
                        buffer.clear()
                        buffer.put(chunk, 0, n)
                        buffer.flip()
                        if (!playing) {
                            sink.play()
                            playing = true
                        }
                        val pts = framesWritten * 1_000_000L / wav.rate
                        while (buffer.hasRemaining() && running && !flushWanted) {
                            if (!sink.handleBuffer(buffer, pts, 1)) Thread.sleep(4)
                        }
                        framesWritten += n / wav.frameBytes
                    }
                }
            }
        } catch (e: Exception) {
            lastError = "Direct USB stopped: ${e.message}"
            Log.w(TAG, lastError!!, e)
            running = false
            changed()
        } finally {
            try {
                sink.reset()
                sink.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun format(w: Wav): Format = Format.Builder()
        .setSampleMimeType(MimeTypes.AUDIO_RAW)
        .setPcmEncoding(w.encoding)
        .setChannelCount(w.channels)
        .setSampleRate(w.rate)
        .build()

    /** The WAV header mpv's ao_pcm writes: RIFF, WAVE, then chunks up to `data` (whose size it can't know). */
    private fun header(s: DataInputStream): Wav? {
        fun u16() = Integer.reverseBytes(s.readUnsignedShort() shl 16)
        fun u32() = Integer.reverseBytes(s.readInt())
        fun tag(): String = ByteArray(4).also { s.readFully(it) }.toString(Charsets.US_ASCII)
        if (tag() != "RIFF") return null
        u32()
        if (tag() != "WAVE") return null
        var fmt = 0
        var channels = 0
        var rate = 0
        var bits = 0
        while (true) {
            val id = tag()
            val size = u32()
            if (id == "data") break
            if (id == "fmt ") {
                fmt = u16()
                channels = u16()
                rate = u32()
                u32()
                u16()
                bits = u16()
                var left = size - 16
                if (fmt == 0xFFFE && left >= 24) {
                    u16()
                    u16()
                    u32()
                    fmt = u16() // the sub-format GUID starts with the plain format code
                    s.skipBytes(14)
                    left -= 24
                }
                if (left > 0) s.skipBytes(left)
            } else {
                s.skipBytes(size)
            }
        }
        val encoding = when {
            fmt == 3 && bits == 32 -> C.ENCODING_PCM_FLOAT
            fmt == 1 && bits == 16 -> C.ENCODING_PCM_16BIT
            fmt == 1 && bits == 24 -> C.ENCODING_PCM_24BIT
            fmt == 1 && bits == 32 -> C.ENCODING_PCM_32BIT
            else -> return null.also { lastError = "Unsupported stream (format $fmt, $bits-bit)" }
        }
        val label = "${if (fmt == 3) "float" else "$bits-bit"} / $rate Hz / $channels ch"
        return Wav(encoding, channels, rate, channels * bits / 8, label)
    }
}
