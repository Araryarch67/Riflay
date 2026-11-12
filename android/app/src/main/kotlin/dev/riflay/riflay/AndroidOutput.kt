package dev.riflay.riflay

import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Detail stats' Output on Android: what the system mixer runs at (its rate and buffer), what the phone offers
/// (low-latency and pro audio, spatial audio and whether it is on), the media volume in the phone's own steps,
/// and the format the device playing now takes.
class AndroidOutput(private val context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "riflay/android_output").setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> result.success(
                    try {
                        read()
                    } catch (e: Throwable) {
                        null
                    }
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun read(): Map<String, Any?> {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val features = context.packageManager
        val media = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        // Where media goes now (Android 13+), else the likeliest of what is plugged in.
        val device: AudioDeviceInfo? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            audio.getAudioDevicesForAttributes(media).firstOrNull()?.let { routed ->
                audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.id == routed.id }
            }
        } else {
            null
        } ?: audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).maxByOrNull { rank(it.type) }
        // The mixer format Riflay set for a USB DAC (bit-perfect), else the best PCM the device lists.
        val mixerBits: Int? = if (Build.VERSION.SDK_INT >= 34 && device != null) {
            audio.getPreferredMixerAttributes(media, device)?.format?.encoding?.let(::bitsOf)
        } else {
            null
        }
        val deviceBits = mixerBits ?: device?.encodings?.toList()?.mapNotNull(::bitsOf)?.maxOrNull()
        val spatial: String = if (Build.VERSION.SDK_INT >= 32) {
            val s = audio.spatializer
            when {
                s.immersiveAudioLevel == android.media.Spatializer.SPATIALIZER_IMMERSIVE_LEVEL_NONE -> "unsupported"
                s.isEnabled && s.isAvailable -> "on"
                else -> "off"
            }
        } else {
            "unsupported"
        }
        return mapOf(
            "mixerRate" to audio.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull(),
            "framesPerBuffer" to audio.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)?.toIntOrNull(),
            "lowLatency" to features.hasSystemFeature(PackageManager.FEATURE_AUDIO_LOW_LATENCY),
            "pro" to features.hasSystemFeature(PackageManager.FEATURE_AUDIO_PRO),
            "spatial" to spatial,
            "volume" to audio.getStreamVolume(AudioManager.STREAM_MUSIC),
            "maxVolume" to audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
            "deviceBits" to deviceBits,
        )
    }

    /// Headphones and DACs over the phone's own speaker, as Android routes media.
    private fun rank(type: Int) = when (type) {
        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> 5
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> 4
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> 3
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> 1
        else -> 0
    }

    private fun bitsOf(encoding: Int): Int? = when (encoding) {
        AudioFormat.ENCODING_PCM_16BIT -> 16
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> 24
        AudioFormat.ENCODING_PCM_32BIT, AudioFormat.ENCODING_PCM_FLOAT -> 32 // float named as its width
        AudioFormat.ENCODING_PCM_8BIT -> 8
        else -> null
    }
}
