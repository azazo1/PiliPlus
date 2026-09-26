package com.azazo1.piliplus

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 小窗 spike: 主 Flutter 引擎 (MainActivity) 与悬浮窗 Service 之间的通道.
 *
 * 悬浮窗只负责提供 Surface; 播放器始终只有一个, 活在主引擎里.
 * Service 拿到 Surface 的 wid 之后通过这里回传给 Dart, 由 Dart 把 mpv 输出切过去.
 *
 * todo remove 小窗 spike 验证完成后删除本文件
 */
object InAppChannel {
    private const val TAG = "MiniOverlaySpike"

    /** Dart 侧控制通道 (同一个名字在 Dart 与 MainActivity 各注册一次). */
    const val CHANNEL = "com.azazo1.piliplus/spike"

    /** 当前存活的悬浮窗 Service, 供主引擎调用 (如按视频比例调整高度). */
    @Volatile
    var overlayWindow: MiniPlayerOverlayService? = null

    /** 悬浮窗 Surface 就绪, 参数是 wid 字符串. */
    @Volatile
    var onOverlaySurfaceReady: ((String) -> Unit)? = null

    /** 悬浮窗 Surface 即将消失, Dart 需要把输出切回主页面. */
    @Volatile
    var onOverlaySurfaceLost: (() -> Unit)? = null

    /** 用户点了小窗上的关闭按钮. */
    @Volatile
    var onOverlayClose: (() -> Unit)? = null

    private var channel: MethodChannel? = null

    fun attach(engine: FlutterEngine, context: Context) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" ->
                    result.success(MiniPlayerOverlayService.canDrawOverlays(context))
                "startOverlay" -> {
                    onOverlaySurfaceReady = { wid ->
                        Log.i(TAG, "notify dart surface ready wid=$wid")
                        channel?.invokeMethod("onSurfaceReady", wid)
                    }
                    onOverlaySurfaceLost = {
                        Log.i(TAG, "notify dart surface lost")
                        channel?.invokeMethod("onSurfaceLost", null)
                    }
                    onOverlayClose = {
                        Log.i(TAG, "notify dart overlay close")
                        channel?.invokeMethod("onOverlayClose", null)
                    }
                    MiniPlayerOverlayService.start(context)
                    result.success(true)
                }
                "stopOverlay" -> {
                    MiniPlayerOverlayService.stop(context)
                    result.success(true)
                }
                "isOverlayRunning" ->
                    result.success(MiniPlayerOverlayService.isRunning)
                "requestOverlayPermission" -> {
                    try {
                        context.startActivity(MiniPlayerOverlayService.permissionIntent(context))
                        result.success(true)
                    } catch (e: Throwable) {
                        Log.w(TAG, "open overlay permission page failed", e)
                        result.success(false)
                    }
                }
                "applyVideoSize" -> {
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    overlayWindow?.applyVideoSize(width, height)
                    result.success(true)
                }
                // 读出 media_kit 为主页面纹理保存的 wid, 供切回时恢复输出
                "readHomeWid" -> {
                    val handle = call.argument<String>("handle")?.toLongOrNull() ?: 0L
                    result.success(OverlaySurfaceHolder.readHomeWid(handle).toString())
                }
                "overlayWid" ->
                    result.success(OverlaySurfaceHolder.currentWid().toString())
                "log" -> {
                    Log.i(TAG, "dart: ${call.arguments}")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }
}
