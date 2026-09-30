package com.azazo1.piliplus

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.HardwareRenderer
import android.graphics.Rect
import android.graphics.RenderNode
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.PixelCopy
import android.view.ScrollCaptureCallback
import android.view.ScrollCaptureSession
import android.view.Surface
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.function.Consumer

private const val TAG = "ScrollCapture"
private const val CHANNEL = "com.azazo1.piliplus/scroll_capture"
private const val METHOD_SEARCH = "search"
private const val METHOD_START = "start"
private const val METHOD_REQUEST = "request"
private const val METHOD_END = "end"

/** 取图前等待的帧数, 用于等待 Dart 侧滚动后的画面绘制上屏. */
private const val FRAME_WAIT = 2

/** 等待 Dart 侧响应的超时时间. */
private const val RESPONSE_TIMEOUT_MS = 2000L

/** 一次取图 (滚动加拷贝) 的超时时间. */
private const val REQUEST_TIMEOUT_MS = 5000L

/**
 * 长截屏接入: Android 12 及以上系统截图界面里的 "截取更多".
 *
 * Flutter 界面绘制在一张纹理上, 系统无法自行滚动界面来拼接长图, 因此这里把系统的
 * 请求转发给 Dart 侧 (由 Dart 侧找到主滚动列表并滚动到指定位置), 原生侧只负责把
 * 当前画面拷贝到系统提供的 Surface 上.
 */
object ScrollCaptureSupport {
    private var target: View? = null
    private var callback: FlutterScrollCaptureCallback? = null

    /** 在窗口里找到 FlutterView 并注册滚动截屏回调. */
    fun attach(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        try {
            val decorView = activity.window?.decorView as? ViewGroup ?: return
            val flutterView = findFlutterView(decorView) ?: return
            if (target === flutterView && callback != null) return
            detach(activity)
            val instance = FlutterScrollCaptureCallback(activity, flutterView)
            flutterView.setScrollCaptureHint(View.SCROLL_CAPTURE_HINT_INCLUDE)
            flutterView.setScrollCaptureCallback(instance)
            target = flutterView
            callback = instance
        } catch (e: Throwable) {
            Log.w(TAG, "attach failed", e)
        }
    }

    fun detach(activity: Activity) {
        val view = target
        // Activity 重建时新实例可能已经注册, 此时不要动它.
        if (view != null && view.context !== activity) return
        if (view != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                view.setScrollCaptureCallback(null)
                view.setScrollCaptureHint(View.SCROLL_CAPTURE_HINT_AUTO)
            } catch (e: Exception) {
                Log.w(TAG, "detach failed", e)
            }
        }
        target = null
        callback = null
    }

    private fun findFlutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findFlutterView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }
}

/** 保证只执行一次. */
private fun onceRun(action: () -> Unit): () -> Unit {
    val done = AtomicBoolean(false)
    return { if (done.compareAndSet(false, true)) action() }
}

/** 保证只回调一次. */
private fun onceRect(action: (Rect) -> Unit): (Rect) -> Unit {
    val done = AtomicBoolean(false)
    return { rect -> if (done.compareAndSet(false, true)) action(rect) }
}

/** Dart 侧回报的取图区域, [capturedTop] 是这块画面在长图中的位置. */
private class CaptureArea(
    val left: Int,
    val top: Int,
    val width: Int,
    val height: Int,
    val capturedTop: Int,
)

