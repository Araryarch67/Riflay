package dev.riflay.riflay

import android.Manifest
import android.content.Context
import android.content.Intent
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
    private var usbDac: UsbDac? = null
    private var appUpdater: AppUpdater? = null

    // Settings > Appearance > Window opacity below 100%: the home-screen wallpaper shows behind the app.
    // A translucent window and a transparent Flutter surface cost frame time, so they are only used then.
    // The theme is read when the window is made, hence the flag is kept here and the activity restarted
    // (its Flutter engine, and so the app's state and the music, carries on) when it changes.
    private val seeThrough get() = getSharedPreferences("window", MODE_PRIVATE).getBoolean("seeThrough", false)
    private var seeThroughNow = false

    // A YouTube link opened ("Open with") or shared with Riflay, until Dart takes it (riflay/incoming_link,
    // lib/services/incoming_links.dart). Kept here because Dart may not be listening yet on a cold start.
    private var incomingLink: String? = null
    private var incomingLinks: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        seeThroughNow = seeThrough
        // Not when see-through recreates the activity: its intent was handled already.
        if (savedInstanceState == null) incomingLink = linkOf(intent)
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
        usbDac = UsbDac(this, flutterEngine.dartExecutor.binaryMessenger)
        // Not disposed with the activity: it feeds the DAC while the music plays on without it.
        DirectUsb.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        PowerControl(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        appUpdater = AppUpdater(this, flutterEngine.dartExecutor.binaryMessenger)
        // Share: Android's own share sheet (messaging apps, Nearby Share…) with the song's name and link.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "riflay/share").setMethodCallHandler { call, result ->
            val text = call.argument<String>("text")
            if (call.method != "share" || text == null) return@setMethodCallHandler result.notImplemented()
            // A picture too, when given: a file in the cache's shared/ folder, lent to the app picked.
            val picture = call.argument<String>("file")?.let { path ->
                try {
                    androidx.core.content.FileProvider.getUriForFile(this, "$packageName.updates", java.io.File(path))
                } catch (e: IllegalArgumentException) {
                    null
                }
            }
            val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                type = if (picture != null) call.argument<String>("mime") ?: "image/png" else "text/plain"
                putExtra(android.content.Intent.EXTRA_TEXT, text)
                call.argument<String>("subject")?.let { putExtra(android.content.Intent.EXTRA_SUBJECT, it) }
                if (picture != null) {
                    putExtra(android.content.Intent.EXTRA_STREAM, picture)
                    clipData = android.content.ClipData.newRawUri(null, picture)
                    addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            try {
                startActivity(android.content.Intent.createChooser(send, null))
                result.success(true)
            } catch (e: android.content.ActivityNotFoundException) {
                result.success(false)
            }
        }
        incomingLinks = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "riflay/incoming_link").apply {
            setMethodCallHandler { call, result ->
                if (call.method != "take") return@setMethodCallHandler result.notImplemented()
                result.success(incomingLink)
                incomingLink = null
            }
        }
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
        // Signal path's Bluetooth stage: the codec the headphones get, and Nearby devices to read it (Android 12+).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "riflay/bluetooth").setMethodCallHandler { call, result ->
            when (call.method) {
                "codec" -> BluetoothCodec(this).read(result)
                "allow" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                        checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
                    ) return@setMethodCallHandler result.success(true)
                    pending?.success(false)
                    pending = result
                    requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQUEST)
                }
                else -> result.notImplemented()
            }
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

    // singleTask: a link opened while Riflay runs comes here. Dart is told, then takes it.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        linkOf(intent)?.let {
            incomingLink = it
            incomingLinks?.invokeMethod("available", null)
        }
    }

    // The link or the shared text; Dart finds the YouTube link in it. Reopening Riflay from Recents
    // replays the intent it was started with, which was handled then.
    private fun linkOf(intent: Intent?): String? {
        if (intent == null || intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.dataString
            Intent.ACTION_SEND -> listOfNotNull(
                intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
                intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString(),
            ).joinToString("\n").ifBlank { null }
            else -> null
        }
    }

    // The activity is recreated when see-through turns on or off: a search's lock goes with the old one.
    override fun onDestroy() {
        multicastLock?.takeIf { it.isHeld }?.release()
        usbDac?.dispose()
        appUpdater?.dispose()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST) return
        pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pending = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        appUpdater?.onActivityResult(requestCode)
    }

    private companion object {
        const val REQUEST = 7301
    }
}
