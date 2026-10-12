package com.keepscreen.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import androidx.core.app.NotificationCompat

/**
 * 常亮前台服务（V2）：
 * 1) 常驻通知，降低被系统回收概率；
 * 2) 透明悬浮窗（OverlayWindow）：App 退到后台也保持屏幕常亮；
 * 3) 以“原因集合”管理是否常亮：manual（手动）/ charge（充电）/ foreground（指定 App 前台）；
 *    任一原因存在即保持常亮，全部消失则自动停止自身；
 * 4) 定时关闭：手动常亮时按设定分钟数到点自动移除 manual 原因；
 * 5) 充电监听：插电且开启“充电时常亮”即加 charge 原因，拔电移除；
 * 6) 前台 App 监听：指定包名处于前台时加 foreground 原因，离开移除；
 * 7) 通过 KeepEvents 把实时状态推给 Flutter。
 */
class KeepScreenService : Service() {

    companion object {
        /** 运行中实例，供 MainActivity / 接收器直接调用 */
        var instance: KeepScreenService? = null
    }

    private var overlay: OverlayWindow? = null
    private val CHANNEL_ID = "keep_screen_channel"
    private val NOTIFY_ID = 1001

    /** 当前保持常亮的原因集合 */
    private val reasons = mutableSetOf<String>()

    private var chargeModeEnabled = false
    private var foregroundModeEnabled = false
    private var targetPackage: String? = null
    private var timerMinutes = 0
    private var timerExpiry = 0L
    private var currentCharging = false

    // —— 定时降低亮度（防烧屏）——
    private var dimEnabled = false
    private var dimMinutes = 5
    private val dimTargetRatio = 0.25f // 到点降到当前亮度的 25%
    private var originalBrightness = -1
    private var dimExpiry = 0L
    private var dimRunnable: Runnable? = null

