package dev.riflay.riflay

import android.content.Context
import android.content.Intent
import android.os.Process
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

// Ends the process with its Flutter engine. audio_service destroys the engine once the app is closed and its
// playback service has stopped, but Android keeps the process, and in it every mpv player Dart made: nothing is
// left to dispose them. Each still holds its wakeup callback, a Dart function whose code went away with the engine,
// and mpv's next event (a log line while a music video was still opening, in the crash this is for) jumps into
// unmapped memory: a native crash in libmpv.so some time after Riflay was closed. Nothing of the app runs past
// the engine anyway (the next launch starts Dart afresh either way), so the process goes before the engine does.
// Off with RIFLAY_NO_ENGINE_EXIT (Dart sends "keep"), so the process stays as it did.
object EngineEnd {
    private const val TAG = "EngineEnd"
    private var keep = false
    private var watched = WeakReference<FlutterEngine>(null)

    // Called for each activity; one listener per engine.
    fun attach(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "riflay/engine_end").setMethodCallHandler { call, result ->
            if (call.method != "keep") return@setMethodCallHandler result.notImplemented()
            keep = true
            result.success(null)
        }
        if (watched.get() === engine) return
        watched = WeakReference(engine)
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}

            // Before the engine lets go of anything: Dart, its callbacks and the video's surface are all still there.
            override fun onEngineWillDestroy() {
                if (keep) return
                Log.i(TAG, "The Flutter engine ends: ending the process with it")
                // The downloads' foreground service is sticky: left running, the system would start the process
                // again for it, without Dart to download anything.
                try {
                    context.stopService(
                        Intent().setClassName(context, "com.dexterous.flutterlocalnotifications.ForegroundService"),
                    )
                } catch (e: RuntimeException) {
                    Log.w(TAG, "Stopping the downloads service: $e")
                }
                Process.killProcess(Process.myPid())
            }
        })
    }
}
