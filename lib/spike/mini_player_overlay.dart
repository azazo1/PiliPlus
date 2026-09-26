import 'dart:async';

import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

/// 小窗 spike: 把**同一个**播放器的画面输出在"主页面"与"系统悬浮窗"之间切换.
///
/// 参考 B 站 com.bilibili.mini.player.common.view.MiniPlayerFloatViewManager:
/// 它把承载播放器的 View 在 activity window 与 system window 之间搬来搬去,
/// 播放器实例全程不重建, 因此小窗是无缝的 (不重新拉流, 不重新缓冲).
///
/// Flutter 的画面纹理搬不了, 所以这里改 mpv 的输出目标 (wid).
/// media_kit 的 videoParams 回调会把 wid 抢回主页面纹理, 小窗期间必须再抢回来.
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

  /// 小窗正在接管画面. 播放页不要进系统 PiP, 也不要 dispose 播放器.
  static bool get isActive => _overlayWid != null || _player != null;

  /// 悬浮窗 Surface 就绪时回调 (wid, width, height).
  static void Function(String wid, int width, int height)? onSurfaceReady;

  /// 悬浮窗 Surface 消失 (小窗关闭) 时回调, 此时应把输出切回主页面.
  static void Function()? onSurfaceLost;

  static Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;

  static Future<void> requestPermission() =>
      _channel.invokeMethod('requestOverlayPermission');

  static Future<void> stop() => _channel.invokeMethod('stopOverlay');

  /// 启动悬浮窗. Surface 就绪后会通过 [onSurfaceReady] 回传 wid.
  static Future<void> start(Player player) async {
    _installHandler();
    _player = player;
    _homeWid = _readWid(player);
    // 小窗期间禁止系统自动 PiP, 否则播放页会被收进 pinned 窗口
    PiliAndroidHelper.disableAutoEnterPip();
    _log('start overlay, home wid=${_homeWid ?? "unknown"}');
    await _channel.invokeMethod('startOverlay');
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
    _bind(player, wid, width, height);
    _startGuard(player);
    _log('switch output to overlay wid=$wid ${width}x$height (home=${_homeWid ?? "unknown"})');
    for (final delay in const [80, 200, 500]) {
      Future<void>.delayed(Duration(milliseconds: delay), () {
        if (_overlayWid != wid) {
          return;
        }
        _bind(player, wid, width, height);
        _log('reclaim overlay wid=$wid after ${delay}ms');
      });
    }
  }

  /// 把画面输出切回主页面纹理.
  static Future<void> switchToHome([Player? player]) async {
    _stopGuard();
    final target = player ?? _player;
    if (target == null) {
      _log('switchToHome skipped: no player');
      return;
    }
    final home = _homeWid;
    if (home == null || home == '0' || home.isEmpty) {
      _log('switchToHome failed: home wid unknown');
      return;
    }
    _bind(target, home, target.state.width, target.state.height);
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

  static void _bind(Player player, String wid, int width, int height) {
    final w = width > 0 ? width : 1;
    final h = height > 0 ? height : 1;
    final size = '${w}x$h';
    // media_kit 自己的顺序: vo=null -> android-surface-size -> wid -> vo=gpu
    // option 与 property 都写一遍, 运行时改 wid 两者都不保证, 但 media_kit 自己就是这么干的
    player.setOption('vo', 'null');
    player.setProperty('vo', 'null');
    player.setOption('android-surface-size', size);
    player.setProperty('android-surface-size', size);
    player.setOption('wid', wid);
    player.setProperty('wid', wid);
    player.setOption('vo', 'gpu');
    player.setProperty('vo', 'gpu');
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
        case 'onOverlayClose':
          onSurfaceLost?.call();
      }
      return null;
    });
  }

  static void _log(Object message) {
    print('[miniwin] $message');
    try {
      _channel.invokeMethod('log', message.toString());
    } catch (_) {}
  }
}
