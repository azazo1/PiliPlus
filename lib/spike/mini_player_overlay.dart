import 'dart:async';

import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
// ignore: implementation_imports
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';

/// 小窗 spike: 把**同一个**播放器的画面输出在"主页面"与"系统悬浮窗"之间切换.
///
/// 参考 B 站 com.bilibili.mini.player.common.view.MiniPlayerFloatViewManager:
/// 它把承载播放器的 View 在 activity window 与 system window 之间搬来搬去,
/// 播放器实例全程不重建, 因此小窗是无缝的 (不重新拉流, 不重新缓冲).
///
/// Flutter 的画面纹理搬不了, 所以改 mpv 的输出目标 (wid).
/// S5: 退出播放页自动开小窗, 点小窗展开回播放页.
///
/// todo remove 小窗 spike 验证完成后删除本文件
abstract final class MiniPlayerOverlaySpike {
  static const _channel = MethodChannel('com.azazo1.piliplus/spike');

  static Player? _player;
  static String? _homeWid;
  static String? _overlayWid;
  static int _overlayW = 0;
  static int _overlayH = 0;
  static StreamSubscription<VideoParams>? _guard;
  static bool _session = false;
  static bool _closing = false;
  static bool _expanding = false;
  static _ResumeArgs? _resume;
  static Completer<void>? _foreground;

  /// 小窗 session 期间: 播放页不要进系统 PiP, 也不要因为 overlay 把 Activity pause 就停播放器.
  static bool get isActive => _session;

  /// 点小窗展开的是同一支视频, 才把正在播的播放器接回页面.
  static bool isSameVideo({required int aid, required int cid}) {
    final args = _resume;
    if (args == null) {
      return false;
    }
    return args.aid == aid && args.cid == cid;
  }

  /// 悬浮窗 Surface 就绪时回调 (wid, width, height).
  static void Function(String wid, int width, int height)? onSurfaceReady;

  /// 悬浮窗 Surface 消失 (小窗关闭) 时回调, 此时应把输出切回主页面.
  static void Function()? onSurfaceLost;

  /// 用户点了小窗 X: 停播并释放播放器, 不再后台继续播.
  static void Function()? onUserClosed;

  static Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;

  static Future<void> requestPermission() =>
      _channel.invokeMethod('requestOverlayPermission');

  static Future<void> stop() => _channel.invokeMethod('stopOverlay');

  /// 必须在跳转悬浮窗权限页之前调用, 否则 Settings 会把播放页收进系统 PiP.
  static void beginSession() {
    if (_session) {
      return;
    }
    _session = true;
    PiliAndroidHelper.disableAutoEnterPip();
    _log('begin overlay session');
  }

