package com.azazo1.piliplus

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Flutter 引擎 (MainActivity) 与悬浮窗之间的通道.
 *
 * 悬浮窗只负责提供 Surface; 播放器始终只有一个, 活在主引擎里.
 * 悬浮窗拿到 Surface 的 wid 之后通过这里回传给 Dart, 由 Dart 把 mpv 输出切过去.
 * 所有悬浮窗事件都带 session, Dart 据此丢弃过期事件.
 */
object InAppChannel {
    private const val TAG = "MiniOverlay"

    /** Dart 侧控制通道 (同一个名字在 Dart 与 MainActivity 各注册一次). */
    const val CHANNEL = "com.azazo1.piliplus/mini_player"

    private var channel: MethodChannel? = null

    /** 发给 Dart. 引擎不在时返回 false, 调用方需要本地兜底. */
    fun send(method: String, args: Any?): Boolean {
        val ch = channel ?: return false
        Log.i(TAG, "notify dart $method $args")
        ch.invokeMethod(method, args)
        return true
    }

    fun notifyActivityResumed() {
        channel?.invokeMethod("onActivityResumed", null)
    }

    fun attach(engine: FlutterEngine, context: Context) {
        // 悬浮窗比 Activity 活得久, 只持有 application context.
        val appContext = context.applicationContext
        MiniPlayerOverlayWindow.init(appContext)
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" ->
                    result.success(MiniPlayerOverlayWindow.canDrawOverlays(appContext))
                "showOverlay" -> {
                    val session = call.argument<Number>("session")?.toLong() ?: 0L
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    val live = call.argument<Boolean>("live") ?: false
                    result.success(MiniPlayerOverlayWindow.show(session, width, height, live))
                }
                "hideOverlay" -> {
                    val session = call.argument<Number>("session")?.toLong() ?: 0L
                    MiniPlayerOverlayWindow.hide(session)
                    result.success(true)
                }
                "concealOverlay" -> {
                    MiniPlayerOverlayWindow.conceal()
                    result.success(true)
                }
                "revealOverlay" -> {
                    MiniPlayerOverlayWindow.reveal()
                    result.success(true)
                }
                "requestOverlayPermission" -> {
                    try {
                        appContext.startActivity(MiniPlayerOverlayWindow.permissionIntent(appContext))
                        result.success(true)
                    } catch (e: Throwable) {
                        Log.w(TAG, "open overlay permission page failed", e)
                        result.success(false)
                    }
                }
                "overlayPlayback" -> {
                    val playing = call.argument<Boolean>("playing") ?: false
                    val position = (call.argument<Number>("position") ?: 0).toInt()
                    val duration = (call.argument<Number>("duration") ?: 0).toInt()
                    val buffered = (call.argument<Number>("buffered") ?: 0).toInt()
                    MiniPlayerOverlayWindow.applyPlayback(playing, position, duration, buffered)
                    result.success(true)
                }
                "bringToFront" -> {
                    val already = MiniPlayerOverlayWindow.bringAppToFront(appContext)
                    result.success(already)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }
}
