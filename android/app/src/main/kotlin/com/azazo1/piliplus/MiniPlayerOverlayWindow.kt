package com.azazo1.piliplus

import android.animation.AnimatorSet
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Outline
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.SurfaceTexture
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar

/**
 * SYSTEM_ALERT_WINDOW 悬浮窗, 画面由同一个 media_kit 播放器直接输出.
 *
 * 参考 B 站 com.bilibili.mini.player.common.view.MiniPlayerFloatViewManager:
 * 它把承载播放器的 View 在 activity window 与 system window 之间搬来搬去,
 * 播放器实例全程不重建, 所以小窗是真正无缝的.
 *
 * Flutter 的画面纹理绑死在引擎/窗口上, 搬不了, 因此这里改用等价做法:
 * 悬浮窗自己提供一个 android.view.Surface (TextureView 的 SurfaceTexture),
 * 把它注册成 media_kit 的 wid, 让 libmpv 把画面重新输出到这个 Surface.
 *
 * 同样对齐 B 站: 进程内单例直接管 WindowManager, 不起 Service (不受前台服务启动限制,
 * 也没有 start/stop 交错). add/remove/update 全部 try/catch.
 * 每次显示带 Dart 下发的 session, 所有回调带回去, Dart 丢弃过期事件.
 * Surface 的释放由 Dart 驱动: Dart 先把 mpv 切走, 再调 [hide] 拆窗, Surface 延迟释放.
 *
 * 布局/交互对齐 B 站 lite 小窗, 白图标 + 半透明遮罩, 进度用项目绿:
 * 单击切控件, 双击切尺寸, 展开只走按钮, 进度不可拖.
 */
@SuppressLint("StaticFieldLeak")
object MiniPlayerOverlayWindow : View.OnTouchListener {
    private const val TAG = "MiniOverlay"
    private const val CORNER_DP = 4
    private const val EDGE_DP = 8
    private const val VERTICAL_INSET_DP = 48
    private const val HIDE_CONTROLS_MS = 6000L
    private const val SNAP_MS = 300L
    private const val HOST_GONE_TIMEOUT_MS = 8000L
    private const val DEFAULT_SIZE_INDEX = 1
    // B 站 MiniPlayerSize: SMALL/DEFAULT/BIG/LARGE
    private val SIZE_MAGS = floatArrayOf(1.0f, 1.3f, 1.62f, 1.92f)
    private val SIZE_VERTICAL = floatArrayOf(0.65f, 0.8f, 1.0f, 1.1f)

    private var appContext: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 当前窗口所属的 Dart session, 0 表示没有窗口. */
    private var session = 0L

    private var windowManager: WindowManager? = null
    private var rootView: FrameLayout? = null
    private var controlsView: FrameLayout? = null
    private var playPause: ImageButton? = null
    private var seekBack: View? = null
    private var seekForward: View? = null
    private var progress: ProgressBar? = null
    private var liveMode = false
    private var params: WindowManager.LayoutParams? = null
    private var gestureDetector: GestureDetector? = null

    private var dragStartX = 0f
    private var dragStartY = 0f
    private var dragging = false
    private var controlsVisible = false
    private var sizeIndex = DEFAULT_SIZE_INDEX
    private var snapAnimator: AnimatorSet? = null
    private val screenSize = Point()
    private val hideControls = Runnable { setControlsVisible(false) }
    private var touchSlopPx = 0

    /** 正在由 [teardownWindow] 主动拆窗, 此时 Surface 销毁不算意外丢失. */
    private var hiding = false

    /** 宿主 Activity 结束后 Dart 迟迟不来收窗时的兜底. */
    private val hostGoneTimeout = Runnable {
        if (rootView != null) {
            Log.w(TAG, "host gone and dart did not hide overlay, tear down session=$session")
            teardownWindow()
        }
    }

    /** 视频原始比例, 用于按比例调整小窗高度. */
    private var videoWidth = 16
    private var videoHeight = 9

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    fun canDrawOverlays(context: Context): Boolean =
        Settings.canDrawOverlays(context)

