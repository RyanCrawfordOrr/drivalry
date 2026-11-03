package app.drivalry.convoy

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `app.drivalry/convoy_audio`: the Android half of the convoy audio session.
 *
 * Methods: `start` (communication mode, audio focus, foreground service),
 * `stop`, `duck {on}` (transient may-duck focus while push-to-talk is held),
 * `setSpeaker {on}`. Calls `stopped` on the Dart side when the user taps Stop
 * on the service notification. WebRTC itself lives in the Flutter engine; this
 * only shapes the system audio state around it.
 */
class ConvoyAudioPlugin private constructor(
    private val activity: Activity,
    engine: FlutterEngine,
) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var mainFocus: AudioFocusRequest? = null
    private var duckFocus: AudioFocusRequest? = null
    private var running = false

    private val stoppedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == ConvoyAudioService.ACTION_STOPPED) {
                running = false
                releaseAudio()
                channel.invokeMethod("stopped", null)
            }
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> { start(); result.success(null) }
                    "stop" -> { stop(); result.success(null) }
                    "duck" -> { duck(call.argument<Boolean>("on") == true); result.success(null) }
                    "setSpeaker" -> { setSpeaker(call.argument<Boolean>("on") == true); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("audio", e.message, null)
            }
        }
        ContextCompat.registerReceiver(
            activity,
            stoppedReceiver,
            IntentFilter(ConvoyAudioService.ACTION_STOPPED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    private fun start() {
        if (running) return
        running = true
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attrs)
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener { }
            .build()
        audio.requestAudioFocus(request)
        mainFocus = request
        ConvoyAudioService.start(activity)
    }

    private fun stop() {
        if (!running) return
        running = false
        releaseAudio()
        ConvoyAudioService.stop(activity)
    }

    private fun releaseAudio() {
        duckFocus?.let { audio.abandonAudioFocusRequest(it) }
        duckFocus = null
        mainFocus?.let { audio.abandonAudioFocusRequest(it) }
        mainFocus = null
        audio.mode = AudioManager.MODE_NORMAL
    }

    /** Push-to-talk held: ask other apps (music) to duck; released: give it back. */
    private fun duck(on: Boolean) {
        if (on) {
            if (duckFocus != null) return
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener { }
                .build()
            audio.requestAudioFocus(request)
            duckFocus = request
        } else {
            duckFocus?.let { audio.abandonAudioFocusRequest(it) }
            duckFocus = null
        }
    }

    private fun setSpeaker(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (on) {
                val speaker = audio.availableCommunicationDevices
                    .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                if (speaker != null) audio.setCommunicationDevice(speaker)
            } else {
                audio.clearCommunicationDevice()
            }
        } else {
            @Suppress("DEPRECATION")
            audio.isSpeakerphoneOn = on
        }
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        try {
            activity.unregisterReceiver(stoppedReceiver)
        } catch (_: IllegalArgumentException) {
        }
    }

    companion object {
        const val CHANNEL = "app.drivalry/convoy_audio"

        fun attach(activity: Activity, engine: FlutterEngine): ConvoyAudioPlugin =
            ConvoyAudioPlugin(activity, engine)
    }
}
