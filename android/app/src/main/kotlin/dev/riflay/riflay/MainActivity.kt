package dev.riflay.riflay

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Resources
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service's activity shares its Flutter engine with the playback service,
// so music keeps playing (with its notification) after the app is closed.
class MainActivity : AudioServiceActivity() {
    private var pending: MethodChannel.Result? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    // Settings > Appearance > Window opacity below 100%: the home-screen wallpaper shows behind the app.
    // A translucent window and a transparent Flutter surface cost frame time, so they are only used then.
    // The theme is read when the window is made, hence the flag is kept here and the activity restarted
    // (its Flutter engine, and so the app's state and the music, carries on) when it changes.
    private val seeThrough get() = getSharedPreferences("window", MODE_PRIVATE).getBoolean("seeThrough", false)
    private var seeThroughNow = false

    override fun onCreate(savedInstanceState: Bundle?) {
        seeThroughNow = seeThrough
        super.onCreate(savedInstanceState)
        if (seeThroughNow) window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
    }

    // Flutter swaps in the app's normal theme in onCreate, which would drop the see-through attributes.
    override fun onApplyThemeResource(theme: Resources.Theme, resid: Int, first: Boolean) {
        super.onApplyThemeResource(theme, resid, first)
        if (seeThroughNow) theme.applyStyle(R.style.SeeThrough, true)
    }

    override fun getBackgroundMode() = if (seeThroughNow) BackgroundMode.transparent else BackgroundMode.opaque

    private val musicPermission =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE

    // "Add folder" reads the songs where they are, which takes the permission to read music
    // (picked files are copies the system may clear).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "riflay/window").setMethodCallHandler { call, result ->
            val on = call.arguments as? Boolean
            if (call.method != "setSeeThrough" || on == null) return@setMethodCallHandler result.notImplemented()
            getSharedPreferences("window", MODE_PRIVATE).edit().putBoolean("seeThrough", on).apply()
            result.success(null)
            if (on != seeThroughNow) recreate()
        }
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

    // The activity is recreated when see-through turns on or off: a search's lock goes with the old one.
    override fun onDestroy() {
        multicastLock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
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
