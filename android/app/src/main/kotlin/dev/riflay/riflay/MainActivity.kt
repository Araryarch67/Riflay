package dev.riflay.riflay

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service's activity shares its Flutter engine with the playback service,
// so music keeps playing (with its notification) after the app is closed.
class MainActivity : AudioServiceActivity() {
    private var pending: MethodChannel.Result? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    private val musicPermission =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE

    // "Add folder" reads the songs where they are, which takes the permission to read music
    // (picked files are copies the system may clear).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "riflay/music_permission").setMethodCallHandler { call, result ->
            if (call.method != "request") return@setMethodCallHandler result.notImplemented()
            if (checkSelfPermission(musicPermission) == PackageManager.PERMISSION_GRANTED) return@setMethodCallHandler result.success(true)
            pending?.success(false)
            pending = result
            requestPermissions(arrayOf(musicPermission), REQUEST)
        }
        // Looking for AirPlay speakers (mDNS) needs Wi-Fi to pass multicast packets on.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "riflay/multicast").setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    if (multicastLock == null) {
                        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        multicastLock = wifi.createMulticastLock("riflay-cast").apply { setReferenceCounted(false) }
                    }
                    multicastLock?.acquire()
                    result.success(null)
                }
                "release" -> {
                    multicastLock?.takeIf { it.isHeld }?.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST) return
        pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pending = null
    }

    private companion object {
        const val REQUEST = 7301
    }
}
