package com.dorkforce.powwot

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/** Looping alarm on the ALARM stream with a linear volume ramp. */
class AlarmPlayer(private val ctx: Context) {
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var startedAt = 0L
    private var rampSeconds = RampMath.DEFAULT_RAMP_SECONDS
    private var savedStreamVolume: Int? = null
    private var savedInterruptionFilter: Int? = null
    private var vibrator: Vibrator? = null

    val isPlaying: Boolean get() = player != null

    private val rampTick = object : Runnable {
        override fun run() {
            val p = player ?: return
            val v = RampMath.volumeAt(SystemClock.elapsedRealtime() - startedAt, rampSeconds)
            try { p.setVolume(v, v) } catch (_: Exception) {}
            if (v < 1f) handler.postDelayed(this, 250)
        }
    }

    fun start(toneUri: String?, rampSeconds: Int, maxStream: Boolean, vibrate: Boolean) {
        if (player != null) return // already ringing; keep the current ramp
        this.rampSeconds = rampSeconds
        val am = ctx.getSystemService(AudioManager::class.java)
        val nm = ctx.getSystemService(NotificationManager::class.java)

        // If DND is in "total silence" and we have policy access, allow alarms while ringing.
        if (nm.isNotificationPolicyAccessGranted &&
            nm.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_NONE) {
            savedInterruptionFilter = nm.currentInterruptionFilter
            try { nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS) } catch (e: Exception) {
                Log.w(TAG, "could not relax DND", e)
            }
        }
        if (maxStream) {
            savedStreamVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            try {
                am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
            } catch (e: Exception) { Log.w(TAG, "could not raise alarm stream", e) }
        }

        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val p = buildPlayer(toneUri, attrs) ?: buildPlayer(null, attrs)
        if (p == null) { Log.e(TAG, "no playable alarm tone"); return }
        p.isLooping = true
        p.setVolume(0f, 0f)
        p.start()
        player = p
        startedAt = SystemClock.elapsedRealtime()
        handler.post(rampTick)
        if (vibrate) startVibration()
    }

    private fun buildPlayer(toneUri: String?, attrs: AudioAttributes): MediaPlayer? = try {
        MediaPlayer().apply {
            setAudioAttributes(attrs)
            if (toneUri.isNullOrBlank()) {
                val afd = ctx.resources.openRawResourceFd(R.raw.powwot_alarm)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
            } else {
                setDataSource(ctx, Uri.parse(toneUri))
            }
            prepare()
        }
    } catch (e: Exception) {
        Log.w(TAG, "tone load failed (custom=${!toneUri.isNullOrBlank()})", e); null
    }

    private fun startVibration() {
        val v = if (Build.VERSION.SDK_INT >= 31)
            ctx.getSystemService(VibratorManager::class.java).defaultVibrator
        else @Suppress("DEPRECATION") ctx.getSystemService(Vibrator::class.java)
        vibrator = v
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 800, 600), 0)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
            }
        } catch (e: Exception) { Log.w(TAG, "vibrate failed", e) }
    }

    fun stop() {
        handler.removeCallbacks(rampTick)
        player?.let { try { it.stop() } catch (_: Exception) {}; it.release() }
        player = null
        vibrator?.cancel(); vibrator = null
        val am = ctx.getSystemService(AudioManager::class.java)
        savedStreamVolume?.let { try { am.setStreamVolume(AudioManager.STREAM_ALARM, it, 0) } catch (_: Exception) {} }
        savedStreamVolume = null
        savedInterruptionFilter?.let {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            try { if (nm.isNotificationPolicyAccessGranted) nm.setInterruptionFilter(it) } catch (_: Exception) {}
        }
        savedInterruptionFilter = null
    }

    companion object { private const val TAG = "powwot.alarm" }
}
