package com.azazo1.piliplus

import android.animation.AnimatorSet
import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Outline
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.SurfaceTexture
import android.net.Uri
import android.os.Build
import android.os.IBinder
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
import android.widget.Toast

/**
 * 小窗 spike: SYSTEM_ALERT_WINDOW 悬浮窗, 画面由**同一个** media_kit 播放器直接输出.
 *
 * 参考 B 站 com.bilibili.mini.player.common.view.MiniPlayerFloatViewManager:
 * 它把承载播放器的 View 在 activity window 与 system window 之间搬来搬去,
 * 播放器实例全程不重建, 所以小窗是真正无缝的.
 *
 * Flutter 的画面纹理绑死在引擎/窗口上, 搬不了, 因此这里改用等价做法:
 * 悬浮窗自己提供一个 android.view.Surface (TextureView 的 SurfaceTexture),
 * 把它注册成 media_kit 的 wid, 让 libmpv 把画面重新输出到这个 Surface.
 * 播放器实例, 解码器, 播放位置, 音频全部保持原样, 因此同样无缝.
 *
 * 布局/交互对齐 B 站 lite 小窗, 白图标 + 半透明遮罩, 进度用项目绿:
 * 单击切控件, 双击切尺寸, 展开只走按钮, 进度不可拖.
 *
 * todo remove 小窗 spike 验证完成后删除本文件与清单里的 service / 权限声明
 */
class MiniPlayerOverlayService : Service(), View.OnTouchListener {
    companion object {
        private const val TAG = "MiniOverlaySpike"
        private const val CHANNEL_ID = "mini_overlay_spike"
        private const val NOTIFY_ID = 0x5152
        const val ACTION_STOP = "com.azazo1.piliplus.action.STOP_MINI_OVERLAY"
        private const val EXTRA_VIDEO_WIDTH = "videoWidth"
        private const val EXTRA_VIDEO_HEIGHT = "videoHeight"
        private const val CORNER_DP = 4
        private const val EDGE_DP = 8
        private const val VERTICAL_INSET_DP = 48
        private const val HIDE_CONTROLS_MS = 6000L
        private const val SNAP_MS = 300L
        private const val DEFAULT_SIZE_INDEX = 1
        // B 站 MiniPlayerSize: SMALL/DEFAULT/BIG/LARGE
        private val SIZE_MAGS = floatArrayOf(1.0f, 1.3f, 1.62f, 1.92f)
        private val SIZE_VERTICAL = floatArrayOf(0.65f, 0.8f, 1.0f, 1.1f)

        /** Dart 侧控制通道 (只在主引擎上). */
        const val SPIKE_CHANNEL = "com.azazo1.piliplus/spike"

        @Volatile
        var isRunning: Boolean = false
            private set

        fun canDrawOverlays(context: Context): Boolean =
            Settings.canDrawOverlays(context)

        fun permissionIntent(context: Context): Intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        )

