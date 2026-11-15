package com.dorkforce.powwot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts monitoring after reboot / app update if it was on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                if (MonitorService.isMonitoringEnabled(context)) {
                    MonitorService.send(context, MonitorService.ACTION_START)
                }
            }
        }
    }
}
