package dev.riflay.riflay

import android.Manifest
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/// What the Bluetooth headphones playing now are sent: the codec, its rate and bit depth (and LDAC's bitrate), as
/// Android's Bluetooth settings show them in Developer options. Android lists the codec in `BluetoothA2dp`'s
/// `getCodecStatus`, which apps reach by reflection: a phone that hides it gives the headphones' name alone.
class BluetoothCodec(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())

    fun read(result: MethodChannel.Result) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val output = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }
            ?: return result.success(null)
        val info = mutableMapOf<String, Any?>("name" to output.productName?.toString())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            info["permission"] = false
            return result.success(info)
        }
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            ?: return result.success(info)
        var answered = false
        fun answer() {
            if (answered) return
            answered = true
            result.success(info)
        }
        val asked = try {
            adapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    try {
                        val a2dp = proxy as BluetoothA2dp
                        a2dp.connectedDevices.firstOrNull()?.let { info.putAll(codecOf(a2dp, it)) }
                    } catch (e: Throwable) {
                        info["error"] = e.javaClass.simpleName
                    } finally {
                        adapter.closeProfileProxy(BluetoothProfile.A2DP, proxy)
                        main.post { answer() }
                    }
                }

                override fun onServiceDisconnected(profile: Int) {
                    main.post { answer() }
                }
            }, BluetoothProfile.A2DP)
        } catch (e: SecurityException) {
            false
        }
        if (!asked) return answer()
        // A stack that never connects the proxy still answers, with the name.
        main.postDelayed({ answer() }, 1500)
    }

    private fun codecOf(a2dp: BluetoothA2dp, device: BluetoothDevice): Map<String, Any?> {
        val status = a2dp.javaClass.getMethod("getCodecStatus", BluetoothDevice::class.java).invoke(a2dp, device)
            ?: return emptyMap()
        val config = status.javaClass.getMethod("getCodecConfig").invoke(status) ?: return emptyMap()
        fun int(name: String) = (config.javaClass.getMethod(name).invoke(config) as Number).toInt()
        fun long(name: String) = (config.javaClass.getMethod(name).invoke(config) as Number).toLong()
        return mapOf(
            "codec" to int("getCodecType"),
            "rate" to int("getSampleRate"),
            "bits" to int("getBitsPerSample"),
            "specific1" to long("getCodecSpecific1"),
        )
    }
}
