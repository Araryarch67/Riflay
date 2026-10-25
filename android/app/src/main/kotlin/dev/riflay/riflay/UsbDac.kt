package dev.riflay.riflay

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// Bit-perfect output to a USB DAC (Android 14+): while a media track has exactly the format of the mixer
// attributes set here, Android hands it to the DAC untouched. Dart picks the format per song.
class UsbDac(context: Context, messenger: BinaryMessenger) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val channel = MethodChannel(messenger, "riflay/usb_dac")
    private val supported = Build.VERSION.SDK_INT >= 34

    private val media = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = changed()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = changed()
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> result.success(state())
                "prefer" -> result.success(prefer(call.argument<Int>("device"), call.argument<Int>("rate"), call.argument<String>("encoding")))
                "clear" -> {
                    clear(call.argument<Int>("device"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        if (supported) audio.registerAudioDeviceCallback(callback, Handler(Looper.getMainLooper()))
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (supported) audio.unregisterAudioDeviceCallback(callback)
    }

    private fun changed() = channel.invokeMethod("changed", state())

    private fun usbOutputs() = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter {
        it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET
    }

    // Stereo bit-perfect formats only: that is what Riflay plays.
    private fun formats(device: AudioDeviceInfo): List<AudioMixerAttributes> {
        if (!supported) return emptyList()
        return audio.getSupportedMixerAttributes(device).filter {
            it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT &&
                it.format.channelMask == AudioFormat.CHANNEL_OUT_STEREO
        }
    }

    private fun encodingName(encoding: Int) = when (encoding) {
        AudioFormat.ENCODING_PCM_16BIT -> "pcm16"
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> "pcm24"
        AudioFormat.ENCODING_PCM_32BIT -> "pcm32"
        AudioFormat.ENCODING_PCM_FLOAT -> "float"
        else -> null
    }

    private fun state(): Map<String, Any> = mapOf(
        "supported" to supported,
        "devices" to if (!supported) emptyList() else usbOutputs().map { d ->
            mapOf(
                "id" to d.id,
                "name" to (d.productName?.toString() ?: "USB DAC"),
                "formats" to formats(d).mapNotNull { a ->
                    encodingName(a.format.encoding)?.let { mapOf("rate" to a.format.sampleRate, "encoding" to it) }
                },
            )
        },
    )

    private fun prefer(id: Int?, rate: Int?, encoding: String?): Boolean {
        if (!supported || id == null || rate == null) return false
        val device = usbOutputs().firstOrNull { it.id == id } ?: return false
        val wanted = formats(device).firstOrNull { it.format.sampleRate == rate && encodingName(it.format.encoding) == encoding }
            ?: return false
        return audio.setPreferredMixerAttributes(media, device, wanted)
    }

    private fun clear(id: Int?) {
        if (!supported || id == null) return
        val device = usbOutputs().firstOrNull { it.id == id } ?: return
        audio.clearPreferredMixerAttributes(media, device)
    }
}
