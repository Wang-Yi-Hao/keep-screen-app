package com.keepscreen.app

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.WindowManager

/**
 * 透明全屏悬浮窗：本身不可见、不接收触摸，
 * 仅通过 FLAG_KEEP_SCREEN_ON 让屏幕在 App 退到后台时依然保持常亮。
 */
class OverlayWindow(private val context: Context) {

    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val view = View(context).apply { setBackgroundColor(Color.TRANSPARENT) }
    private var added = false

    fun show() {
        if (added) return
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            // 关键：保持屏幕常亮 + 不抢焦点 + 不接收触摸 + 占满屏幕
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START
        wm.addView(view, params)
        added = true
    }

    fun hide() {
        if (added) {
            try {
                wm.removeView(view)
            } catch (_: Exception) {
                // 忽略移除异常
            }
            added = false
        }
    }
}