  /// 先把画面切回主页面, 再拆悬浮窗. 避免 mpv 对着已销毁的 Surface 画.
  static Future<void> closeAndRestore() async {
    if (_closing) {
      return;
    }
    _closing = true;
    await switchToHome();
    // 等 mpv 放下 overlay Surface 再拆窗, 避免切回主页面黑屏.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      await stop();
    } catch (_) {}
    endSession();
  }

  /// 点小窗 X: 拆悬浮窗并释放播放器, 不要切回主页面纹理继续播.
  static Future<void> closeAndRelease() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _log('close overlay and release player');
    _stopGuard();
    onSurfaceLost = null;
    onSurfaceReady = null;
    final player = _player;
    try {
      player?.setOption('vo', 'null');
      player?.setOption('wid', '0');
    } catch (_) {}
    try {
      await player?.pause();
    } catch (_) {}
    try {
      await stop();
    } catch (_) {}
    final release = onUserClosed;
    onUserClosed = null;
    endSession();
    release?.call();
  }

  /// 点了另一支视频: 拆小窗但留下播放器, 让新页面 setDataSource.
  static Future<void> dismissForNewVideo() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _log('dismiss overlay for another video');
    _stopGuard();
    onSurfaceLost = null;
    onSurfaceReady = null;
    onUserClosed = null;
    final player = _player;
    final controller = player == null ? null : AndroidVideoController.of(player);
    if (controller != null) {
      await controller.detachOverlayWid();
    } else if (player != null) {
      try {
        player.setOption('vo', 'null');
        player.setOption('wid', '0');
      } catch (_) {}
    }
    try {
      await stop();
    } catch (_) {}
    endSession();
  }

  /// 关小窗后清状态. 不负责把 wid 切回家, 那是 [switchToHome] 的事.
  static void endSession() {
    _stopGuard();
    _player = null;
    _homeWid = null;
    _overlayW = 0;
    _overlayH = 0;
    onSurfaceReady = null;
    onSurfaceLost = null;
    onUserClosed = null;
    final keepResume = _expanding;
    _closing = false;
    _expanding = false;
    if (!keepResume) {
      _resume = null;
    }
    if (_session) {
      _session = false;
      _log('end overlay session');
    }
  }

  static void logSurfaceReady(String wid, int width, int height) {
    _log('S3 surface ready wid=$wid ${width}x$height');
  }

  /// 退出播放页时调用: 有悬浮窗权限就把同一 Player 切到小窗.
  static Future<bool> enterFromLeavingVideo({
    required Player? player,
    required int aid,
    required String bvid,
    required int cid,
    required VideoType videoType,
    int? seasonId,
    int? epId,
    int? pgcType,
    String? cover,
    String? title,
    void Function()? onUserClosed,
  }) async {
    if (player == null || cid <= 0) {
      return false;
    }
    if (isActive) {
      return true;
    }
    beginSession();
    if (!await hasPermission()) {
      endSession();
      _log('S5 skip auto overlay: no permission');
      return false;
    }
    MiniPlayerOverlaySpike.onUserClosed = onUserClosed;
    _resume = _ResumeArgs(
      aid: aid,
      bvid: bvid,
      cid: cid,
      videoType: videoType,
      seasonId: seasonId,
      epId: epId,
      pgcType: pgcType,
      cover: cover,
      title: title,
    );
    onSurfaceLost = closeAndRestore;
    onSurfaceReady = (wid, width, height) {
      logSurfaceReady(wid, width, height);
      switchToOverlay(
        player,
        wid,
        width: player.state.width,
        height: player.state.height,
      );
    };
    // 不要在这里等 Surface, 返回键必须立刻把播放页弹掉.
    start(
      player: player,
      width: player.state.width,
      height: player.state.height,
    );
    return true;
  }

  /// 点小窗展开回播放页. 先把 Activity 拉回前台, 播放页就绪后再 [closeAndRestore].
  static Future<void> expand() async {
    _log('expand overlay, resume=${_resume != null}');
    await _bringToFront();
    final args = _resume;
    if (args == null) {
      await closeAndRestore();
      return;
    }
    _expanding = true;
    PageUtils.toVideoPage(
      videoType: args.videoType,
      aid: args.aid,
      bvid: args.bvid,
      cid: args.cid,
      seasonId: args.seasonId,
      epId: args.epId,
      pgcType: args.pgcType,
      cover: args.cover,
      title: args.title,
    );
  }

  /// 启动悬浮窗. S3 传入 [player] 和视频像素尺寸, Surface 就绪后切 wid.
  static Future<void> start({
    Player? player,
    int width = 0,
    int height = 0,
  }) async {
    _installHandler();
    beginSession();
    if (player != null) {
      _player = player;
      _homeWid = _readWid(player);
      if (_homeWid == null) {
        _homeWid = await _readHomeWidNative();
      }
    }
    _log(
      'start overlay, home wid=${_homeWid ?? "unused"} video=${width}x$height',
    );
    await _channel.invokeMethod('startOverlay', {
      'width': width,
      'height': height,
    });
  }

  /// 把画面输出切到悬浮窗的 Surface, 并守住 wid 不被 media_kit 抢回.
  static Future<void> switchToOverlay(
    Player player,
    String wid, {
    int width = 0,
    int height = 0,
  }) async {
    _player = player;
    _homeWid ??= _readWid(player);
    _overlayWid = wid;
    _overlayW = width;
    _overlayH = height;
    final parsed = int.tryParse(wid);
    if (parsed != null) {
      AndroidVideoController.of(player)?.attachOverlayWid(parsed);
    }
    _bind(player, wid, width, height, recreateVo: true);
    _log(
      'switch output to overlay wid=$wid ${width}x$height (home=${_homeWid ?? "unknown"})',
    );
  }

  /// 把画面输出切回主页面纹理.
  static Future<void> switchToHome([Player? player]) async {
    _stopGuard();
    final target = player ?? _player;
    if (target == null) {
      _log('switchToHome skipped: no player');
      return;
    }
    final controller = AndroidVideoController.of(target);
    if (controller != null) {
      await controller.detachOverlayWid();
      _log('switch output back to flutter surface via detachOverlayWid');
      return;
    }
    final home = _homeWid;
    if (home == null || home == '0' || home.isEmpty) {
      _log('switchToHome failed: home wid unknown');
      return;
    }
    _bind(target, home, target.state.width, target.state.height, recreateVo: true);
    _log('switch output back to home wid=$home');
  }

  static Future<void> applyVideoSize(int width, int height) async {
    if (width <= 0 || height <= 0) {
      return;
    }
    try {
      await _channel.invokeMethod('applyVideoSize', {
        'width': width,
        'height': height,
      });
    } catch (_) {}
  }

  static void _bind(
    Player player,
    String wid,
    int width,
    int height, {
    bool recreateVo = false,
  }) {
    final w = width > 0 ? width : 1;
    final h = height > 0 ? height : 1;
    final size = '${w}x$h';
    // 只用 setOption, 对齐 media_kit. 第一次切 Surface 才拆 vo.
    if (recreateVo) {
      player.setOption('vo', 'null');
      player.setOption('wid', '0');
    }
    player.setOption('android-surface-size', size);
    player.setOption('wid', wid);
    if (recreateVo) {
      player.setOption('vo', 'gpu');
    }
  }

  static String? _readWid(Player player) {
    try {
      final value = player.getProperty('wid');
      if (value.isEmpty || value == '0') {
        return null;
      }
      return value;
    } catch (e) {
      _log('getProperty(wid) failed: $e');
      return null;
    }
  }

  static Future<String?> _readHomeWidNative() async {
    try {
      final value = await _channel.invokeMethod<String>('readHomeWid', {
        'handle': '0',
      });
      if (value == null || value.isEmpty || value == '0') {
        return null;
      }
      return value;
    } catch (e) {
      _log('readHomeWid failed: $e');
      return null;
    }
  }

  static void _startGuard(Player player) {
    _guard?.cancel();
    _guard = player.stream.videoParams.listen((_) async {
      final wid = _overlayWid;
      if (wid == null) {
        return;
      }
      // media_kit 的 listener 是 async 的, 等它把 wid 抢回去再抢回来
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_overlayWid != wid) {
        return;
      }
      _bind(player, wid, _overlayW, _overlayH);
      _log('reclaim overlay wid=$wid after videoParams');
    });
  }

  static void _stopGuard() {
    _guard?.cancel();
    _guard = null;
    _overlayWid = null;
  }

  static void _installHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSurfaceReady':
          final args = call.arguments;
          if (args is Map) {
            final wid = args['wid']?.toString();
            final width = (args['width'] as num?)?.toInt() ?? 0;
            final height = (args['height'] as num?)?.toInt() ?? 0;
            if (wid != null) {
              onSurfaceReady?.call(wid, width, height);
            }
          } else if (args is String) {
            onSurfaceReady?.call(args, 0, 0);
          }
        case 'onSurfaceLost':
          onSurfaceLost?.call();
        case 'onOverlayClose':
          if (_resume != null) {
            await closeAndRelease();
          } else {
            await closeAndRestore();
          }
        case 'onOverlayTap':
          await expand();
        case 'onActivityResumed':
          final wait = _foreground;
          if (wait != null && !wait.isCompleted) {
            wait.complete();
          }
      }
      return null;
    });
  }

  static Future<void> _bringToFront() async {
    _foreground = Completer<void>();
    try {
      final already = await _channel.invokeMethod<bool>('bringToFront') ?? false;
      if (already) {
        return;
      }
      await _foreground!.future.timeout(const Duration(milliseconds: 800));
    } catch (e) {
      _log('bringToFront wait: $e');
    }
  }

  static void _log(Object message) {
    print('[miniwin] $message');
    try {
      _channel.invokeMethod('log', message.toString());
    } catch (_) {}
  }
}

class _ResumeArgs {
  const _ResumeArgs({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.videoType,
    this.seasonId,
    this.epId,
    this.pgcType,
    this.cover,
    this.title,
  });

  final int aid;
  final String bvid;
  final int cid;
  final VideoType videoType;
  final int? seasonId;
  final int? epId;
  final int? pgcType;
  final String? cover;
  final String? title;
}
