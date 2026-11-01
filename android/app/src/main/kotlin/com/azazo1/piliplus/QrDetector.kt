package com.azazo1.piliplus

import android.content.Context
import android.graphics.BitmapFactory
import android.os.SystemClock
import android.util.Log
import com.king.wechat.qrcode.WeChatQRCodeDetector
import org.opencv.OpenCV

/**
 * 微信开源的二维码引擎 (OpenCV wechat_qrcode), 深色背景和白边很窄的二维码也能识别.
 */
object QrDetector {
    private const val TAG = "QrScan"

    /** 相册图片长边上限, 太大的截图先缩小, 避免占用过多内存. */
    private const val MAX_IMAGE_SIDE = 2048

    @Volatile
    private var ready = false

    /** 加载 OpenCV 与模型, 只做一次; 相机开始分析前必须完成. */
    fun ensureInit(context: Context): Boolean {
        if (ready) return true
        synchronized(this) {
            if (ready) return true
            val start = SystemClock.elapsedRealtime()
            if (!OpenCV.initOpenCV()) {
                Log.e(TAG, "init OpenCV failed")
                return false
            }
            WeChatQRCodeDetector.init(context.applicationContext)
            ready = true
            Log.i(TAG, "detector ready in ${SystemClock.elapsedRealtime() - start} ms")
            return true
        }
    }

    /** 识别图片文件中的二维码, 返回第一个非空结果. */
    fun decodeFile(path: String): String? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sampleSize = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sampleSize > MAX_IMAGE_SIDE) {
            sampleSize *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val bitmap = BitmapFactory.decodeFile(path, options) ?: return null
        return try {
            WeChatQRCodeDetector.detectAndDecode(bitmap).firstOrNull { it.isNotEmpty() }
        } finally {
            bitmap.recycle()
        }
    }
}
