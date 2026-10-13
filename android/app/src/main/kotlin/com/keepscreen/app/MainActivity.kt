package com.keepscreen.app

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.BatteryManager
import android.os.PowerManager
import android.provider.Settings
import android.util.Base64
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/**
 * 主界面：注册 MethodChannel（命令）与 EventChannel（状态推送）。
 *
 * 命令统一转发给 KeepScreenService 处理，服务是“保持常亮”的唯一权威，
 * 因为退到后台时必须靠前台服务 + 透明悬浮窗才能让屏幕常亮。
 *
 * V2 新增命令：定时关闭 / 充电时常亮 / 指定 App 前台时常亮 / 取已装应用列表 /
 * 检查并引导“使用情况访问”权限 / 拉取当前状态。
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.keepscreen.app/keep"
    private val EVENTS = "com.keepscreen.app/events"

    // 定时降亮度所需的“修改系统设置”权限未授予时，记录意图待授权返回后补发
    private var pendingDimEnabled = false
    private var pendingDimMinutes = 5

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // —— V1 既有 ——
                    "start" -> {
                        // 前台兜底：直接给 Activity 窗口加常亮标记（无需悬浮窗权限）
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        launchKeepService(cmd("CMD_MANUAL_ON"))
                        result.success(true)
                    }
                    "stop" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        launchKeepService(cmd("CMD_MANUAL_OFF"))
                        result.success(true)
                    }
                    "checkOverlayPermission" -> result.success(canDrawOverlay())
                    "openOverlaySettings" -> {
                        if (!canDrawOverlay()) {
                            val uri = Uri.parse("package:$packageName")
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, uri))
                        }
                        result.success(true)
                    }

                    // —— V2 新增 ——
                    "setTimer" -> {
                        val min = call.argument<Int>("minutes") ?: 0
                        launchKeepService(cmd("CMD_SET_TIMER").apply { putExtra("minutes", min) })
                        result.success(true)
                    }
                    "setChargeMode" -> {
                        val on = call.argument<Boolean>("enabled") ?: false
                        launchKeepService(cmd("CMD_CHARGE_MODE").apply { putExtra("enabled", on) })
                        result.success(true)
                    }
                    "setForegroundMode" -> {
                        val on = call.argument<Boolean>("enabled") ?: false
                        launchKeepService(cmd("CMD_FG_MODE").apply { putExtra("enabled", on) })
                        result.success(true)
                    }
                    "setTargetPackage" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        launchKeepService(cmd("CMD_SET_PKG").apply { putExtra("package", pkg) })
                        result.success(true)
                    }
                    "checkUsagePermission" -> result.success(canReadUsage())
                    "openUsageSettings" -> {
                        if (!canReadUsage()) {
                            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        }
                        result.success(true)
                    }
                    "getInstalledApps" -> result.success(getInstalledApps())
                    "getState" -> result.success(getState())

                    // —— 首次引导 / 必要权限 ——
                    "checkBatteryOptimization" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestBatteryOptimization" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(true)
                    }
                    "setOverlayMode" -> {
                        // 悬浮窗已改为首次必选权限，不再提供运行时开关
                        result.success(true)
                    }
                    "setDimMode" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val minutes = call.argument<Int>("minutes") ?: 5
                        result.success(applyDimMode(enabled, minutes))
                    }
                    "markGuideDone" -> {
                        getSharedPreferences("keep_prefs", Context.MODE_PRIVATE)
                            .edit()
                            .putBoolean("guideDone", true)
                            .apply()
                        result.success(true)
                    }

                    // —— 检查更新 ——
                    /** 返回本机当前版本名与版本号（versionCode 为整数，用于和远程比较） */
                    "getAppVersion" -> {
                        @Suppress("DEPRECATION")
                        val pInfo = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pInfo.longVersionCode.toInt()
                        } else {
                            @Suppress("DEPRECATION")
                            pInfo.versionCode
                        }
                        result.success(
                            mapOf(
                                "version" to (pInfo.versionName ?: "1.0.0"),
                                "versionCode" to code,
                            ),
                        )
                    }
                    /** 调起系统浏览器打开指定 url（发现新版本后跳转发布页） */
                    "openBrowser" -> {
                        val url = call.argument<String>("url") ?: ""
                        if (url.isNotEmpty()) {
                            try {
                                val intent =
                                    Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            } catch (_: Exception) {
                            }
                        }
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

        // 状态推送：Flutter 监听时把 sink 登记到 KeepEvents，服务据此发消息
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    KeepEvents.sink = sink
                    // 立即把当前状态补发一次
                    KeepScreenService.instance?.pushState()
                }

                override fun onCancel(args: Any?) {
                    KeepEvents.sink = null
                }
            })
    }

    private fun cmd(action: String): Intent =
        Intent(this, KeepScreenService::class.java).setAction(action)

    private fun launchKeepService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /** 拉取当前状态：优先取运行中的服务快照，否则回退到本地持久化设置 */
    private fun getState(): Map<String, Any> {
        val prefs = getSharedPreferences("keep_prefs", Context.MODE_PRIVATE)
        val svc = KeepScreenService.instance
        return if (svc != null) {
            svc.snapshot()
        } else {
            mapOf(
                "isOn" to false,
                "manualOn" to false,
                "chargeMode" to prefs.getBoolean("chargeMode", false),
                "charging" to isCharging(),
                "foregroundMode" to prefs.getBoolean("foregroundMode", false),
                "targetPackage" to (prefs.getString("targetPackage", "") ?: ""),
                "timerMinutes" to prefs.getInt("timerMinutes", 0),
                "remainingSeconds" to -1,
                "dimEnabled" to prefs.getBoolean("dimEnabled", false),
                "dimMinutes" to prefs.getInt("dimMinutes", 5),
                "dimmed" to false,
                "batteryOpt" to isIgnoringBatteryOptimizations(),
                "guideDone" to prefs.getBoolean("guideDone", false),
            )
        }
    }

    private fun canDrawOverlay(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }

    /** 是否拥有“使用情况访问”权限（查前台 App 必需，Android 自带的特殊权限） */
    private fun canReadUsage(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun isCharging(): Boolean {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return bm.isCharging
    }

    /** 是否已在电池优化白名单（Android 6.0+ 才有该概念，低版本直接视为已加入） */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    /** 引导加入电池优化白名单；个别 ROM 无该页时回退到系统设置 */
    private fun requestIgnoreBatteryOptimizations() {
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS))
            } catch (_: Exception) {
            }
        }
    }

    /** 返回已安装且可启动的 App 列表（JSON：[{name, package, icon}]），供 Flutter 做选择器。
     *  icon 为 72px PNG 的 Base64 字符串（可能为空），用于在列表中展示应用图标。 */
    private fun getInstalledApps(): String {
        val pm = packageManager
        val arr = JSONArray()
        val size = 72
        for (app in pm.getInstalledApplications(PackageManager.GET_META_DATA)) {
            if (app.packageName == packageName) continue
            // 只保留有启动入口的应用，避免列出系统隐式组件造成选择困扰
            if (pm.getLaunchIntentForPackage(app.packageName) == null) continue
            val obj = JSONObject()
            obj.put("name", pm.getApplicationLabel(app).toString())
            obj.put("package", app.packageName)
            obj.put("icon", appIconBase64(pm, app, size))
            arr.put(obj)
        }
        return arr.toString()
    }

    /** 将应用图标绘制为固定尺寸的 PNG 并以 Base64 返回；异常时返回 null */
    private fun appIconBase64(pm: PackageManager, app: ApplicationInfo, size: Int): String? {
        return try {
            val drawable = pm.getApplicationIcon(app)
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val stream = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, stream)
            val bytes = stream.toByteArray()
            stream.close()
            Base64.encodeToString(bytes, Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }

    // —— 定时降低亮度：WRITE_SETTINGS 权限处理 ——

    /** 应用降亮度配置；缺少 WRITE_SETTINGS 权限时引导授权并标记待补发 */
    private fun applyDimMode(enabled: Boolean, minutes: Int): String {
        if (enabled && !canWriteSettings()) {
            pendingDimEnabled = true
            pendingDimMinutes = minutes
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:$packageName")),
                )
            } catch (_: Exception) {
            }
            return "need_permission"
        }
        pendingDimEnabled = false
        launchKeepService(
            cmd("CMD_DIM_CONFIG").apply {
                putExtra("enabled", enabled)
                putExtra("minutes", minutes)
            },
        )
        return "ok"
    }

    private fun canWriteSettings(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.System.canWrite(this)
        } else {
            true
        }

    override fun onResume() {
        super.onResume()
        if (pendingDimEnabled && canWriteSettings()) {
            pendingDimEnabled = false
            launchKeepService(
                cmd("CMD_DIM_CONFIG").apply {
                    putExtra("enabled", true)
                    putExtra("minutes", pendingDimMinutes)
                },
            )
            KeepScreenService.instance?.pushState()
        }
    }
}
