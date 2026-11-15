package com.dorkforce.powwot

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationManagerCompat

/** Shared constants and helpers. Nothing secret is stored here. */
object Powwot {
    const val NATIVE_PREFS = "powwot_native"
    const val PREF_MONITORING = "monitoring_enabled"
    const val PREF_KEEP_CPU_AWAKE = "keep_cpu_awake"

    const val CH_MONITOR = "powwot_monitor"
    const val CH_INFO = "powwot_info"
    const val CH_ALARM = "powwot_alarm"
    const val CH_ALARM_DND = "powwot_alarm_dnd"

    const val NOTIF_MONITOR = 1
    const val NOTIF_ALARM = 2
    const val NOTIF_INFO = 3

    const val ACTION_ALARM_STOPPED = "com.dorkforce.powwot.ALARM_STOPPED"

    fun prefs(ctx: Context) = ctx.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)

    fun ensureChannels(ctx: Context): String {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CH_MONITOR) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CH_MONITOR, "Monitoring", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Persistent notification while powwot watches the mailbox"
                    setShowBadge(false)
                })
        }
        if (nm.getNotificationChannel(CH_INFO) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CH_INFO, "Power restored / info", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Power restored and other one-off notices"
                })
        }
        // Pick a channel id depending on DND access so that a channel created after the
        // user grants DND access gets bypass-DND applied.
        val dnd = nm.isNotificationPolicyAccessGranted
        val id = if (dnd) CH_ALARM_DND else CH_ALARM
        if (nm.getNotificationChannel(id) == null) {
            nm.createNotificationChannel(
                NotificationChannel(id, "Power-out alarm", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Full-screen alarm when a MySpool POWER OFF email arrives"
                    setBypassDnd(true)
                    setSound(null, null) // the app plays the alarm itself on the alarm stream
                    enableVibration(false)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                })
        }
        return id
    }

    fun permissionStatus(ctx: Context): Map<String, Boolean> {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        val pm = ctx.getSystemService(PowerManager::class.java)
        return mapOf(
            "notifications" to NotificationManagerCompat.from(ctx).areNotificationsEnabled(),
            "dndAccess" to nm.isNotificationPolicyAccessGranted,
            "batteryExempt" to pm.isIgnoringBatteryOptimizations(ctx.packageName),
            "fullScreenIntent" to (if (Build.VERSION.SDK_INT >= 34) nm.canUseFullScreenIntent() else true),
        )
    }
}
