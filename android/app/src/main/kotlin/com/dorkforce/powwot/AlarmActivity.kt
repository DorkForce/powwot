package com.dorkforce.powwot

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.DateFormat
import java.util.Date

/** Full-screen alarm shown over the lock screen with a big Dismiss button. */
class AlarmActivity : Activity() {
    private val stoppedReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) = finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            getSystemService(KeyguardManager::class.java)?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val reason = intent.getStringExtra(EXTRA_REASON) ?: "MySpool POWER OFF Alert"
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.rgb(150, 0, 0))
            setPadding(48, 48, 48, 48)
        }
        root.addView(TextView(this).apply {
            text = "POWER OUTAGE"
            textSize = 40f; setTextColor(Color.WHITE); gravity = Gravity.CENTER
        })
        root.addView(TextView(this).apply {
            text = "$reason\n${DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())}"
            textSize = 20f; setTextColor(Color.WHITE); gravity = Gravity.CENTER
            setPadding(0, 24, 0, 64)
        })
        root.addView(Button(this).apply {
            text = "DISMISS"
            textSize = 28f
            setPadding(48, 48, 48, 48)
            setOnClickListener {
                MonitorService.send(this@AlarmActivity, MonitorService.ACTION_DISMISS)
                finish()
            }
        })
        setContentView(root)

        val filter = IntentFilter(Powwot.ACTION_ALARM_STOPPED)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(stoppedReceiver, filter, RECEIVER_NOT_EXPORTED)
        else @Suppress("UnspecifiedRegisterReceiverFlag") registerReceiver(stoppedReceiver, filter)
        if (!MonitorService.isAlarmActive) finish()
    }

    override fun onDestroy() {
        try { unregisterReceiver(stoppedReceiver) } catch (_: Exception) {}
        super.onDestroy()
    }

    companion object { const val EXTRA_REASON = "reason" }
}
