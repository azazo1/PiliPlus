package com.azazo1.piliplus

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * 扫一扫的原生能力: 加载微信二维码引擎, 识别相册图片, 注册相机预览 PlatformView.
 */
object QrScanChannel {
    private const val TAG = "QrScan"
    const val CHANNEL = "com.azazo1.piliplus/qr_scan"

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        engine.platformViewsController.registry
            .registerViewFactory("$CHANNEL/view", QrScanViewFactory(messenger))
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // 模型加载较慢, 放到后台线程, 避免卡住界面.
                "init" -> executor.execute {
                    val context = MainActivity.instance
                    val ready = try {
                        context != null && QrDetector.ensureInit(context)
                    } catch (e: Throwable) {
                        Log.e(TAG, "init detector failed", e)
                        false
                    }
                    mainHandler.post { result.success(ready) }
                }

                "decodeImage" -> {
                    val path = call.arguments as? String
                    if (path == null) {
                        result.error("BAD_ARGS", "path is required", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        val start = SystemClock.elapsedRealtime()
                        try {
                            val context = MainActivity.instance
                                ?: throw IllegalStateException("MainActivity is not available")
                            check(QrDetector.ensureInit(context)) { "detector is not ready" }
                            val text = QrDetector.decodeFile(path)
                            Log.i(
                                TAG,
                                "album decoded=${text != null} in ${SystemClock.elapsedRealtime() - start} ms"
                            )
                            mainHandler.post { result.success(text) }
                        } catch (e: Throwable) {
                            Log.w(TAG, "decode album image failed", e)
                            mainHandler.post { result.error("DECODE_FAILED", e.message, null) }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
