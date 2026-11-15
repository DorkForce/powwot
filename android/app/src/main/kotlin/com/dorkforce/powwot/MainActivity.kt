package com.dorkforce.powwot

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingTonePick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Powwot.ensureChannels(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "powwot/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitoring" -> { MonitorService.send(this, MonitorService.ACTION_START); result.success(null) }
                "stopMonitoring" -> { MonitorService.send(this, MonitorService.ACTION_STOP); result.success(null) }
                "pollNow" -> { MonitorService.send(this, MonitorService.ACTION_POLL_NOW); result.success(null) }
                "reloadConfig" -> { MonitorService.send(this, MonitorService.ACTION_RELOAD); result.success(null) }
                "isMonitoring" -> result.success(MonitorService.isMonitoringEnabled(this))
                "isAlarmActive" -> result.success(MonitorService.isAlarmActive)
                "dismissAlarm" -> { MonitorService.send(this, MonitorService.ACTION_DISMISS); result.success(null) }
                "testAlarm" -> {
                    MonitorService.send(this, MonitorService.ACTION_TEST_ALARM) {
                        putExtra(MonitorService.EXTRA_TONE, call.argument<String>("toneUri"))
                        putExtra(MonitorService.EXTRA_RAMP, call.argument<Int>("rampSeconds") ?: 100)
                        putExtra(MonitorService.EXTRA_MAX_STREAM, call.argument<Boolean>("maxStream") ?: true)
                    }
                    result.success(null)
                }
                "setKeepCpuAwake" -> {
                    Powwot.prefs(this).edit()
                        .putBoolean(Powwot.PREF_KEEP_CPU_AWAKE, call.argument<Boolean>("value") ?: true).apply()
                    result.success(null)
                }
                "permissionStatus" -> result.success(Powwot.permissionStatus(this))
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42)
                    } else {
                        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                    }
                    result.success(null)
                }
                "openDndAccess" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)); result.success(null)
                }
                "requestBatteryExemption" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName")))
                    } catch (_: Exception) {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    }
                    result.success(null)
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        try {
                            startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                Uri.parse("package:$packageName")))
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")))
                        }
                    }
                    result.success(null)
                }
                "pickAlarmTone" -> {
                    pendingTonePick?.success(null)
                    pendingTonePick = result
                    val current = call.argument<String>("current")
                    val i = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
                        .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
                        .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, false)
                        .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                        .putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "powwot alarm tone")
                    if (!current.isNullOrBlank()) {
                        i.putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(current))
                    }
                    @Suppress("DEPRECATION")
                    startActivityForResult(i, REQ_TONE)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_TONE) return
        val r = pendingTonePick ?: return
        pendingTonePick = null
        if (resultCode != RESULT_OK || data == null) { r.success(null); return }
        val uri: Uri? = if (Build.VERSION.SDK_INT >= 33)
            data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
        else @Suppress("DEPRECATION") data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (uri == null) { r.success(null); return }
        val title = try { RingtoneManager.getRingtone(this, uri)?.getTitle(this) } catch (_: Exception) { null }
        r.success(mapOf("uri" to uri.toString(), "title" to (title ?: "System tone")))
    }

    companion object { private const val REQ_TONE = 7001 }
}
