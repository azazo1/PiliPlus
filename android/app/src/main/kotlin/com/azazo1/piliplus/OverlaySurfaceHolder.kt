package com.azazo1.piliplus

import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import java.lang.reflect.Field
import java.lang.reflect.Method

/**
 * 小窗 spike: media_kit 的 Surface 桥接.
 *
 * media_kit 的画面输出目标是一个 "wid" -- 指向 android.view.Surface 的 JNI 全局引用地址,
 * 由 media_kit_libs_android_video 的 com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper
 * 维护 (见 media_kit_video 的 VideoOutput.createSurface / newGlobalObjectRef).
 *
 * 这里做两件事:
 * 1. 给悬浮窗造一个 Surface 并注册成 wid, 让 libmpv 可以把画面输出到悬浮窗;
 * 2. 读出 media_kit 为主页面纹理保存的 wid, 供切回时恢复.
 *
 * 于是播放器/解码器/播放位置全程不重启, 小窗与主页面共用一个播放器.
 *
 * todo remove 小窗 spike 验证完成后删除本文件
 */
object OverlaySurfaceHolder {
    private const val TAG = "MiniOverlaySpike"

    private const val HELPER_CLASS =
        "com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper"

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

    /**
     * media_kit_video 的内部结构, 用于读回主页面纹理的 wid:
     * MediaKitVideoPlugin.videoOutputManager (private) -> VideoOutputManager.videoOutputs
     * (private HashMap<Long, VideoOutput>) -> VideoOutput.wid (public long).
     */
    private val videoOutputsField: Field? = try {
        val managerClass = Class.forName("com.alexmercerind.media_kit_video.VideoOutputManager")
        managerClass.getDeclaredField("videoOutputs").apply { isAccessible = true }
    } catch (e: Throwable) {
        Log.e(TAG, "videoOutputs field unavailable", e)
        null
    }

    private var surfaceTexture: SurfaceTexture? = null
    private var surface: Surface? = null
    private var wid: Long = 0L

    val isAvailable: Boolean
        get() = newGlobalObjectRef != null

    @Synchronized
    fun currentWid(): Long = wid

    /**
     * 读取 media_kit 为指定 player 保存的主页面纹理 wid.
     * 拿不到时返回 0.
     */
    fun readHomeWid(playerHandle: Long): Long {
        val field = videoOutputsField ?: return 0L
        return try {
            val pluginClass = Class.forName("com.alexmercerind.media_kit_video.MediaKitVideoPlugin")
            val managerField = pluginClass.getDeclaredField("videoOutputManager").apply {
                isAccessible = true
            }
            val manager = managerField.get(null) ?: return 0L
            val outputs = field.get(manager) as? Map<*, *> ?: return 0L
            // 正常情况下按 player handle 取; 取不到时退回唯一项 (spike 场景下只有一个播放器)
            val output = outputs[playerHandle]
                ?: outputs.values.firstOrNull()
                ?: return 0L
            val widField = output.javaClass.getField("wid")
            (widField.get(output) as? Long) ?: 0L
        } catch (e: Throwable) {
            Log.w(TAG, "readHomeWid failed for handle=$playerHandle", e)
            0L
        }
    }

    /**
     * 用 TextureView 自己的 SurfaceTexture 建立 Surface, 返回它的 wid.
     *
     * SurfaceTexture 由 TextureView 持有, 这里只借用, 绝不 release 它,
     * 否则 TextureView 会失效.
     */
    @Synchronized
    fun obtain(surfaceTexture: SurfaceTexture, width: Int, height: Int): Long {
        if (wid == 0L) {
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
        } else {
            surfaceTexture.setDefaultBufferSize(width.coerceAtLeast(1), height.coerceAtLeast(1))
        }
        return wid
    }

    @Synchronized
    fun resize(width: Int, height: Int) {
        surfaceTexture?.setDefaultBufferSize(
            width.coerceAtLeast(1),
            height.coerceAtLeast(1),
        )
    }

    /**
     * 释放 Surface 与全局引用. 延迟删除全局引用, 给 libmpv 时间放下引用
     * (与 media_kit 的做法一致). 不释放 SurfaceTexture, 它属于 TextureView.
     */
    @Synchronized
    fun release() {
        val ref = wid
        wid = 0L
        try {
            surface?.release()
        } catch (e: Throwable) {
            Log.w(TAG, "release surface failed", e)
        }
        surface = null
        surfaceTexture = null
        if (ref != 0L) {
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    deleteGlobalObjectRef?.invoke(null, ref)
                    Log.i(TAG, "overlay surface released: wid=$ref")
                } catch (e: Throwable) {
                    Log.w(TAG, "deleteGlobalObjectRef failed", e)
                }
            }, 2000)
        }
    }
}
