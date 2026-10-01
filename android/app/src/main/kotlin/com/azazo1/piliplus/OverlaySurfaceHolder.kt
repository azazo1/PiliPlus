package com.azazo1.piliplus

import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import java.lang.reflect.Method

/**
 * media_kit 的 Surface 桥接.
 *
 * media_kit 的画面输出目标是一个 "wid" -- 指向 android.view.Surface 的 JNI 全局引用地址,
 * 由 media_kit_libs_android_video 的 com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper
 * 维护 (见 media_kit_video 的 VideoOutput.createSurface / newGlobalObjectRef).
 *
 * 这里给悬浮窗造一个 Surface 并注册成 wid, 让 libmpv 可以把画面输出到悬浮窗.
 * 于是播放器/解码器/播放位置全程不重启, 小窗与主页面共用一个播放器.
 *
 * 释放规则: Surface, SurfaceTexture 与全局引用一起由 [retire] 延迟释放.
 * 调用 [retire] 时 mpv 已经被 Dart 切走, 或者播放器正在销毁; 延迟要覆盖
 * media_kit dispose 里 mpv_terminate_destroy 的 5s, 避免 mpv 拿已删除的引用重建 vo.
 */
object OverlaySurfaceHolder {
    private const val TAG = "MiniOverlay"

    private const val HELPER_CLASS =
        "com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper"

    private const val RELEASE_DELAY_MS = 6000L

    /** newGlobalObjectRef(Object) -> long */
    private val newGlobalObjectRef: Method? = try {
        Class.forName(HELPER_CLASS)
            .getDeclaredMethod("newGlobalObjectRef", Object::class.java)
            .apply { isAccessible = true }
    } catch (e: Throwable) {
        Log.e(TAG, "newGlobalObjectRef unavailable", e)
        null
    }

    /** deleteGlobalObjectRef(long) */
    private val deleteGlobalObjectRef: Method? = try {
        Class.forName(HELPER_CLASS)
            .getDeclaredMethod("deleteGlobalObjectRef", Long::class.javaPrimitiveType)
            .apply { isAccessible = true }
    } catch (e: Throwable) {
        Log.e(TAG, "deleteGlobalObjectRef unavailable", e)
        null
    }

    private val handler = Handler(Looper.getMainLooper())

    private var surfaceTexture: SurfaceTexture? = null
    private var surface: Surface? = null
    private var wid: Long = 0L

    val isAvailable: Boolean
        get() = newGlobalObjectRef != null

    /**
     * 用 TextureView 的 SurfaceTexture 建立 Surface, 返回它的 wid.
     *
     * TextureView 的 onSurfaceTextureDestroyed 返回 false, SurfaceTexture 交给这里管理,
     * 由 [retire] 统一释放.
     */
    @Synchronized
    fun obtain(surfaceTexture: SurfaceTexture, width: Int, height: Int): Long {
        if (this.surfaceTexture === surfaceTexture && wid != 0L) {
            return wid
        }
        // 正常流程里拆窗前一定 retire 过, 这里只是兜底.
        retire()
        surfaceTexture.setDefaultBufferSize(width.coerceAtLeast(1), height.coerceAtLeast(1))
        val newSurface = Surface(surfaceTexture)
        val ref = newGlobalObjectRef?.invoke(null, newSurface) as? Long ?: 0L
        if (ref == 0L) {
            Log.e(TAG, "newGlobalObjectRef returned 0")
            newSurface.release()
            return 0L
        }
        this.surfaceTexture = surfaceTexture
        surface = newSurface
        wid = ref
        Log.i(TAG, "overlay surface created: ${width}x$height wid=$wid")
        return wid
    }

    @Synchronized
    fun resize(width: Int, height: Int) {
        surfaceTexture?.setDefaultBufferSize(
            width.coerceAtLeast(1),
            height.coerceAtLeast(1),
        )
    }

    /** 交出当前 Surface, 延迟释放. 不会影响之后新 obtain 的 Surface. */
    @Synchronized
    fun retire() {
        val ref = wid
        val oldSurface = surface
        val oldTexture = surfaceTexture
        wid = 0L
        surface = null
        surfaceTexture = null
        if (ref == 0L && oldSurface == null && oldTexture == null) {
            return
        }
        handler.postDelayed({
            try {
                oldSurface?.release()
            } catch (e: Throwable) {
                Log.w(TAG, "release overlay surface failed", e)
            }
            try {
                oldTexture?.release()
            } catch (e: Throwable) {
                Log.w(TAG, "release overlay surfaceTexture failed", e)
            }
            if (ref != 0L) {
                try {
                    deleteGlobalObjectRef?.invoke(null, ref)
                } catch (e: Throwable) {
                    Log.w(TAG, "deleteGlobalObjectRef failed", e)
                }
            }
            Log.i(TAG, "overlay surface released: wid=$ref")
        }, RELEASE_DELAY_MS)
    }
}
