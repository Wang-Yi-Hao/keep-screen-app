package com.keepscreen.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 充电事件接收器（在 Manifest 中静态注册，即使 App 已关闭也能响应插拔电）。
 * 仅当用户开启“充电时常亮”时才动作：插电 → 启动服务并加 charge 原因；拔电 → 移除。
 */
class PowerEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences("keep_prefs", Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("chargeMode", false)
        if (!enabled) return

        val serviceIntent = Intent(context, KeepScreenService::class.java)
        when (intent.action) {
            Intent.ACTION_POWER_CONNECTED -> serviceIntent.action = "CMD_CHARGE_ON"
            Intent.ACTION_POWER_DISCONNECTED -> serviceIntent.action = "CMD_CHARGE_OFF"
            else -> return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