    fun permissionIntent(context: Context): Intent = Intent(
        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
        Uri.parse("package:${context.packageName}"),
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** 把主 Activity 拉回前台. 已在前台则返回 true. */
    fun bringAppToFront(context: Context): Boolean {
        val activity = MainActivity.instance
        val already =
            activity != null && !activity.isFinishing && activity.hasWindowFocus()
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK
                    or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED,
            )
        }
        context.startActivity(intent)
        return already
    }

    /**
     * 显示悬浮窗. 同一 session 重复调用直接返回 true;
     * 还挂着旧 session 的窗口时先拆掉 (正常情况下 Dart 已经先 hide 过).
     */
    fun show(session: Long, videoWidth: Int, videoHeight: Int, live: Boolean): Boolean {
        val context = appContext ?: return false
        if (!canDrawOverlays(context)) {
            Log.w(TAG, "no overlay permission, abort session=$session")
            return false
        }
        if (!OverlaySurfaceHolder.isAvailable) {
            Log.e(TAG, "media_kit helper unavailable, abort session=$session")
            return false
        }
        if (rootView != null) {
            if (this.session == session) {
                return true
            }
            Log.w(TAG, "drop stale overlay session=${this.session} for session=$session")
            teardownWindow()
        }
        this.session = session
        if (videoWidth > 0 && videoHeight > 0) {
            this.videoWidth = videoWidth
            this.videoHeight = videoHeight
        } else {
            this.videoWidth = 16
            this.videoHeight = 9
        }
        liveMode = live
        return try {
            addWindow(context)
            applyLiveChrome()
            true
        } catch (e: Exception) {
            Log.e(TAG, "add overlay failed, session=$session", e)
            teardownWindow()
            false
        }
    }

    /** 拆窗. 只处理当前 session, 过期的 hide 直接忽略. */
    fun hide(session: Long) {
        if (rootView != null && session != this.session) {
            Log.w(TAG, "ignore stale hide session=$session, current=${this.session}")
            return
        }
        teardownWindow()
    }

    /** 立即隐藏但不拆窗: Surface 保持可用, mpv 可以继续画, 触摸穿透到下面. */
    fun conceal() {
        val layoutParams = params ?: return
        if (layoutParams.alpha == 0f) {
            return
        }
        snapAnimator?.cancel()
        layoutParams.alpha = 0f
        layoutParams.flags = layoutParams.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        updateLayoutSafely(layoutParams)
    }

    /** 撤销 [conceal]. */
    fun reveal() {
        val layoutParams = params ?: return
        if (layoutParams.alpha == 1f) {
            return
        }
        layoutParams.alpha = 1f
        layoutParams.flags =
            layoutParams.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        updateLayoutSafely(layoutParams)
    }

    /** 宿主 Activity 结束: 让 Dart 收窗并释放播放器, Dart 不在了就本地兜底拆窗. */
    fun onHostDestroyed() {
        if (rootView == null) {
            return
        }
        conceal()
        if (!emit("onHostFinishing")) {
            teardownWindow()
            return
        }
        mainHandler.removeCallbacks(hostGoneTimeout)
        mainHandler.postDelayed(hostGoneTimeout, HOST_GONE_TIMEOUT_MS)
    }

    private fun emit(method: String, extra: Map<String, Any> = emptyMap()): Boolean =
        InAppChannel.send(method, extra + ("session" to session))

    private fun teardownWindow() {
        snapAnimator?.cancel()
        snapAnimator = null
        controlsView?.removeCallbacks(hideControls)
        mainHandler.removeCallbacks(hostGoneTimeout)
        val view = rootView
        val wm = windowManager
        rootView = null
        controlsView = null
        playPause = null
        seekBack = null
        seekForward = null
        progress = null
        params = null
        gestureDetector = null
        controlsVisible = false
        dragging = false
        liveMode = false
        if (view != null) {
            hiding = true
            try {
                view.setOnTouchListener(null)
                if (view.isAttachedToWindow) {
                    wm?.removeViewImmediate(view)
                }
            } catch (e: Exception) {
                Log.w(TAG, "removeView failed", e)
            } finally {
                hiding = false
            }
            Log.i(TAG, "overlay removed, session=$session")
        }
        session = 0L
        // mpv 已经被 Dart 切走 (或者播放器正在销毁), Surface 延迟释放.
        OverlaySurfaceHolder.retire()
    }

    private fun addWindow(context: Context) {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealSize(screenSize)
        touchSlopPx = ViewConfiguration.get(context).scaledTouchSlop
        sizeIndex = DEFAULT_SIZE_INDEX

        val (widthPx, heightPx) = windowSizePx(sizeIndex)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val layoutParams = WindowManager.LayoutParams(
            widthPx,
            heightPx,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                or WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
        )
        layoutParams.gravity = Gravity.TOP or Gravity.START
        layoutParams.x = screenSize.x - widthPx - dpToPx(EDGE_DP)
        layoutParams.y = (screenSize.y - heightPx - dpToPx(VERTICAL_INSET_DP)).coerceAtLeast(dpToPx(VERTICAL_INSET_DP))
        params = layoutParams

        val container = FrameLayout(context)
        container.setBackgroundColor(android.graphics.Color.BLACK)
        container.clipToOutline = true
        container.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(
                    0,
                    0,
                    view.width,
                    view.height,
                    dpToPx(CORNER_DP).toFloat(),
                )
            }
        }
        container.elevation = dpToPx(2).toFloat()

        val tv = TextureView(context)
        tv.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(
                surfaceTexture: SurfaceTexture,
                width: Int,
                height: Int,
            ) {
                if (rootView == null) {
                    return
                }
                Log.i(TAG, "overlay surfaceTexture available ${width}x$height session=$session")
                val bufW = videoWidth.coerceAtLeast(1)
                val bufH = videoHeight.coerceAtLeast(1)
                val wid = OverlaySurfaceHolder.obtain(
                    surfaceTexture = surfaceTexture,
                    width = bufW,
                    height = bufH,
                )
                if (wid == 0L) {
                    Log.e(TAG, "obtain wid failed")
                    emit("onSurfaceLost")
                    return
                }
                emit(
                    "onSurfaceReady",
                    mapOf(
                        "wid" to wid.toString(),
                        "width" to bufW,
                        "height" to bufH,
                    ),
                )
            }

            override fun onSurfaceTextureSizeChanged(
                surfaceTexture: SurfaceTexture,
                width: Int,
                height: Int,
            ) {
                OverlaySurfaceHolder.resize(videoWidth.coerceAtLeast(1), videoHeight.coerceAtLeast(1))
            }

            override fun onSurfaceTextureDestroyed(
                surfaceTexture: SurfaceTexture,
            ): Boolean {
                // 返回 false: SurfaceTexture 由 OverlaySurfaceHolder 持有, 等 mpv 切走后延迟释放.
                // 对齐 B 站渲染层 (onSurfaceTextureDestroyed 返回 false, 自己管释放时机).
                if (!hiding) {
                    Log.w(TAG, "overlay surfaceTexture destroyed unexpectedly, session=$session")
                    emit("onSurfaceLost")
                }
                return false
            }

            override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) = Unit
        }
        container.addView(
            tv,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        val controls = buildControls(context)
        controls.visibility = View.GONE
        container.addView(
            controls,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        val bar = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal)
        bar.progressDrawable = context.getDrawable(R.drawable.mini_player_progress)
        bar.max = 1000
        bar.progress = 0
        bar.secondaryProgress = 0
        bar.isClickable = false
        bar.isFocusable = false
        val barParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            dpToPx(2),
            Gravity.BOTTOM,
        )
        container.addView(bar, barParams)
        progress = bar

        gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent): Boolean = true

            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                if (!dragging) {
                    toggleControls()
                }
                return true
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                if (!dragging) {
                    cycleSize()
                }
                return true
            }
        }).also { it.setIsLongpressEnabled(false) }

        container.setOnTouchListener(this)
        tv.setOnTouchListener(this)
        controls.setOnTouchListener(this)
        rootView = container
        controlsView = controls
        wm.addView(container, layoutParams)
        Log.i(TAG, "overlay added: ${widthPx}x$heightPx at (${layoutParams.x}, ${layoutParams.y}) session=$session")
    }

    private fun buildControls(context: Context): FrameLayout {
        val overlay = FrameLayout(context)
        overlay.setBackgroundColor(0x7F000000.toInt())

        val close = iconButton(context, R.drawable.ic_player_close, 8)
        close.contentDescription = "关闭小窗"
        close.setOnClickListener {
            // 先隐藏给出即时反馈; 由 Dart 先把 mpv 切走再调 hide 拆窗. 不要先拆 Surface.
            conceal()
            if (!emit("onOverlayClose")) {
                teardownWindow()
            }
        }
        val closeParams = FrameLayout.LayoutParams(dpToPx(36), dpToPx(36))
        closeParams.gravity = Gravity.TOP or Gravity.START
        overlay.addView(close, closeParams)

        val expand = iconButton(context, R.drawable.ic_player_expand, 8)
        expand.contentDescription = "展开播放页"
        expand.setOnClickListener {
            // 播放页即将盖上来, 先隐藏小窗, 别让它叠在转场上.
            conceal()
            emit("onOverlayTap")
        }
        val expandParams = FrameLayout.LayoutParams(dpToPx(34), dpToPx(34))
        expandParams.gravity = Gravity.TOP or Gravity.END
        overlay.addView(expand, expandParams)

        val center = LinearLayout(context)
        center.orientation = LinearLayout.HORIZONTAL
        center.gravity = Gravity.CENTER
        val rewind = iconButton(context, R.drawable.ic_player_rewind_10s, 4)
        seekBack = rewind
        rewind.contentDescription = "快退 10 秒"
        rewind.setOnClickListener {
            emit("onOverlaySeekBy", mapOf("delta" to -10_000))
            scheduleHide()
        }
        val play = iconButton(context, R.drawable.ic_player_pause, 4)
        play.contentDescription = "播放或暂停"
        play.setOnClickListener {
            emit("onOverlayPlayPause")
            scheduleHide()
        }
        val forward = iconButton(context, R.drawable.ic_player_fast_forward_10s, 4)
        seekForward = forward
        forward.contentDescription = "快进 10 秒"
        forward.setOnClickListener {
            emit("onOverlaySeekBy", mapOf("delta" to 10_000))
            scheduleHide()
        }
        val btnGap = dpToPx(8)
        val rewindParams = LinearLayout.LayoutParams(dpToPx(36), dpToPx(36))
        rewindParams.rightMargin = btnGap
        val playParams = LinearLayout.LayoutParams(dpToPx(36), dpToPx(36))
        val forwardParams = LinearLayout.LayoutParams(dpToPx(36), dpToPx(36))
        forwardParams.leftMargin = btnGap
        center.addView(rewind, rewindParams)
        center.addView(play, playParams)
        center.addView(forward, forwardParams)
        val centerParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
        )
        centerParams.bottomMargin = dpToPx(12)
        overlay.addView(center, centerParams)
        playPause = play
        return overlay
    }

    private fun iconButton(context: Context, icon: Int, paddingDp: Int): ImageButton {
        val btn = ImageButton(context, null, 0)
        btn.setImageResource(icon)
        btn.background = context.getDrawable(R.drawable.mini_player_icon_ripple)
        btn.scaleType = ImageView.ScaleType.CENTER_INSIDE
        btn.minimumWidth = 0
        btn.minimumHeight = 0
        val pad = dpToPx(paddingDp)
        btn.setPadding(pad, pad, pad, pad)
        return btn
    }

    /** 直播没有可拖的进度, 只留播放暂停. */
    private fun applyLiveChrome() {
        val visibility = if (liveMode) View.GONE else View.VISIBLE
        seekBack?.visibility = visibility
        seekForward?.visibility = visibility
        progress?.visibility = visibility
    }

    fun applyPlayback(playing: Boolean, positionMs: Int, durationMs: Int, bufferedMs: Int) {
        playPause?.setImageResource(
            if (playing) R.drawable.ic_player_pause else R.drawable.ic_player_play,
        )
        val duration = durationMs.coerceAtLeast(1)
        progress?.max = duration
        progress?.progress = positionMs.coerceIn(0, duration)
        progress?.secondaryProgress = bufferedMs.coerceIn(0, duration)
    }

    /** 拖拽: 抬起时贴到最近的左右边缘. 单击切控件, 双击切尺寸. */
    override fun onTouch(view: View, event: MotionEvent): Boolean {
        val wm = windowManager ?: return false
        val layoutParams = params ?: return false
        val overlay = rootView ?: return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                dragging = false
                snapAnimator?.cancel()
                dragStartX = event.rawX
                dragStartY = event.rawY
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - dragStartX
                val dy = event.rawY - dragStartY
                val slop = touchSlopPx.coerceAtLeast(1)
                if (!dragging && dx * dx + dy * dy < slop * slop) {
                    gestureDetector?.onTouchEvent(event)
                    return true
                }
                dragging = true
                dragStartX = event.rawX
                dragStartY = event.rawY
                layoutParams.x = (layoutParams.x + dx).toInt()
                layoutParams.y = (layoutParams.y + dy).toInt()
                updateOverlayLayout(wm, overlay, layoutParams)
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (dragging) {
                    snapToEdge(wm, overlay, layoutParams)
                    return true
                }
            }
        }
        gestureDetector?.onTouchEvent(event)
        return true
    }

    private fun toggleControls() {
        setControlsVisible(!controlsVisible)
    }

    private fun setControlsVisible(visible: Boolean) {
        controlsVisible = visible
        val controls = controlsView ?: return
        controls.removeCallbacks(hideControls)
        controls.visibility = if (visible) View.VISIBLE else View.GONE
        if (visible) {
            scheduleHide()
        }
    }

    private fun scheduleHide() {
        val controls = controlsView ?: return
        controls.removeCallbacks(hideControls)
        controls.postDelayed(hideControls, HIDE_CONTROLS_MS)
    }

    private fun cycleSize() {
        val wm = windowManager ?: return
        val overlay = rootView ?: return
        val layoutParams = params ?: return
        sizeIndex = (sizeIndex + 1) % SIZE_MAGS.size
        val (newW, newH) = windowSizePx(sizeIndex)
        val wasRight = layoutParams.x + layoutParams.width / 2 > screenSize.x / 2
        layoutParams.width = newW
        layoutParams.height = newH
        layoutParams.x = if (wasRight) {
            screenSize.x - newW - dpToPx(EDGE_DP)
        } else {
            dpToPx(EDGE_DP)
        }
        clampVertical(layoutParams)
        updateOverlayLayout(wm, overlay, layoutParams)
        overlay.invalidateOutline()
        Log.i(TAG, "overlay size index=$sizeIndex ${newW}x$newH")
    }

    private fun windowSizePx(index: Int): Pair<Int, Int> {
        val i = index.coerceIn(0, SIZE_MAGS.lastIndex)
        val mag = if (videoHeight > videoWidth) SIZE_VERTICAL[i] else SIZE_MAGS[i]
        val minSide = minOf(screenSize.x, screenSize.y)
        val base = ((minSide - dpToPx(22)) / 2).coerceAtLeast(dpToPx(120))
        val w = (base * mag).toInt().coerceAtLeast(dpToPx(96))
        val h = (w * videoHeight / videoWidth.toFloat()).toInt().coerceAtLeast(1)
        return w to h
    }

    private fun clampVertical(layoutParams: WindowManager.LayoutParams) {
        val inset = dpToPx(VERTICAL_INSET_DP)
        val maxY = (screenSize.y - layoutParams.height - inset).coerceAtLeast(inset)
        layoutParams.y = layoutParams.y.coerceIn(inset, maxY)
    }

    /** 对齐 B 站 MiniPlayerFloatViewManager: DecelerateInterpolator + 300ms 滑到左右边缘. */
    private fun snapToEdge(
        wm: WindowManager,
        overlay: View,
        layoutParams: WindowManager.LayoutParams,
    ) {
        snapAnimator?.cancel()
        val margin = dpToPx(EDGE_DP)
        val halfway = (screenSize.x - layoutParams.width) / 2
        val targetX = if (layoutParams.x < halfway) {
            margin
        } else {
            screenSize.x - layoutParams.width - margin
        }
        val inset = dpToPx(VERTICAL_INSET_DP)
        val maxY = (screenSize.y - layoutParams.height - inset).coerceAtLeast(inset)
        val targetY = layoutParams.y.coerceIn(inset, maxY)
        val interpolator = DecelerateInterpolator()
        val ax = ValueAnimator.ofInt(layoutParams.x, targetX).setDuration(SNAP_MS)
        ax.interpolator = interpolator
        ax.addUpdateListener {
            layoutParams.x = it.animatedValue as Int
            updateOverlayLayout(wm, overlay, layoutParams)
        }
        val ay = ValueAnimator.ofInt(layoutParams.y, targetY).setDuration(SNAP_MS)
        ay.interpolator = interpolator
        ay.addUpdateListener {
            layoutParams.y = it.animatedValue as Int
            updateOverlayLayout(wm, overlay, layoutParams)
        }
        snapAnimator = AnimatorSet().apply {
            play(ax).with(ay)
            start()
        }
    }

    private fun updateLayoutSafely(layoutParams: WindowManager.LayoutParams) {
        val wm = windowManager ?: return
        val overlay = rootView ?: return
        updateOverlayLayout(wm, overlay, layoutParams)
    }

    private fun updateOverlayLayout(
        wm: WindowManager,
        overlay: View,
        layoutParams: WindowManager.LayoutParams,
    ) {
        // 对齐 B 站: 先确认 View 仍挂在窗口上, 再 updateViewLayout.
        if (!overlay.isAttachedToWindow) {
            return
        }
        try {
            wm.updateViewLayout(overlay, layoutParams)
        } catch (e: Exception) {
            Log.w(TAG, "overlay not attached, skip layout update", e)
        }
    }

    private fun dpToPx(dp: Int): Int {
        val density = appContext?.resources?.displayMetrics?.density ?: 1f
        return (dp * density).toInt()
    }
}
