package dev.riflay.riflay

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.ostrichbat2k.usbdac.UsbAudioManager
import org.ostrichbat2k.usbdac.UsbAudioManagerImpl
import org.ostrichbat2k.usbdac.UsbDacPreferences
import org.ostrichbat2k.usbdac.streaming.RoutingAudioSink
import java.io.DataInputStream
import java.io.EOFException
import java.io.File
import java.io.FileInputStream
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
//
// Nothing here may take the app down: it is experimental and talks to hardware. Every call from Dart answers (an
// error at worst), the reader and the library's own threads end in "Direct USB stopped" instead of a force close
// (see guardThreads), and a reader that stops takes the FIFO away, so mpv's next open makes a plain file instead of
// waiting for good on a pipe nobody reads. Dart then sends the songs back through Android.
object DirectUsb {
    private const val TAG = "DirectUsb"

    // mpv blocks writing into a full pipe, and with it every call Dart makes into mpv on the UI thread: a sink that
    // stops taking audio froze the app (ANR, on a KTMicro DAC). libusbdac's fallback, Android's own track, goes silent
    // once the library claims the DAC away from Android: its switch to the USB stream then waits for that track to
    // drain (handleBuffer false for good), or a blocking AudioTrack.write never returns.
    //
    // So: each stream waits up to ACTIVATION_MS for the DAC first, so it starts on the USB stream itself; a sink that
    // refuses audio for STALL_MS is flushed once (a waiting switch goes through); and the watchdog, on its own
    // thread, ends Direct USB when the sink has made no progress for WATCHDOG_MS, whatever call it is stuck in, by
    // closing the pipe, which frees mpv at once. The songs then go back through Android.
    private const val ACTIVATION_MS = 1500L
    private const val STALL_MS = 1000L
    private const val WATCHDOG_MS = 2500L

    /** When the reader handed the sink audio it hasn't taken yet; 0 while it isn't waiting on the sink. */
    @Volatile private var sinkSince = 0L
    @Volatile private var pipe: FileInputStream? = null

    private var context: Context? = null
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(
        SupervisorJob() + Dispatchers.Main + CoroutineExceptionHandler { _, e -> Log.w(TAG, "Direct USB status", e) },
    )

    private var manager: UsbAudioManager? = null
    private var worker: Thread? = null
    @Volatile private var running = false
    // Not paused until told: a paused mpv writes nothing anyway, and Direct USB may start mid-song.
    @Volatile private var paused = false
    @Volatile private var flushWanted = false

    // What the screens show (Signal path, Settings): updated from the reader and the library.
    @Volatile private var streamFormat: String? = null
    @Volatile private var lastError: String? = null
    @Volatile private var route: String = "none"
    @Volatile private var routeFormat: String? = null
    @Volatile private var underruns = 0
    @Volatile private var log: List<String> = emptyList()

