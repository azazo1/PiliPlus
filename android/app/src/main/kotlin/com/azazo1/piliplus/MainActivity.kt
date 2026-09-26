package com.azazo1.piliplus

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    // todo remove 小窗 spike 的控制通道
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MiniPlayerOverlayService.SPIKE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" ->
                    result.success(MiniPlayerOverlayService.canDrawOverlays(this))
                "requestOverlayPermission" -> {
                    startActivity(MiniPlayerOverlayService.permissionIntent(this))
                    result.success(true)
                }
                "startOverlay" -> {
                    MiniPlayerOverlayService.start(this, call.arguments as String)
                    result.success(true)
                }
                "stopOverlay" -> {
                    MiniPlayerOverlayService.stop(this)
                    result.success(true)
                }
                "isOverlayRunning" ->
                    result.success(MiniPlayerOverlayService.isRunning)
                else -> result.notImplemented()
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onDestroy() {
        stopService(Intent(this, com.ryanheise.audioservice.AudioService::class.java))
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
    }
}