    private val handler = Handler(Looper.getMainLooper())
    private var timerRunnable: Runnable? = null
    private var fgRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        currentCharging = isCharging()
        // 还原持久化设置（让服务重启后保持用户偏好）
        val prefs = getSharedPreferences("keep_prefs", Context.MODE_PRIVATE)
        chargeModeEnabled = prefs.getBoolean("chargeMode", false)
        foregroundModeEnabled = prefs.getBoolean("foregroundMode", false)
        targetPackage = prefs.getString("targetPackage", "") ?: ""
        timerMinutes = prefs.getInt("timerMinutes", 0)
        dimEnabled = prefs.getBoolean("dimEnabled", false)
        dimMinutes = prefs.getInt("dimMinutes", 5)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFY_ID, buildNotification())

        when (intent?.action) {
            "CMD_MANUAL_ON" -> {
                addReason("manual")
                startTimerIfNeeded()
            }
            "CMD_MANUAL_OFF" -> {
                removeReason("manual")
                cancelTimer()
            }
            "CMD_SET_TIMER" -> {
                timerMinutes = intent.getIntExtra("minutes", 0)
                savePrefs()
                startTimerIfNeeded()
            }
            "CMD_CHARGE_MODE" -> {
                chargeModeEnabled = intent.getBooleanExtra("enabled", false)
                savePrefs()
                // 已插电且开启 → 立即加原因；否则移除（若之前因充电而亮）
                if (chargeModeEnabled && currentCharging) addReason("charge") else removeReason("charge")
            }
            "CMD_CHARGE_ON" -> { // 由 PowerEventReceiver 在插电时发来
                addReason("charge")
            }
            "CMD_CHARGE_OFF" -> { // 由 PowerEventReceiver 在拔电时发来
                removeReason("charge")
            }
            "CMD_FG_MODE" -> {
                foregroundModeEnabled = intent.getBooleanExtra("enabled", false)
                savePrefs()
                if (foregroundModeEnabled) startFgPoller() else stopFgPoller()
                evaluateForeground()
            }
            "CMD_SET_PKG" -> {
                targetPackage = intent.getStringExtra("package")
                savePrefs()
                evaluateForeground()
            }
            "CMD_DIM_CONFIG" -> {
                dimEnabled = intent.getBooleanExtra("enabled", false)
                dimMinutes = intent.getIntExtra("minutes", 5)
                saveDimPrefs()
                onDimConfigChanged()
            }
        }
        pushState()
        return START_STICKY
    }

    override fun onDestroy() {
        stopFgPoller()
        cancelTimer()
        cancelDimTimer()
        restoreBrightness()
        overlay?.hide()
        overlay = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // —————————————————————— 核心：是否保持常亮 ——————————————————————

    private fun addReason(r: String) {
        if (reasons.add(r)) updateKeepState()
    }

    private fun removeReason(r: String) {
        if (reasons.remove(r)) updateKeepState()
    }

    /** 根据 reasons 决定显示/隐藏悬浮窗；无原因时停掉自身 */
    private fun updateKeepState() {
        if (reasons.isNotEmpty()) {
            if (overlay == null) {
                // 悬浮窗需要 SYSTEM_ALERT_WINDOW 权限（首次引导已要求授予）；
                // 若未授予则降级（前台由 Activity 窗口标记兜底）
                try {
                    overlay = OverlayWindow(this)
                    overlay?.show()
                } catch (e: Exception) {
                    e.printStackTrace()
                    overlay = null
                }
            }
        } else {
            overlay?.hide()
            overlay = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        // 刷新常驻通知标题（体现当前常亮原因）
        if (reasons.isNotEmpty()) refreshNotification()
        onActiveChanged(reasons.isNotEmpty())
        pushState()
    }

    // —————————————————————— 定时关闭 ——————————————————————

    private fun startTimerIfNeeded() {
        cancelTimer()
        if (timerMinutes > 0 && reasons.contains("manual")) {
            val delay = timerMinutes * 60_000L
            timerExpiry = System.currentTimeMillis() + delay
            timerRunnable = Runnable { onTimerExpired() }
            handler.postDelayed(timerRunnable!!, delay)
        }
    }

    private fun cancelTimer() {
        timerRunnable?.let { handler.removeCallbacks(it) }
        timerRunnable = null
        timerExpiry = 0
    }

    /** 定时到点：移除 manual 原因（若仍有其它原因则继续亮） */
    private fun onTimerExpired() {
        removeReason("manual")
        cancelTimer()
        pushState()
    }

    // —————————————————————— 定时降低亮度（防烧屏） ——————————————————————

    /** 常亮状态变化：进入常亮则按配置启动降亮度计时；退出常亮立即恢复亮度 */
    private fun onActiveChanged(active: Boolean) {
        if (active && dimEnabled) {
            ensureDimTimer()
        } else {
            cancelDimTimer()
            restoreBrightness()
        }
    }

    /** 降亮度配置变化：变更分钟数需重启计时；关闭则立即恢复亮度 */
    private fun onDimConfigChanged() {
        if (dimEnabled && reasons.isNotEmpty()) {
            cancelDimTimer()
            startDimTimer()
        } else {
            cancelDimTimer()
            restoreBrightness()
        }
    }

    private fun ensureDimTimer() {
        if (dimRunnable == null) startDimTimer()
    }

    private fun startDimTimer() {
        cancelDimTimer()
        if (dimEnabled && reasons.isNotEmpty() && dimMinutes > 0) {
            val delay = dimMinutes * 60_000L
            dimExpiry = System.currentTimeMillis() + delay
            dimRunnable = Runnable { applyDim() }
            handler.postDelayed(dimRunnable!!, delay)
        }
    }

    private fun cancelDimTimer() {
        dimRunnable?.let { handler.removeCallbacks(it) }
        dimRunnable = null
        dimExpiry = 0
    }

    /** 到点：把系统背光降到较低亮度（防烧屏）。降前记录原亮度以便恢复 */
    private fun applyDim() {
        if (!canWriteSettings()) return
        if (originalBrightness < 0) originalBrightness = getCurrentBrightness()
        val target = (originalBrightness * dimTargetRatio).toInt().coerceAtLeast(1)
        setBrightness(target)
        pushState()
    }

    /** 恢复：写回降前亮度，并复位计时 */
    private fun restoreBrightness() {
        cancelDimTimer()
        if (originalBrightness >= 0) {
            setBrightness(originalBrightness)
            originalBrightness = -1
        }
        pushState()
    }

    private fun setBrightness(value: Int) {
        if (!canWriteSettings()) return
        try {
            Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, value)
        } catch (_: Exception) {
        }
    }

    private fun getCurrentBrightness(): Int =
        try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 100)
        } catch (_: Exception) {
            100
        }

    private fun canWriteSettings(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.System.canWrite(this)
        } else {
            true
        }

    private fun saveDimPrefs() {
        getSharedPreferences("keep_prefs", Context.MODE_PRIVATE).edit().apply {
            putBoolean("dimEnabled", dimEnabled)
            putInt("dimMinutes", dimMinutes)
            apply()
        }
    }

    // —————————————————————— 充电监听（由 PowerEventReceiver 驱动） ——————————————————————

    private fun isCharging(): Boolean {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return bm.isCharging
    }

    // —————————————————————— 指定 App 前台监听 ——————————————————————

    private fun startFgPoller() {
        if (fgRunnable != null) return
        fgRunnable = object : Runnable {
            override fun run() {
                evaluateForeground()
                handler.postDelayed(this, 1500)
            }
        }
        handler.post(fgRunnable!!)
    }

    private fun stopFgPoller() {
        fgRunnable?.let { handler.removeCallbacks(it) }
        fgRunnable = null
    }

    /** 查当前顶层 App 是否为目标包名，据此增删 foreground 原因 */
    private fun evaluateForeground() {
        if (!foregroundModeEnabled || targetPackage.isNullOrEmpty()) {
            removeReason("foreground")
            return
        }
        val top = getTopPackage()
        if (top == null) return // 查询空窗期，保持现状，避免抖动
        if (top == targetPackage) addReason("foreground") else removeReason("foreground")
    }

    private fun getTopPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            now - 3000,
            now,
        ) ?: return null
        if (stats.isEmpty()) return null
        return stats.maxByOrNull { it.lastTimeUsed }?.packageName
    }

    // —————————————————————— 状态推送 ——————————————————————

    /** 构建当前状态快照（同时供 MainActivity.getState 复用） */
    fun snapshot(): Map<String, Any> = mapOf(
        "isOn" to reasons.isNotEmpty(),
        "manualOn" to reasons.contains("manual"),
        "chargeMode" to chargeModeEnabled,
        "charging" to currentCharging,
        "foregroundMode" to foregroundModeEnabled,
        "targetPackage" to (targetPackage ?: ""),
        "timerMinutes" to timerMinutes,
        "remainingSeconds" to remainingSeconds(),
        "dimEnabled" to dimEnabled,
        "dimMinutes" to dimMinutes,
        "dimmed" to (originalBrightness >= 0),
    )

    internal fun pushState() {
        KeepEvents.sink?.success(snapshot())
    }

    private fun remainingSeconds(): Int {
        if (timerExpiry == 0L) return -1
        val left = (timerExpiry - System.currentTimeMillis()) / 1000
        return if (left < 0) 0 else left.toInt()
    }

    private fun savePrefs() {
        getSharedPreferences("keep_prefs", Context.MODE_PRIVATE).edit().apply {
            putBoolean("chargeMode", chargeModeEnabled)
            putBoolean("foregroundMode", foregroundModeEnabled)
            putString("targetPackage", targetPackage ?: "")
            putInt("timerMinutes", timerMinutes)
            apply()
        }
    }

    // —————————————————————— 通知 ——————————————————————

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val chan = NotificationChannel(
                CHANNEL_ID,
                "常亮服务",
                NotificationManager.IMPORTANCE_LOW,
            )
            chan.description = "保持屏幕常亮的后台服务"
            chan.enableLights(false)
            chan.setShowBadge(false)
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(chan)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val why = buildString {
            if (reasons.contains("manual")) append("手动")
            if (reasons.contains("charge")) append("·充电")
            if (reasons.contains("foreground")) append("·前台App")
        }.ifEmpty { "常亮中" }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("常亮小助手运行中（$why）")
            .setContentText("点击打开 · 关闭请在 App 内点开关")
            .setSmallIcon(R.drawable.ic_keep)
            .setContentIntent(pi)
            .setOngoing(true)
            .setColor(Color.CYAN)
            .build()
    }

    private fun refreshNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFY_ID, buildNotification())
    }
}
