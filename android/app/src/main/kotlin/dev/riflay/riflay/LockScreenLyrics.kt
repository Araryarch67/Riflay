package dev.riflay.riflay

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// Lyrics over the lock screen (riflay/lock_screen, lib/services/lock_screen_lyrics.dart): when the screen goes off
// while a song plays, the app comes up over the lock screen and Dart shows its lyrics page there; unlocking puts it
// back. Bringing the app up from the background takes "Display over other apps" (Android 10+ blocks it otherwise).
class LockScreenLyrics(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "riflay/lock_screen")
    private var enabled = false
    private var shown = false
    private val keyguard = activity.getSystemService(KeyguardManager::class.java)

    // Unlocking, told by the system itself: some phones (Xiaomi) never send USER_PRESENT to an app over the lock
    // screen, which left the page up after unlocking.
    private val lockState = if (Build.VERSION.SDK_INT >= 33) {
        KeyguardManager.KeyguardLockedStateListener { locked -> if (!locked) hide() }
    } else null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> if (enabled) show()
                Intent.ACTION_USER_PRESENT -> hide()
            }
        }
    }

    init {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        // System broadcasts only: nothing else can send these.
        if (Build.VERSION.SDK_INT >= 33) activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else activity.registerReceiver(receiver, filter)
        if (Build.VERSION.SDK_INT >= 33) keyguard?.addKeyguardLockedStateListener(activity.mainExecutor, lockState!!)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dart: the setting is on and a song is playing. Pausing on the page leaves it up; it decides only
                // whether the next screen-off shows it.
                "setEnabled" -> {
                    enabled = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                "canOverlay" -> result.success(Settings.canDrawOverlays(activity))
                "askOverlay" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${activity.packageName}"))
                    )
                    result.success(null)
                }
                // The lock screen's own unlock (PIN, fingerprint…); unlocking then hides the page.
                "unlock" -> {
                    if (Build.VERSION.SDK_INT >= 26) keyguard?.requestDismissKeyguard(activity, null)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// The app in front again (MainActivity.onResume): unlocked meanwhile, the page goes.
    fun onResume() {
        if (shown && keyguard?.isKeyguardLocked == false) hide()
    }

    private fun show() {
        shown = true
        setOverLock(true)
        channel.invokeMethod("locked", null)
        // Up from the background, so the page is what the screen shows when it comes on.
        try {
            activity.startActivity(
                Intent(activity, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            )
        } catch (_: Exception) {
            // Not allowed from the background: shown the next time the app is up.
        }
    }

    private fun hide() {
        if (!shown) return
        shown = false
        setOverLock(false)
        channel.invokeMethod("unlocked", null)
    }

    private fun setOverLock(on: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) {
            activity.setShowWhenLocked(on)
        } else {
            @Suppress("DEPRECATION")
            if (on) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
            else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
    }

    fun dispose() {
        hide()
        if (Build.VERSION.SDK_INT >= 33) keyguard?.removeKeyguardLockedStateListener(lockState!!)
        try {
            activity.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
        }
        channel.setMethodCallHandler(null)
    }
}