        fun start(context: Context, videoWidth: Int = 0, videoHeight: Int = 0) {
            val intent = Intent(context, MiniPlayerOverlayService::class.java)
            if (videoWidth > 0) {
                intent.putExtra(EXTRA_VIDEO_WIDTH, videoWidth)
            }
            if (videoHeight > 0) {
                intent.putExtra(EXTRA_VIDEO_HEIGHT, videoHeight)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, MiniPlayerOverlayService::class.java).setAction(ACTION_STOP),
            )
        }

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
    }

    private var windowManager: WindowManager? = null
    private var rootView: FrameLayout? = null
    private var textureView: TextureView? = null
    private var controlsView: FrameLayout? = null
    private var playPause: ImageButton? = null
    private var progress: ProgressBar? = null
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

    /** 视频原始比例, 用于按比例调整小窗高度. */
    private var videoWidth = 16
    private var videoHeight = 9

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        InAppChannel.overlayWindow = this
        createNotificationChannel()
        startForeground(NOTIFY_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!canDrawOverlays(this)) {
            Log.w(TAG, "no overlay permission, abort")
            Toast.makeText(this, "缺少悬浮窗权限", Toast.LENGTH_SHORT).show()
            stopSelf()
            return START_NOT_STICKY
        }
        val vw = intent?.getIntExtra(EXTRA_VIDEO_WIDTH, 0) ?: 0
        val vh = intent?.getIntExtra(EXTRA_VIDEO_HEIGHT, 0) ?: 0
        if (vw > 0 && vh > 0) {
            videoWidth = vw
            videoHeight = vh
        }
        showOverlay()
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        snapAnimator?.cancel()
        snapAnimator = null
        controlsView?.removeCallbacks(hideControls)
        InAppChannel.overlayWindow = null
        val view = rootView
        if (view != null) {
            try {
                view.setOnTouchListener(null)
                windowManager?.removeView(view)
            } catch (e: Exception) {
                Log.w(TAG, "removeView failed", e)
            }
        }
        rootView = null
        textureView = null
        controlsView = null
        playPause = null
        progress = null
        // 画面目标即将消失, 通知 Dart 把输出切回主页面纹理, 否则主页面会黑
        OverlaySurfaceHolder.release()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFY_ID)
        super.onDestroy()
    }

    private fun showOverlay() {
        if (rootView != null) {
            return
        }
        if (!OverlaySurfaceHolder.isAvailable) {
            Log.e(TAG, "media_kit helper unavailable, abort")
            Toast.makeText(this, "media_kit helper 不可用", Toast.LENGTH_SHORT).show()
            stopSelf()
            return
        }
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealSize(screenSize)
        touchSlopPx = ViewConfiguration.get(this).scaledTouchSlop
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

        val container = FrameLayout(this)
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

        val tv = TextureView(this)
        tv.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(
                surfaceTexture: SurfaceTexture,
                width: Int,
                height: Int,
            ) {
                Log.i(TAG, "overlay surfaceTexture available ${width}x$height")
                val bufW = videoWidth.coerceAtLeast(1)
                val bufH = videoHeight.coerceAtLeast(1)
                val wid = OverlaySurfaceHolder.obtain(
                    surfaceTexture = surfaceTexture,
                    width = bufW,
                    height = bufH,
                )
                if (wid == 0L) {
                    Log.e(TAG, "obtain wid failed")
                    return
                }
                InAppChannel.onOverlaySurfaceReady?.invoke(
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
                Log.i(TAG, "overlay surfaceTexture destroyed")
                InAppChannel.onOverlaySurfaceLost?.invoke()
                OverlaySurfaceHolder.release()
                return true
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

        val controls = buildControls()
        controls.visibility = View.GONE
        container.addView(
            controls,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        val bar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        bar.progressDrawable = getDrawable(R.drawable.mini_player_progress)
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

        gestureDetector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
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
        textureView = tv
        controlsView = controls
        wm.addView(container, layoutParams)
        isRunning = true
        Log.i(TAG, "overlay added: ${widthPx}x$heightPx at (${layoutParams.x}, ${layoutParams.y})")
    }

    private fun buildControls(): FrameLayout {
        val overlay = FrameLayout(this)
        overlay.setBackgroundColor(0x7F000000.toInt())

        val close = iconButton(R.drawable.ic_player_close, 8)
        close.contentDescription = "关闭小窗"
        close.setOnClickListener {
            // 先通知 Dart 把 wid 切回家, 再由 Dart 调 stopOverlay. 不要先拆 Surface.
            InAppChannel.onOverlayClose?.invoke()
        }
        val closeParams = FrameLayout.LayoutParams(dpToPx(36), dpToPx(36))
        closeParams.gravity = Gravity.TOP or Gravity.START
        overlay.addView(close, closeParams)

        val expand = iconButton(R.drawable.ic_player_expand, 8)
        expand.contentDescription = "展开播放页"
        expand.setOnClickListener {
            InAppChannel.onOverlayTap?.invoke()
        }
        val expandParams = FrameLayout.LayoutParams(dpToPx(34), dpToPx(34))
        expandParams.gravity = Gravity.TOP or Gravity.END
        overlay.addView(expand, expandParams)

        val center = LinearLayout(this)
        center.orientation = LinearLayout.HORIZONTAL
        center.gravity = Gravity.CENTER
        val rewind = iconButton(R.drawable.ic_player_rewind_10s, 4)
        rewind.contentDescription = "快退 10 秒"
        rewind.setOnClickListener {
            InAppChannel.onOverlaySeekBy?.invoke(-10_000)
            scheduleHide()
        }
        val play = iconButton(R.drawable.ic_player_pause, 4)
        play.contentDescription = "播放或暂停"
        play.setOnClickListener {
            InAppChannel.onOverlayPlayPause?.invoke()
            scheduleHide()
        }
        val forward = iconButton(R.drawable.ic_player_fast_forward_10s, 4)
        forward.contentDescription = "快进 10 秒"
        forward.setOnClickListener {
            InAppChannel.onOverlaySeekBy?.invoke(10_000)
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

    private fun iconButton(icon: Int, paddingDp: Int): ImageButton {
        val btn = ImageButton(this, null, 0)
        btn.setImageResource(icon)
        btn.background = getDrawable(R.drawable.mini_player_icon_ripple)
        btn.scaleType = ImageView.ScaleType.CENTER_INSIDE
        btn.minimumWidth = 0
        btn.minimumHeight = 0
        val pad = dpToPx(paddingDp)
        btn.setPadding(pad, pad, pad, pad)
        return btn
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

    /** 按视频真实比例调整小窗高度, 避免画面被拉伸. */
    fun applyVideoSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) {
            return
        }
        videoWidth = width
        videoHeight = height
        val wm = windowManager ?: return
        val view = rootView ?: return
        val layoutParams = params ?: return
        val (newW, newH) = windowSizePx(sizeIndex)
        if (newW == layoutParams.width && newH == layoutParams.height) {
            return
        }
        val wasRight = layoutParams.x + layoutParams.width / 2 > screenSize.x / 2
        layoutParams.width = newW
        layoutParams.height = newH
        layoutParams.x = if (wasRight) {
            screenSize.x - newW - dpToPx(EDGE_DP)
        } else {
            dpToPx(EDGE_DP)
        }
        clampVertical(layoutParams)
        try {
            wm.updateViewLayout(view, layoutParams)
        } catch (e: Exception) {
            Log.w(TAG, "resize overlay failed", e)
        }
        view.invalidateOutline()
        Log.i(TAG, "overlay resized to ${newW}x$newH for ${width}x$height")
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

    private fun updateOverlayLayout(
        wm: WindowManager,
        overlay: View,
        layoutParams: WindowManager.LayoutParams,
    ) {
        try {
            wm.updateViewLayout(overlay, layoutParams)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "overlay not attached, skip drag", e)
        }
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density).toInt()

    private fun buildNotification(): Notification {
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            pendingFlags,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("小窗播放中")
            .setContentText("点击回到 PiliPlus")
            .setSmallIcon(R.drawable.ic_notification_icon)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "小窗播放",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
    }
}
