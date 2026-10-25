# 小窗切换与 mpv 缓存

这份文档记录 android 小窗相关的一处跨仓库改动: mpv 补丁, libmpv 构建产物, media_kit 依赖, 以及 PiliPlus 里的切换逻辑.

目标是进出小窗时音频不中断, demux 缓存不清零, 播放进度不回退.

## 涉及的仓库

| 仓库 | 作用 | 关键 ref |
| --- | --- | --- |
| PiliPlus | 应用侧切换逻辑 | `pubspec.yaml` 固定 media_kit commit |
| media_kit | 按 libmpv 发布的清单校验 jar | 分支 `vnext` |
| libmpv-android-video-build | 打补丁并构建 jar, 自动发布 | 分支 `mpv-vnext`, tag `vnext` |
| mpv (上游) | 补丁作用的源码 | v0.41.0 |

## mpv 补丁

文件: `buildscripts/patches/mpv/vo-switch-keep-cache.patch`, 位于 libmpv-android-video-build 仓库.

两处改动:

1. `player/command.c` 的 `UPDATE_VO`: 把 `queue_seek(MPSEEK_EXACT)` 换成 `reselect_demux_stream(..., true)`. 原来的整体 seek 会 flush 音频输出, 表现为切换时音频卡一下.
2. `demux/demux.c` 的 `refresh_track`: 视频轨优先回退到缓存里的关键帧, 不再调用 `initiate_refresh_seek`. 后者会 `clear_queue` 丢掉整个 demux 缓存.

回退位置要同时满足两个条件:

- 落在 `ref_pts` 之前. 调用方已经清空 `reader_head`, 没有别的位置参照; 不加上限会落到缓存末尾, 表现为进度跳到缓存位置
- 取队列里最近的关键帧, 让重建后的视频链能立刻开始解码

进度不回退依赖 mpv 已有逻辑: 视频链重建后 `video_status == STATUS_SYNCING`, `video_output_image` 会用 `playback_pts` (此时来自音频) 跳过所有更早的帧.

## libmpv 构建与发布

推送 `mpv-vnext` 分支即触发构建. workflow 会:

- 缓存 `buildscripts/deps` 与 `buildscripts/prefix`, 缓存键包含依赖版本和补丁内容
- 构建, 计算 md5, 把 jar 与 `md5.txt` 上传到固定 tag `vnext`

`vnext` 的资产会被覆盖, 同一个 commit 在不同时间构建出的 jar 可能不同. 需要精确回溯时看 libmpv 仓库的 workflow run 与 `mpv-vnext` 的提交记录.

## media_kit

`libs/android/media_kit_libs_android_video/android/build.gradle` 在构建时下载 `vnext` 的 `md5.txt`, 按清单校验 jar. libmpv 更新 jar 后不需要改 media_kit.

## PiliPlus

- `pubspec.yaml` 里的 media_kit 依赖固定 commit
- `lib/plugin/pl_player/overlay_surface_switcher.dart` 负责切换: 只改 wid, 不关视频轨. 关视频轨会让未选中的流丢掉队列, 恢复时只能退回整体 seek, 缓存会清零
- 熄屏判断分布在 `view.dart` 与 `InAppChannel.kt`
- 拉流失败的占位处理在 `lib/pages/video/controller.dart`

## 更新流程

1. 改 `buildscripts/patches/mpv/` 下的补丁
2. 推 `mpv-vnext`
3. 等 CI 发布 `vnext` 与新的 `md5.txt`
4. 重建 PiliPlus

## 验证

真机日志看 `MiniOverlay` 前缀:

- `output switched` 前后 `demuxer-cache-duration` 不应归零或大幅下降
- `avsync` 不应出现几十秒以上的负值
- 切换前后 `audio-pts` 应连续前进

## 已知限制

- 缓存里没有可用关键帧时, 视频要等下一个关键帧, 会有短暂画面等待, 音频与缓存不受影响
- 回退范围受 `demuxer-max-back-bytes` 限制
- 固定 tag 会被覆盖, 构建产物不可字节级复现
