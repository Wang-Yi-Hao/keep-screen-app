package com.keepscreen.app

import io.flutter.plugin.common.EventChannel

/**
 * 事件桥：原生（服务）向 Flutter 推送实时状态（是否常亮、充电中、计时剩余等）。
 * MainActivity 在 Flutter 监听 EventChannel 时把 sink 存进来；服务通过它发消息。
 * 若 Flutter 未监听（App 在后台），sink 为 null，推送自动忽略。
 */
object KeepEvents {
    var sink: EventChannel.EventSink? = null
}