    // Off with RIFLAY_NO_DIRECT_USB_GUARD (Dart sends it with "enable"), so the real crash shows in logcat.
    private var guard = true
    private var guarded = false

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
                try {
                    handle(call.method, call.arguments, result)
                } catch (e: Throwable) {
                    // Flutter only catches RuntimeException here: an Error (a missing native library, say) would end
                    // the app. Dart gets an error and carries on through Android.
                    Log.e(TAG, "Direct USB ${call.method} failed", e)
                    lastError = "Direct USB ${call.method} failed: ${e.message ?: e.javaClass.simpleName}"
                    result.error("direct_usb", lastError, null)
                }
            }
        }
    }

    private fun handle(method: String, arguments: Any?, result: MethodChannel.Result) {
        when (method) {
            "state" -> result.success(state())
            "enable" -> {
                // {on, guard}; a plain Boolean from an older Dart side.
                val args = arguments as? Map<*, *>
                guard = args?.get("guard") as? Boolean ?: true
                result.success(enable(args?.get("on") as? Boolean ?: arguments as? Boolean ?: false))
            }
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
            "requestPermission" -> {
                manager?.devices?.value?.firstOrNull { !it.hasPermission }?.let { manager?.requestPermission(it.device) }
                result.success(null)
            }
            else -> result.notImplemented()
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
        if (guard) guardThreads()
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
        val m = try {
            manager ?: UsbAudioManagerImpl(ctx, prefs).also {
                manager = it
                it.start()
                watch(it)
            }
        } catch (e: Throwable) {
            lastError = "Couldn't start the USB driver: ${e.message ?: e.javaClass.simpleName}"
            Log.e(TAG, lastError!!, e)
            fifo(ctx).delete()
            changed()
            return null
        }
        running = true
        lastError = null
        try {
            prefs.changed()
            // Ask for the DAC right away, so the first song doesn't start before permission is there. The library
            // asks too (retryActivation) when nothing is granted yet; Android shows one dialog either way.
            m.devices.value.firstOrNull { !it.hasPermission }?.let { m.requestPermission(it.device) }
        } catch (e: Throwable) {
            // No permission dialog is no reason to stop: "Allow USB access" in Settings asks again.
            Log.w(TAG, "Asking for the USB DAC failed", e)
        }
        sinkSince = 0L
        worker = Thread({ read(ctx, m) }, "riflay-direct-usb").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
        Thread({ watch(ctx) }, "riflay-direct-usb-watchdog").apply {
            isDaemon = true
            start()
        }
        changed()
        return fifo(ctx).path
    }

    /** See WATCHDOG_MS. Runs while Direct USB does; never touches the sink itself (it isn't thread-safe). */
    private fun watch(ctx: Context) {
        while (running) {
            try {
                Thread.sleep(250)
            } catch (_: InterruptedException) {
                return
            }
            val since = sinkSince
            if (!running || since == 0L || SystemClock.elapsedRealtime() - since < WATCHDOG_MS) continue
            Log.e(TAG, "The sink took no audio for $WATCHDOG_MS ms; Direct USB is off")
            fail(ctx, "The USB DAC stopped taking audio")
            // The last reader gone, mpv's blocked write fails at once (SIGPIPE is ignored, see ignoreBrokenPipes).
            try {
                pipe?.close()
            } catch (_: IOException) {
            }
            return
        }
    }

    /**
     * The reader or one of libusbdac's threads (activation, claim, streaming, volume) failed: Direct USB turns off,
     * and Dart, told it no longer runs, sends the songs back through Android. Any thread; does no blocking work.
     */
    private fun fail(ctx: Context, why: String) {
        lastError = why
        running = false
        route = "none"
        // A reader still waiting on the pipe lets go; mpv's next open of the path makes a plain file instead of
        // waiting for a reader that is gone.
        releaseReader(ctx)
        fifo(ctx).delete()
        main.post {
            try {
                prefs.changed()
            } catch (e: Throwable) {
                Log.w(TAG, "Releasing the USB DAC failed", e)
            }
            changed()
        }
    }

    /**
     * An uncaught exception on a thread of the reader or of libusbdac ends Direct USB, not the app: Android's default
     * handler kills the process for any thread. The main thread and every other thread keep that handler. The trace
     * is still logged ("FATAL EXCEPTION" from Android's own logger, then ours), so logcat shows what went wrong.
     */
    private fun guardThreads() {
        if (guarded) return
        guarded = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            val ctx = context
            if (guard && ctx != null && thread !== Looper.getMainLooper().thread && fromUsb(thread, e)) {
                Log.e(TAG, "Direct USB thread ${thread.name} failed; Direct USB is off", e)
                fail(ctx, "Direct USB stopped: ${e.message ?: e.javaClass.simpleName}")
            } else {
                previous?.uncaughtException(thread, e)
            }
        }
    }

    private fun fromUsb(thread: Thread, e: Throwable): Boolean {
        if (thread.name.startsWith("riflay-direct-usb") || thread.name.startsWith("UsbAudio")) return true
        var c: Throwable? = e
        var depth = 0
        while (c != null && depth++ < 8) {
            if (c.stackTrace.any { it.className.startsWith("org.ostrichbat2k.usbdac") || it.className.startsWith("dev.riflay.riflay.DirectUsb") }) {
                return true
            }
            c = c.cause
        }
        return false
    }

    private fun stop(ctx: Context) {
        if (!running) return
        running = false
        try {
            prefs.changed()
        } catch (e: Throwable) {
            Log.w(TAG, "Releasing the USB DAC failed", e)
        }
        releaseReader(ctx)
        worker?.join(2000)
        worker = null
        try {
            manager?.releaseClaim(0)
        } catch (e: Throwable) {
            Log.w(TAG, "Releasing the USB DAC failed", e)
        }
        fifo(ctx).delete()
        route = "none"
        changed()
    }

    /**
     * The reader may be waiting for mpv to open the FIFO: opening it for writing here lets it go. Non-blocking: with
     * no reader there (it just ended) a plain open would wait for good.
     */
    private fun releaseReader(ctx: Context) {
        try {
            Os.close(Os.open(fifo(ctx).path, OsConstants.O_WRONLY or OsConstants.O_NONBLOCK, 0))
        } catch (_: Exception) {
        }
    }

    private fun watch(m: UsbAudioManager) {
        scope.launch {
            combine(m.devices, m.playbackRoute, m.pipelineStats, m.diagnosticLog) { _, r, stats, entries ->
                val was = route
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
                // libusbdac logs through Timber, which says nothing here: its own log goes to logcat instead.
                entries.filter { it !in log }.forEach { Log.i(TAG, "libusbdac: $it") }
                if (route != was) Log.i(TAG, "route $route ${routeFormat ?: ""}")
                log = entries
            }.catch { Log.w(TAG, "Direct USB status", it) }.collect { changed() }
        }
    }

    // ── The reader ──────────────────────────────────────────────────────────────────────────────

    private class Wav(val encoding: Int, val channels: Int, val rate: Int, val frameBytes: Int, val label: String)

    // What the pipe reader hands the feeder: a new stream's format, or samples in it.
    private class Chunk(val wav: Wav, val bytes: ByteArray, val length: Int)

    private val queue = java.util.concurrent.LinkedBlockingQueue<Chunk>()
    private val queued = java.util.concurrent.atomic.AtomicLong()

    // At most this many seconds of audio wait in memory; the reader only stops reading the pipe (and mpv's writes
    // block) past it. A DAC that is still activating, a sink that is slow to start: the audio waits here, not in
    // the pipe, so mpv's lock is never held through them (see AudioEngine.directUsbPaceFilter).
    private const val QUEUE_SECONDS = 10

    /**
     * Two threads: this one empties the pipe as soon as mpv writes into it, and [feed] hands the audio to the sink
     * at the DAC's pace. One thread doing both held mpv's writes while the sink waited (the DAC activating, Android's
     * track starting), and once behind, mpv never caught up: its writes kept blocking with its lock held.
     */
    private fun read(ctx: Context, m: UsbAudioManager) {
        queue.clear()
        queued.set(0)
        val feeder = Thread({ feed(ctx, m) }, "riflay-direct-usb-sink").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
        var loggedAt = SystemClock.elapsedRealtime()
        var readBytes = 0L
        try {
            while (running) {
                // Blocks until mpv opens it for writing (a new output, after a format change or a reload).
                val input = try {
                    DataInputStream(FileInputStream(fifo(ctx)).also { pipe = it })
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
                    val limit = QUEUE_SECONDS.toLong() * wav.rate * wav.frameBytes
                    while (running) {
                        val chunk = ByteArray(16 * 1024)
                        val n = stream.read(chunk, 0, chunk.size - chunk.size % wav.frameBytes)
                        if (n < 0) break
                        if (n == 0) continue
                        queue.put(Chunk(wav, chunk, n))
                        readBytes += n
                        val now = SystemClock.elapsedRealtime()
                        if (now - loggedAt > 5000) {
                            Log.i(TAG, "read ${readBytes * 1000 / (now - loggedAt)} B/s; waiting ${queued.get()} B, pipe ${stream.available()} B")
                            loggedAt = now
                            readBytes = 0
                        }
                        // Far ahead of the DAC: wait here, the one place mpv is meant to wait.
                        while (running && queued.get() + n > limit) Thread.sleep(20)
                        queued.addAndGet(n.toLong())
                    }
                }
            }
        } catch (e: Throwable) {
            // Not only Exception: an Error here (a native library that won't load, out of memory) ended the app.
            Log.e(TAG, "Direct USB stopped", e)
            if (running) fail(ctx, "Direct USB stopped: ${e.message ?: e.javaClass.simpleName}")
        } finally {
            feeder.interrupt()
            feeder.join(2000)
        }
    }

    /** Hands what [read] queued to libusbdac's sink. Owns the sink: it is not thread-safe. */
    private fun feed(ctx: Context, m: UsbAudioManager) {
        var sink: AudioSink? = null
        var current: Wav? = null
        var framesWritten = 0L
        var playing = false
        val buffer = ByteBuffer.allocateDirect(16 * 1024).order(ByteOrder.LITTLE_ENDIAN)
        try {
            Looper.prepare()
            val out: AudioSink = RoutingAudioSink(m, DefaultAudioSink.Builder(ctx).build())
            sink = out
            while (running) {
                if (flushWanted) {
                    flushWanted = false
                    // What mpv wrote before the seek: dropped with what the sink holds.
                    queue.clear()
                    queued.set(0)
                    out.flush()
                    framesWritten = 0
                    playing = false
                }
                if (paused) {
                    if (playing) {
                        out.pause()
                        playing = false
                    }
                    Thread.sleep(20)
                    continue
                }
                val c = queue.poll(20, java.util.concurrent.TimeUnit.MILLISECONDS) ?: continue
                queued.addAndGet(-c.length.toLong())
                val wav = c.wav
                if (current == null || current!!.label != wav.label) {
                    // On the USB stream from the start rather than on Android's track, which the DAC's claim
                    // silences (see ACTIVATION_MS). Returns at once when nothing is activating.
                    try {
                        m.triggerActivation()
                        runBlocking { m.awaitActivation(ACTIVATION_MS) }
                    } catch (e: Exception) {
                        Log.w(TAG, "Waiting for the USB DAC", e)
                    }
                    out.flush()
                    out.configure(format(wav), 0, null)
                    current = wav
                    framesWritten = 0
                    playing = false
                    streamFormat = wav.label
                    lastError = null
                    changed()
                }
                buffer.clear()
                buffer.put(c.bytes, 0, c.length)
                buffer.flip()
                if (!playing) {
                    out.play()
                    playing = true
                }
                val pts = framesWritten * 1_000_000L / wav.rate
                var refusedSince = 0L
                var unstuck = false
                sinkSince = SystemClock.elapsedRealtime()
                while (buffer.hasRemaining() && running && !flushWanted) {
                    if (out.handleBuffer(buffer, pts, 1)) {
                        refusedSince = 0L
                        sinkSince = SystemClock.elapsedRealtime()
                        continue
                    }
                    val now = SystemClock.elapsedRealtime()
                    if (refusedSince == 0L) {
                        refusedSince = now
                    } else if (now - refusedSince > STALL_MS) {
                        // Dropping what the sink holds lets a waiting switch go through; still stuck after that,
                        // Direct USB stops and the songs go back through Android.
                        if (unstuck) throw IllegalStateException("The USB DAC stopped taking audio")
                        Log.w(TAG, "The sink took no audio for $STALL_MS ms; flushing it")
                        out.flush()
                        out.play()
                        unstuck = true
                        refusedSince = now
                    }
                    Thread.sleep(4)
                }
                sinkSince = 0L
                framesWritten += c.length / wav.frameBytes
            }
        } catch (_: InterruptedException) {
            // Direct USB is stopping.
        } catch (e: Throwable) {
            Log.e(TAG, "Direct USB stopped", e)
            if (running) fail(ctx, "Direct USB stopped: ${e.message ?: e.javaClass.simpleName}")
            // The reader may be waiting on a full queue or on the pipe: closing the pipe lets mpv go too.
            try {
                pipe?.close()
            } catch (_: IOException) {
            }
        } finally {
            try {
                sink?.reset()
                sink?.release()
            } catch (_: Throwable) {
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
        // A header with no channels or rate would divide by zero below.
        if (channels !in 1..32 || rate <= 0) return null.also { lastError = "Unsupported stream ($channels ch, $rate Hz)" }
        val label = "${if (fmt == 3) "float" else "$bits-bit"} / $rate Hz / $channels ch"
        return Wav(encoding, channels, rate, channels * bits / 8, label)
    }
}