@RequiresApi(Build.VERSION_CODES.S)
private class FlutterScrollCaptureCallback(
    private val activity: Activity,
    private val flutterView: FlutterView,
) : ScrollCaptureCallback {
    private val handler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(flutterView.binaryMessenger, CHANNEL)

    /** 当前会话的滚动区域, 没有会话时为 null. */
    private var scrollBounds: Rect? = null

    private var renderer: HardwareRenderer? = null
    private var renderNode: RenderNode? = null

    override fun onScrollCaptureSearch(signal: CancellationSignal, onReady: Consumer<Rect>) {
        val ready = onceRect(onReady::accept)
        handler.postDelayed({ ready(Rect()) }, RESPONSE_TIMEOUT_MS)
        invoke(METHOD_SEARCH, null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                val bounds = toBounds(result)
                Log.d(TAG, "search -> $bounds")
                if (!signal.isCanceled) ready(bounds ?: Rect())
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.w(TAG, "search failed: $errorCode $errorMessage")
                ready(Rect())
            }

            override fun notImplemented() = ready(Rect())
        })
    }

    override fun onScrollCaptureStart(
        session: ScrollCaptureSession,
        signal: CancellationSignal,
        onReady: Runnable,
    ) {
        val ready = onceRun(onReady::run)
        handler.postDelayed(Runnable(ready), RESPONSE_TIMEOUT_MS)
        scrollBounds = Rect(session.scrollBounds)
        Log.d(TAG, "start $scrollBounds")
        invoke(METHOD_START, null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (result != true) {
                    scrollBounds = null
                    Log.w(TAG, "start rejected by dart")
                }
                ready()
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.w(TAG, "start failed: $errorCode $errorMessage")
                scrollBounds = null
                ready()
            }

            override fun notImplemented() {
                scrollBounds = null
                ready()
            }
        })
    }

    override fun onScrollCaptureImageRequest(
        session: ScrollCaptureSession,
        signal: CancellationSignal,
        captureArea: Rect,
        onComplete: Consumer<Rect>,
    ) {
        val bounds = scrollBounds
        val done = onceRect { rect -> if (!signal.isCanceled) onComplete.accept(rect) }
        handler.postDelayed({ done(Rect()) }, REQUEST_TIMEOUT_MS)
        if (bounds == null || captureArea.isEmpty()) {
            done(Rect())
            return
        }

        val args = HashMap<String, Any>(2)
        args["top"] = captureArea.top
        args["bottom"] = captureArea.bottom
        invoke(METHOD_REQUEST, args, object : MethodChannel.Result {
            override fun success(result: Any?) {
                val area = toCaptureArea(result)
                Log.d(TAG, "request $captureArea -> $area")
                if (area == null) {
                    done(Rect())
                    return
                }
                // 等滚动后的画面绘制上屏, 否则拷贝到的还是滚动前的像素.
                waitFrames(FRAME_WAIT) {
                    if (signal.isCanceled) return@waitFrames
                    capturePixels(area) { bitmap ->
                        if (bitmap == null) {
                            done(Rect())
                            return@capturePixels
                        }
                        // 位图交给系统后会立即释放, 尺寸先取出来.
                        val width = bitmap.width
                        val height = bitmap.height
                        if (!drawToSurface(session.surface, bitmap)) {
                            done(Rect())
                            return@capturePixels
                        }
                        done(Rect(0, area.capturedTop, width, height))
                    }
                }
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.w(TAG, "request failed: $errorCode $errorMessage")
                done(Rect())
            }

            override fun notImplemented() = done(Rect())
        })
    }

    override fun onScrollCaptureEnd(onReady: Runnable) {
        Log.d(TAG, "end")
        scrollBounds = null
        releaseRenderer()
        val ready = onceRun(onReady::run)
        handler.postDelayed(Runnable(ready), RESPONSE_TIMEOUT_MS)
        invoke(METHOD_END, null, object : MethodChannel.Result {
            override fun success(result: Any?) = ready()

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.w(TAG, "end failed: $errorCode $errorMessage")
                ready()
            }

            override fun notImplemented() = ready()
        })
    }

    private fun invoke(method: String, args: Any?, result: MethodChannel.Result) {
        try {
            channel.invokeMethod(method, args, result)
        } catch (e: Exception) {
            Log.w(TAG, "invoke $method failed", e)
            result.error("channel", e.message, null)
        }
    }

    private fun waitFrames(count: Int, action: () -> Unit) {
        if (count <= 0) {
            action()
            return
        }
        flutterView.postOnAnimation { waitFrames(count - 1, action) }
    }

    /** 拷贝 [area] 区域当前的画面. */
    private fun capturePixels(area: CaptureArea, onDone: (Bitmap?) -> Unit) {
        val source = findSurfaceView(flutterView)
        val bitmap = try {
            Bitmap.createBitmap(area.width, area.height, Bitmap.Config.ARGB_8888)
        } catch (e: Throwable) {
            Log.w(TAG, "create bitmap failed", e)
            onDone(null)
            return
        }
        // 失败时释放掉已经申请的位图, 避免连续失败累积占用内存.
        fun fail(reason: String) {
            Log.w(TAG, reason)
            bitmap.recycle()
            onDone(null)
        }

        try {
            when (source) {
                // 默认渲染模式下画面在独立的 surface 上.
                is SurfaceView -> {
                    val offsetX = area.left - source.left
                    val offsetY = area.top - source.top
                    // 请求区域必须完整落在 surface 内, 否则拷贝到的画面会错位.
                    if (offsetX < 0 ||
                        offsetY < 0 ||
                        offsetX + area.width > source.width ||
                        offsetY + area.height > source.height
                    ) {
                        fail("capture area $area outside surface ${source.width}x${source.height}")
                        return
                    }
                    PixelCopy.request(
                        source,
                        Rect(offsetX, offsetY, offsetX + area.width, offsetY + area.height),
                        bitmap,
                        { result ->
                            if (result == PixelCopy.SUCCESS) {
                                onDone(bitmap)
                            } else {
                                fail("pixel copy failed: $result")
                            }
                        },
                        handler,
                    )
                }

                // texture 渲染模式下画面由 TextureView 持有.
                is TextureView -> {
                    val content = source.getBitmap(source.width, source.height)
                    if (content == null) {
                        fail("texture bitmap unavailable")
                        return
                    }
                    val left = (area.left - source.left).coerceIn(
                        0,
                        (content.width - area.width).coerceAtLeast(0),
                    )
                    val top = (area.top - source.top).coerceIn(
                        0,
                        (content.height - area.height).coerceAtLeast(0),
                    )
                    val width = area.width.coerceAtMost(content.width - left)
                    val height = area.height.coerceAtMost(content.height - top)
                    if (width <= 0 || height <= 0) {
                        fail("capture area $area outside texture ${content.width}x${content.height}")
                        return
                    }
                    val cropped = Bitmap.createBitmap(content, left, top, width, height)
                    content.recycle()
                    bitmap.recycle()
                    onDone(cropped)
                }

                // hybrid composition 下画面就在窗口里.
                else -> {
                    val location = IntArray(2)
                    flutterView.getLocationInWindow(location)
                    val left = area.left + location[0]
                    val top = area.top + location[1]
                    PixelCopy.request(
                        activity.window,
                        Rect(left, top, left + area.width, top + area.height),
                        bitmap,
                        { result ->
                            if (result == PixelCopy.SUCCESS) {
                                onDone(bitmap)
                            } else {
                                fail("window pixel copy failed: $result")
                            }
                        },
                        handler,
                    )
                }
            }
        } catch (e: Throwable) {
            fail("capture failed: $e")
        }
    }

    /** 把画面交给系统用于拼接长图. */
    private fun drawToSurface(surface: Surface, bitmap: Bitmap): Boolean {
        return try {
            prepareRenderer(surface)
            val node = renderNode
            val instance = renderer
            if (node == null || instance == null) {
                bitmap.recycle()
                return false
            }
            node.setPosition(0, 0, bitmap.width, bitmap.height)
            val canvas = node.beginRecording()
            canvas.drawBitmap(bitmap, 0f, 0f, null)
            node.endRecording()
            val request = instance.createRenderRequest()
            request.setVsyncTime(System.nanoTime())
            request.syncAndDraw()
            bitmap.recycle()
            true
        } catch (e: Throwable) {
            Log.w(TAG, "draw failed", e)
            bitmap.recycle()
            false
        }
    }

    /** 建立往系统提供的 surface 上绘制的渲染通道. */
    private fun prepareRenderer(surface: Surface) {
        if (renderer != null && renderNode != null) return
        val node = RenderNode("PiliScrollCapture")
        val instance = HardwareRenderer()
        instance.setName("PiliScrollCapture")
        instance.setContentRoot(node)
        instance.setSurface(surface)
        instance.setOpaque(false)
        renderNode = node
        renderer = instance
    }

    private fun releaseRenderer() {
        try {
            renderer?.destroy()
        } catch (e: Exception) {
            Log.w(TAG, "release renderer failed", e)
        }
        renderer = null
        renderNode = null
    }

    private fun findSurfaceView(view: View): View? {
        if (view is SurfaceView || view is TextureView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findSurfaceView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }
}

private fun toBounds(result: Any?): Rect? {
    val map = result as? Map<*, *> ?: return null
    val left = (map["left"] as? Number)?.toInt() ?: return null
    val top = (map["top"] as? Number)?.toInt() ?: return null
    val width = (map["width"] as? Number)?.toInt() ?: return null
    val height = (map["height"] as? Number)?.toInt() ?: return null
    if (width <= 0 || height <= 0) return null
    return Rect(left, top, left + width, top + height)
}

private fun toCaptureArea(result: Any?): CaptureArea? {
    val map = result as? Map<*, *> ?: return null
    val left = (map["left"] as? Number)?.toInt() ?: return null
    val top = (map["top"] as? Number)?.toInt() ?: return null
    val width = (map["width"] as? Number)?.toInt() ?: return null
    val height = (map["height"] as? Number)?.toInt() ?: return null
    val capturedTop = (map["capturedTop"] as? Number)?.toInt() ?: return null
    if (width <= 0 || height <= 0) return null
    return CaptureArea(left, top, width, height, capturedTop)
}
