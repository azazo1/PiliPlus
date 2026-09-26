package com.azazo1.piliplus

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Point
import android.graphics.SurfaceTexture
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.TextView
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
    }

    private var windowManager: WindowManager? = null
    private var rootView: FrameLayout? = null
    private var textureView: TextureView? = null
    private var params: WindowManager.LayoutParams? = null

    private var dragStartX = 0f
    private var dragStartY = 0f
    private var dragging = false
    private val screenSize = Point()

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

        val widthPx = dpToPx(280)
        val heightPx = (widthPx * videoHeight / videoWidth.toFloat()).toInt()
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
        layoutParams.x = screenSize.x - widthPx - dpToPx(8)
        layoutParams.y = screenSize.y - heightPx - dpToPx(120)
        params = layoutParams

        val container = FrameLayout(this)
        container.setBackgroundColor(android.graphics.Color.BLACK)

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

        val close = ImageButton(this)
        close.setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
        close.setBackgroundColor(android.graphics.Color.argb(120, 0, 0, 0))
        val closeSize = dpToPx(28)
        val closeParams = FrameLayout.LayoutParams(closeSize, closeSize)
        closeParams.gravity = Gravity.TOP or Gravity.END
        closeParams.topMargin = dpToPx(4)
        closeParams.rightMargin = dpToPx(4)
        close.setOnClickListener {
            // 先通知 Dart 把 wid 切回家, 再由 Dart 调 stopOverlay. 不要先拆 Surface.
            InAppChannel.onOverlayClose?.invoke()
        }
        container.addView(close, closeParams)

        val stage = TextView(this)
        stage.text = "S5 点我展开"
        stage.setTextColor(android.graphics.Color.WHITE)
        stage.textSize = 14f
        stage.setBackgroundColor(android.graphics.Color.argb(160, 0, 80, 160))
        val pad = dpToPx(6)
        stage.setPadding(pad, pad, pad, pad)
        val stageParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
        )
        stageParams.gravity = Gravity.BOTTOM or Gravity.START
        stageParams.leftMargin = dpToPx(8)
        stageParams.bottomMargin = dpToPx(8)
        container.addView(stage, stageParams)

        container.setOnTouchListener(this)
        tv.setOnTouchListener(this)
        rootView = container
        textureView = tv
        wm.addView(container, layoutParams)
        isRunning = true
        Log.i(TAG, "overlay added: ${widthPx}x$heightPx at (${layoutParams.x}, ${layoutParams.y})")
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
        val newHeight = (layoutParams.width * height / width.toFloat()).toInt()
        if (newHeight <= 0 || newHeight == layoutParams.height) {
            return
        }
        layoutParams.height = newHeight
        layoutParams.y = (screenSize.y - newHeight - dpToPx(120)).coerceAtLeast(0)
        try {
            wm.updateViewLayout(view, layoutParams)
        } catch (e: Exception) {
            Log.w(TAG, "resize overlay failed", e)
        }
        OverlaySurfaceHolder.resize(layoutParams.width, newHeight)
        Log.i(TAG, "overlay resized to ${layoutParams.width}x$newHeight for ${width}x$height")
    }

    /** 拖拽: 抬起时贴到最近的左右边缘. */
    override fun onTouch(view: View, event: MotionEvent): Boolean {
        val wm = windowManager ?: return false
        val layoutParams = params ?: return false
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                dragging = false
                dragStartX = event.rawX
                dragStartY = event.rawY
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - dragStartX
                val dy = event.rawY - dragStartY
                if (!dragging && dx * dx + dy * dy < 400f) {
                    return true
                }
                dragging = true
                dragStartX = event.rawX
                dragStartY = event.rawY
                layoutParams.x = (layoutParams.x + dx).toInt()
                layoutParams.y = (layoutParams.y + dy).toInt()
                wm.updateViewLayout(view, layoutParams)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (dragging) {
                    val halfway = (screenSize.x - layoutParams.width) / 2
                    layoutParams.x = if (layoutParams.x < halfway) {
                        dpToPx(8)
                    } else {
                        screenSize.x - layoutParams.width - dpToPx(8)
                    }
                    val maxY = screenSize.y - layoutParams.height - dpToPx(48)
                    layoutParams.y = layoutParams.y.coerceIn(dpToPx(48), maxY.coerceAtLeast(dpToPx(48)))
                    wm.updateViewLayout(view, layoutParams)
                } else if (event.action == MotionEvent.ACTION_UP) {
                    InAppChannel.onOverlayTap?.invoke()
                }
            }
        }
        return true
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
            .setSmallIcon(android.R.drawable.ic_media_play)
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
