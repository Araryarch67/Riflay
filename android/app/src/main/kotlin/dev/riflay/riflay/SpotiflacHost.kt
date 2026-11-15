package dev.riflay.riflay

import android.os.Handler
import android.os.Looper
import bridge.Bridge
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

// Blocking extension work never runs on the UI thread. Separate workers keep
// progress and cancellation callable while a download is running.
object SpotiflacHost {
    private val workers = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var root: String? = null
    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, "riflay/spotiflac").setMethodCallHandler { call, result ->
            workers.execute {
                try {
                    val reply: Any? = when (call.method) {
                        "initialize" -> synchronized(this) {
                            val path = requireNotNull(call.argument<String>("directory"))
                            if (root != path) { Bridge.initialize(path); root = path }
                            null
                        }
                        "invoke" -> Bridge.invoke(requireNotNull(call.argument<String>("payload")), requireNotNull(root))
                        "shutdown" -> synchronized(this) { Bridge.shutdown(); root = null; null }
                        else -> { main.post { result.notImplemented() }; return@execute }
                    }
                    main.post { result.success(reply) }
                } catch (_: Exception) {
                    main.post { result.error("extension", "Couldn't complete the extension request.", null) }
                }
            }
        }
    }
}
