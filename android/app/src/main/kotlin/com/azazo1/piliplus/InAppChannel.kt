package com.azazo1.piliplus

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Flutter 引擎 (MainActivity) 与悬浮窗 Service 之间的通道.
 *
 * 悬浮窗只负责提供 Surface; 播放器始终只有一个, 活在主引擎里.
 * Service 拿到 Surface 的 wid 之后通过这里回传给 Dart, 由 Dart 把 mpv 输出切过去.
 */
object InAppChannel {
    private const val TAG = "MiniOverlay"

    /** Dart 侧控制通道 (同一个名字在 Dart 与 MainActivity 各注册一次). */
    const val CHANNEL = "com.azazo1.piliplus/mini_player"

    /** 当前存活的悬浮窗 Service, 供主引擎调用 (如按视频比例调整高度). */
    @Volatile
    var overlayWindow: MiniPlayerOverlayService? = null

    /** 悬浮窗 Surface 就绪, 参数是 wid/width/height. */
    @Volatile
    var onOverlaySurfaceReady: ((Map<String, Any>) -> Unit)? = null

    /** 悬浮窗 Surface 即将消失, Dart 需要把输出切回主页面. */
    @Volatile
    var onOverlaySurfaceLost: (() -> Unit)? = null

    /** 用户点了小窗上的关闭按钮. */
    @Volatile
    var onOverlayClose: (() -> Unit)? = null

    /** 用户点了小窗展开按钮, 回到播放页. */
    @Volatile
    var onOverlayTap: (() -> Unit)? = null

    /** 用户点了小窗播放/暂停. */
    @Volatile
    var onOverlayPlayPause: (() -> Unit)? = null

    /** 用户点了快进/快退, 参数是毫秒偏移. */
    @Volatile
    var onOverlaySeekBy: ((Int) -> Unit)? = null

    private var channel: MethodChannel? = null

    fun notifyActivityResumed() {
        channel?.invokeMethod("onActivityResumed", null)
    }

    fun attach(engine: FlutterEngine, context: Context) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" ->
                    result.success(MiniPlayerOverlayService.canDrawOverlays(context))
                "startOverlay" -> {
                    onOverlaySurfaceReady = { payload ->
                        Log.i(TAG, "notify dart surface ready $payload")
                        channel?.invokeMethod("onSurfaceReady", payload)
                    }
                    onOverlaySurfaceLost = {
                        Log.i(TAG, "notify dart surface lost")
                        channel?.invokeMethod("onSurfaceLost", null)
                    }
                    onOverlayClose = {
                        Log.i(TAG, "notify dart overlay close")
                        channel?.invokeMethod("onOverlayClose", null)
                    }
                    onOverlayTap = {
                        Log.i(TAG, "notify dart overlay tap")
                        channel?.invokeMethod("onOverlayTap", null)
                    }
                    onOverlayPlayPause = {
                        Log.i(TAG, "notify dart overlay playPause")
                        channel?.invokeMethod("onOverlayPlayPause", null)
                    }
                    onOverlaySeekBy = { deltaMs ->
                        Log.i(TAG, "notify dart overlay seekBy $deltaMs")
                        channel?.invokeMethod("onOverlaySeekBy", deltaMs)
                    }
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    val live = call.argument<Boolean>("live") ?: false
                    MiniPlayerOverlayService.start(context, width, height, live)
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
                "overlayPlayback" -> {
                    val playing = call.argument<Boolean>("playing") ?: false
                    val position = (call.argument<Number>("position") ?: 0).toInt()
                    val duration = (call.argument<Number>("duration") ?: 0).toInt()
                    val buffered = (call.argument<Number>("buffered") ?: 0).toInt()
                    overlayWindow?.applyPlayback(playing, position, duration, buffered)
                    result.success(true)
                }
                // 读出 media_kit 为主页面纹理保存的 wid, 供切回时恢复输出
                "readHomeWid" -> {
                    val handle = call.argument<String>("handle")?.toLongOrNull() ?: 0L
                    result.success(OverlaySurfaceHolder.readHomeWid(handle).toString())
                }
                "overlayWid" ->
                    result.success(OverlaySurfaceHolder.currentWid().toString())
                "bringToFront" -> {
                    val already = MiniPlayerOverlayService.bringAppToFront(context)
                    result.success(already)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }
}
