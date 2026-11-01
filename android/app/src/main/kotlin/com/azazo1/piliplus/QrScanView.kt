package com.azazo1.piliplus

import android.content.Context
import android.util.Log
import android.view.View
import androidx.camera.view.PreviewView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.king.camera.scan.BaseCameraScan
import com.king.wechat.qrcode.DecodeResult
import com.king.wechat.qrcode.scanning.analyze.WeChatScanningAnalyzer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class QrScanViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val host = MainActivity.instance
            ?: throw IllegalStateException("MainActivity is not available")
        return QrScanView(
            host,
            MethodChannel(messenger, "${QrScanChannel.CHANNEL}/view_$viewId"),
        )
    }
}

/**
 * 扫一扫的相机预览, 只负责取景和识别, 界面由 Dart 绘制.
 *
 * 自带一个跟随宿主 Activity 的 Lifecycle: 退到后台时相机暂停, 页面关闭时相机释放.
 */
class QrScanView(
    private val host: MainActivity,
    private val channel: MethodChannel,
) : PlatformView, LifecycleOwner {
    private companion object {
        const val TAG = "QrScan"
    }

    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry

    private val hostObserver = LifecycleEventObserver { _, event ->
        if (event != Lifecycle.Event.ON_DESTROY) {
            registry.handleLifecycleEvent(event)
        } else {
            destroyLifecycle()
        }
    }

    private val previewView = PreviewView(host).apply {
        // TextureView 模式才能正常合成进 Flutter 画面.
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
    }

    private val cameraScan = BaseCameraScan<DecodeResult>(host, this, previewView)

    init {
        host.lifecycle.addObserver(hostObserver)
        cameraScan.setAnalyzer(WeChatScanningAnalyzer())
            .setPlayBeep(false)
            .setVibrate(false)
            .setOnScanResultCallback { result ->
                val text = result.result.texts.firstOrNull { it.isNotEmpty() }
                if (text == null) {
                    cameraScan.setAnalyzeImage(true)
                } else {
                    Log.i(TAG, "camera decoded, length=${text.length}")
                    channel.invokeMethod("onDetect", text)
                }
            }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "toggleTorch" -> {
                    if (!cameraScan.hasFlashUnit()) {
                        result.success(null)
                    } else {
                        val torch = !cameraScan.isTorchEnabled
                        cameraScan.enableTorch(torch)
                        result.success(torch)
                    }
                }

                "setAnalyze" -> {
                    cameraScan.setAnalyzeImage(call.arguments as? Boolean ?: true)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
        cameraScan.startCamera()
        Log.i(TAG, "camera view created")
    }

    override fun getView(): View = previewView

    private fun destroyLifecycle() {
        host.lifecycle.removeObserver(hostObserver)
        if (registry.currentState.isAtLeast(Lifecycle.State.CREATED)) {
            registry.currentState = Lifecycle.State.DESTROYED
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        cameraScan.release()
        destroyLifecycle()
        Log.i(TAG, "camera view disposed")
    }
}
