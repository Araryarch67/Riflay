package dev.riflay.riflay

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// Keeps music going with the screen off: a CPU lock and a Wi-Fi lock while playing,
// and the way to ask the system (one tap) not to put Riflay to sleep.
// The locks belong to the process, not the activity: the playback service outlives it.
class PowerControl(private val context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "riflay/power").setMethodCallHandler { call, result ->
            when (call.method) {
                "hold" -> {
                    hold(call.argument<Boolean>("cpu") == true, call.argument<Boolean>("wifi") == true)
                    result.success(null)
                }
                "isExempt" -> {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
                }
                "request" -> result.success(request())
                "openBatterySettings" -> result.success(openBatterySettings())
                "brand" -> result.success(Build.MANUFACTURER.lowercase())
                else -> result.notImplemented()
            }
        }
    }

    private fun hold(cpu: Boolean, wifi: Boolean) {
        if (cpu) {
            if (cpuLock == null) {
                val pm = context.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                cpuLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "riflay:playback").apply { setReferenceCounted(false) }
            }
            cpuLock?.takeIf { !it.isHeld }?.acquire()
        } else {
            cpuLock?.takeIf { it.isHeld }?.release()
        }
        if (wifi) {
            if (wifiLock == null) {
                val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
                wifiLock = wm.createWifiLock(mode, "riflay:stream").apply { setReferenceCounted(false) }
            }
            wifiLock?.takeIf { !it.isHeld }?.acquire()
        } else {
            wifiLock?.takeIf { it.isHeld }?.release()
        }
    }

    private fun launch(intent: Intent): Boolean = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    // The system's own "Allow Riflay to always run in the background?" dialog.
    private fun request(): Boolean {
        val pkg = Uri.parse("package:${context.packageName}")
        return launch(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg)) ||
            launch(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    // The maker's own battery / background page where one is known; else Riflay's app details.
    private fun openBatterySettings(): Boolean {
        for ((pkg, cls) in pagesFor(Build.MANUFACTURER.lowercase())) {
            val intent = Intent().setComponent(ComponentName(pkg, cls))
                .putExtra("package_name", context.packageName).putExtra("package_label", "Riflay")
            if (launch(intent)) return true
        }
        return launch(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
    }

    private fun pagesFor(brand: String): List<Pair<String, String>> = when (brand) {
        "xiaomi", "redmi", "poco" -> listOf(
            "com.miui.powerkeeper" to "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
        "oppo", "realme", "oneplus" -> listOf(
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
        )
        "vivo", "iqoo" -> listOf(
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
        )
        "samsung" -> listOf(
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
            "com.samsung.android.sm_cn" to "com.samsung.android.sm.ui.battery.BatteryActivity",
        )
        "huawei", "honor" -> listOf(
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        )
        else -> emptyList()
    }

    private companion object {
        var cpuLock: PowerManager.WakeLock? = null
        var wifiLock: WifiManager.WifiLock? = null
    }
}
