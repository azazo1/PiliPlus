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
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Toast
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * 小窗 spike: 用 SYSTEM_ALERT_WINDOW 悬浮窗 + 第二个 FlutterEngine 渲染迷你播放器.
 *
 * 参考实现:B 站 的 com.bilibili.mini.player.common.view.MiniPlayerFloatViewManager
 * (WindowManager.addView + TYPE_APPLICATION_OVERLAY), 以及 flutter_overlay_window 的 OverlayService
 * (Service + FlutterEngineGroup 的独立入口 + FlutterView(TEXTURE) + 拖拽).
 *
 * 目的: 验证 "悬浮窗里能跑 Flutter 视频 + 应用自身任务仍然是普通任务(最近任务里有卡片)".
 *
 * todo remove 小窗 spike 验证完成后删除本文件与清单里的 service / 权限声明
 */
class MiniPlayerOverlayService : Service(), View.OnTouchListener {
    companion object {
        private const val TAG = "MiniOverlaySpike"
        private const val CHANNEL_ID = "mini_overlay_spike"
        private const val NOTIFY_ID = 0x5152
        private const val ENGINE_TAG = "piliplus_mini_overlay"
        private const val DART_ENTRYPOINT = "miniPlayerMain"
        const val ACTION_STOP = "com.azazo1.piliplus.action.STOP_MINI_OVERLAY"
        const val EXTRA_PAYLOAD = "payload"

        /** Dart 侧控制通道: 主 engine 用于启动/权限 (MainActivity), 第二个 engine 用于取参数/关闭. */
        const val SPIKE_CHANNEL = "com.azazo1.piliplus/spike"

        /** 传给第二个 engine 的播放参数 (json), 由 Dart 侧通过 getPayload 取回. */
        @Volatile
        var payload: String? = null
            private set

        @Volatile
        var isRunning: Boolean = false
            private set

        fun canDrawOverlays(context: Context): Boolean =
            Settings.canDrawOverlays(context)

        fun permissionIntent(context: Context): Intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        )

        fun start(context: Context, payloadJson: String) {
            payload = payloadJson
            val intent = Intent(context, MiniPlayerOverlayService::class.java)
                .putExtra(EXTRA_PAYLOAD, payloadJson)
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
    private var flutterView: FlutterView? = null
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var params: WindowManager.LayoutParams? = null

    private var dragStartX = 0f
    private var dragStartY = 0f
    private var dragging = false
    private val screenSize = Point()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFY_ID, buildNotification())
        engine = obtainEngine()
        channel = MethodChannel(engine!!.dartExecutor.binaryMessenger, SPIKE_CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPayload" -> result.success(payload)
                "close" -> {
                    result.success(true)
                    stopSelf()
                }
                "resize" -> {
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    resizeOverlay(width, height)
                    result.success(true)
                }
                "log" -> {
                    Log.i(TAG, "dart: ${call.arguments}")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        intent?.getStringExtra(EXTRA_PAYLOAD)?.let { payload = it }
        if (!canDrawOverlays(this)) {
            Log.w(TAG, "no overlay permission, abort")
            Toast.makeText(this, "缺少悬浮窗权限", Toast.LENGTH_SHORT).show()
            stopSelf()
            return START_NOT_STICKY
        }
        showOverlay()
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        val view = flutterView
        if (view != null) {
            try {
                view.setOnTouchListener(null)
                windowManager?.removeView(view)
            } catch (e: Exception) {
                Log.w(TAG, "removeView failed", e)
            }
            view.detachFromFlutterEngine()
        }
        flutterView = null
        windowManager = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFY_ID)
        super.onDestroy()
    }

    private fun obtainEngine(): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_TAG)?.let { return it }
        val group = FlutterEngineGroup(applicationContext)
        val entrypoint = DartExecutor.DartEntrypoint(
            FlutterInjector.instance().flutterLoader().findAppBundlePath(),
            DART_ENTRYPOINT,
        )
        val created = group.createAndRunEngine(applicationContext, entrypoint)
        FlutterEngineCache.getInstance().put(ENGINE_TAG, created)
        Log.i(TAG, "created second engine for entrypoint $DART_ENTRYPOINT")
        return created
    }

    private fun showOverlay() {
        if (flutterView != null) {
            return
        }
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealSize(screenSize)

        val widthPx = dpToPx(280)
        val heightPx = (widthPx * 9 / 16f).toInt()
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
        layoutParams.y = dpToPx(96)
        params = layoutParams

        val view = FlutterView(this, FlutterTextureView(this))
        view.attachToFlutterEngine(engine!!)
        view.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        view.setOnTouchListener(this)
        flutterView = view
        wm.addView(view, layoutParams)
        isRunning = true
        Log.i(TAG, "overlay added: ${widthPx}x$heightPx at (${layoutParams.x}, ${layoutParams.y})")
        // engine 会被缓存复用, 重开小窗时让 Dart 侧重新取一次参数
        channel?.invokeMethod("reload", null)
    }

    private fun resizeOverlay(width: Int, height: Int) {
        val wm = windowManager ?: return
        val view = flutterView ?: return
        val layoutParams = params ?: return
        if (width > 0) {
            layoutParams.width = dpToPx(width)
        }
        if (height > 0) {
            layoutParams.height = dpToPx(height)
        }
        wm.updateViewLayout(view, layoutParams)
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
                    return false
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
                }
            }
        }
        return false
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
            .setContentTitle("小窗 spike")
            .setContentText("悬浮窗里正在播放")
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
                    "小窗 spike",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
    }
}
