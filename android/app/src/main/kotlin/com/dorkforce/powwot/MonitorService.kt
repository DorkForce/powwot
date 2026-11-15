package com.dorkforce.powwot

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service. Hosts a headless Flutter engine running `pollerMain` (lib/main.dart),
 * which polls IMAP and asks this service to start/stop the alarm.
 */
class MonitorService : Service() {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private lateinit var alarm: AlarmPlayer
    private var statusText = "Starting…"
    private val main = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        alarm = AlarmPlayer(this)
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Powwot.ensureChannels(this)
        goForeground()
        val action = intent?.action
            ?: if (isMonitoringEnabled(this)) ACTION_START else ACTION_STOP
        when (action) {
            ACTION_START -> {
                Powwot.prefs(this).edit().putBoolean(Powwot.PREF_MONITORING, true).apply()
                startEngine()
                channel?.invokeMethod("pollNow", null)
            }
            ACTION_STOP -> {
                Powwot.prefs(this).edit().putBoolean(Powwot.PREF_MONITORING, false).apply()
                stopEngine()
                if (!alarm.isPlaying) shutdown()
            }
            ACTION_POLL_NOW -> channel?.invokeMethod("pollNow", null)
            ACTION_RELOAD -> channel?.invokeMethod("reload", null)
            ACTION_TEST_ALARM -> startAlarm(
                "TEST alarm",
                intent?.getStringExtra(EXTRA_TONE),
                intent?.getIntExtra(EXTRA_RAMP, 100) ?: 100,
                intent?.getBooleanExtra(EXTRA_MAX_STREAM, true) ?: true,
            )
            ACTION_DISMISS -> stopAlarm("dismissed", null)
        }
        if (!isMonitoringEnabled(this) && !alarm.isPlaying && engine == null) shutdown()
        return START_STICKY
    }

    private fun goForeground() {
        val n = buildMonitorNotification()
        val type = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        ServiceCompat.startForeground(this, Powwot.NOTIF_MONITOR, n, type)
    }

    private fun buildMonitorNotification(): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val title = if (isMonitoringEnabled(this)) "powwot is watching for power outages" else "powwot"
        return NotificationCompat.Builder(this, Powwot.CH_MONITOR)
            .setSmallIcon(android.R.drawable.ic_lock_idle_low_battery)
            .setContentTitle(title)
            .setContentText(statusText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun refreshMonitorNotification() {
        getSystemService(NotificationManager::class.java)
            .notify(Powwot.NOTIF_MONITOR, buildMonitorNotification())
    }

    private fun startEngine() {
        if (engine != null) return
        applyWakeLock()
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val e = FlutterEngine(applicationContext) // auto-registers plugins
        val ch = MethodChannel(e.dartExecutor.binaryMessenger, "powwot/service")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "startAlarm" -> {
                    startAlarm(
                        call.argument<String>("reason") ?: "MySpool POWER OFF Alert",
                        call.argument<String>("toneUri"),
                        call.argument<Int>("rampSeconds") ?: 100,
                        call.argument<Boolean>("maxStream") ?: true,
                    )
                    result.success(null)
                }
                "stopAlarm" -> {
                    stopAlarm(call.argument<String>("reason") ?: "stopped", call.argument<String>("message"))
                    result.success(null)
                }
                "isAlarmActive" -> result.success(alarm.isPlaying)
                "setStatus" -> {
                    statusText = call.argument<String>("text") ?: ""
                    refreshMonitorNotification()
                    result.success(null)
                }
                "setKeepCpuAwake" -> {
                    Powwot.prefs(this).edit()
                        .putBoolean(Powwot.PREF_KEEP_CPU_AWAKE, call.argument<Boolean>("value") ?: true).apply()
                    applyWakeLock()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "pollerMain"))
        engine = e
        channel = ch
        statusText = "Monitoring started"
        refreshMonitorNotification()
    }

    private fun stopEngine() {
        channel?.setMethodCallHandler(null)
        channel = null
        engine?.destroy()
        engine = null
        releaseWakeLock()
    }

    private fun applyWakeLock() {
        val want = Powwot.prefs(this).getBoolean(Powwot.PREF_KEEP_CPU_AWAKE, true)
        if (want && wakeLock == null) {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "powwot:monitor").apply {
                    setReferenceCounted(false); acquire()
                }
        } else if (!want) releaseWakeLock()
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun startAlarm(reason: String, tone: String?, ramp: Int, maxStream: Boolean) {
        val chId = Powwot.ensureChannels(this)
        alarm.start(tone, ramp, maxStream, vibrate = true)
        val full = PendingIntent.getActivity(
            this, 1,
            Intent(this, AlarmActivity::class.java).putExtra(AlarmActivity.EXTRA_REASON, reason)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val dismiss = PendingIntent.getService(
            this, 2, Intent(this, MonitorService::class.java).setAction(ACTION_DISMISS),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(this, chId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("POWER OUTAGE")
            .setContentText(reason)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(full, true)
            .setContentIntent(full)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismiss)
            .build()
        getSystemService(NotificationManager::class.java).notify(Powwot.NOTIF_ALARM, n)
        // Also try to bring up the alarm screen directly (works when allowed to start activities).
        try { full.send() } catch (e: Exception) { Log.w(TAG, "full-screen send failed", e) }
    }

    private fun stopAlarm(reason: String, message: String?) {
        val wasPlaying = alarm.isPlaying
        alarm.stop()
        val nm = getSystemService(NotificationManager::class.java)
        nm.cancel(Powwot.NOTIF_ALARM)
        sendBroadcast(Intent(Powwot.ACTION_ALARM_STOPPED).setPackage(packageName))
        if (message != null) {
            val open = PendingIntent.getActivity(
                this, 3, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            nm.notify(Powwot.NOTIF_INFO, NotificationCompat.Builder(this, Powwot.CH_INFO)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(message)
                .setContentText("MySpool POWER ON Alert received")
                .setContentIntent(open)
                .setAutoCancel(true)
                .build())
        }
        if (reason == "dismissed" && wasPlaying) {
            channel?.invokeMethod("alarmStopped", mapOf("reason" to reason))
        }
        if (!isMonitoringEnabled(this) && engine == null) main.post { shutdown() }
    }

    private fun shutdown() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        alarm.stop()
        stopEngine()
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "powwot.service"
        const val ACTION_START = "com.dorkforce.powwot.START"
        const val ACTION_STOP = "com.dorkforce.powwot.STOP"
        const val ACTION_POLL_NOW = "com.dorkforce.powwot.POLL_NOW"
        const val ACTION_RELOAD = "com.dorkforce.powwot.RELOAD"
        const val ACTION_TEST_ALARM = "com.dorkforce.powwot.TEST_ALARM"
        const val ACTION_DISMISS = "com.dorkforce.powwot.DISMISS"
        const val EXTRA_TONE = "tone"
        const val EXTRA_RAMP = "ramp"
        const val EXTRA_MAX_STREAM = "maxStream"

        @Volatile var instance: MonitorService? = null
        val isRunning: Boolean get() = instance?.engine != null
        val isAlarmActive: Boolean get() = instance?.alarm?.isPlaying == true

        fun isMonitoringEnabled(ctx: Context) =
            Powwot.prefs(ctx).getBoolean(Powwot.PREF_MONITORING, false)

        fun send(ctx: Context, action: String, extras: Intent.() -> Unit = {}) {
            val i = Intent(ctx, MonitorService::class.java).setAction(action).apply(extras)
            if (action == ACTION_DISMISS || action == ACTION_POLL_NOW || action == ACTION_RELOAD) {
                if (instance == null) return
            }
            androidx.core.content.ContextCompat.startForegroundService(ctx, i)
        }
    }
}
