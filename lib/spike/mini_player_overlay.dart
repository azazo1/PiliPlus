import 'dart:async';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

/// 小窗 spike: 把**同一个**播放器的画面输出在"主页面"与"系统悬浮窗"之间切换.
///
/// 参考 B 站 com.bilibili.mini.player.common.view.MiniPlayerFloatViewManager:
/// 它把承载播放器的 View 在 activity window 与 system window 之间搬来搬去,
/// 播放器实例全程不重建, 因此小窗是无缝的 (不重新拉流, 不重新缓冲).
///
/// Flutter 的画面纹理绑死在引擎与窗口上, 搬不了, 所以这里用等价做法:
/// 悬浮窗提供一个 android.view.Surface, 把它注册成 media_kit 的 `wid`,
/// 让 libmpv 把画面重新输出到那个 Surface. 解码器, 播放位置, 音频全部保持原样.
///
/// todo remove 小窗 spike 验证完成后删除本文件
abstract final class MiniPlayerOverlaySpike {
  static const _channel = MethodChannel('com.azazo1.piliplus/spike');

  /// 当前被小窗接管的播放器.
  static Player? _player;

  /// 主页面纹理的 wid, 切回时恢复用.
  static String? _homeWid;

  /// 悬浮窗 Surface 就绪时回调 wid.
  static void Function(String wid)? onSurfaceReady;

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
    // 先把主页面当前的 wid 记下来, 否则切回来时没目标可指
    _homeWid = await _readHomeWid(player);
    _log('start overlay, home wid=${_homeWid ?? "unknown"}');
    await _channel.invokeMethod('startOverlay');
  }

  /// 把画面输出切到悬浮窗的 Surface.
  static Future<void> switchToOverlay(Player player, String wid) async {
    _player = player;
    _homeWid ??= await _readHomeWid(player);
    // 先断开与主页面纹理的关联, 再挂到悬浮窗 Surface, 避免两边同时持有
    player.setOption('vo', 'null');
    player.setOption('wid', wid);
    player.setOption('vo', 'gpu');
    _log('switch output to overlay wid=$wid (home=${_homeWid ?? "unknown"})');
  }

  /// 把画面输出切回主页面纹理.
  static Future<void> switchToHome([Player? player]) async {
    final target = player ?? _player;
    if (target == null) {
      _log('switchToHome skipped: no player');
      return;
    }
    var home = _homeWid;
    if (home == null || home == '0') {
      home = await _readHomeWid(target);
    }
    if (home == null || home == '0') {
      _log('switchToHome failed: home wid unknown');
      return;
    }
    target.setOption('vo', 'null');
    target.setOption('wid', home);
    target.setOption('vo', 'gpu');
    _log('switch output back to home wid=$home');
  }

  /// 通知原生按视频尺寸调整小窗高度, 避免画面被拉伸.
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

  /// 向原生索取 media_kit 为主页面纹理保存的 wid.
  static Future<String?> _readHomeWid(Player player) async {
    try {
      final wid = await _channel.invokeMethod<String>('readHomeWid', {
        'handle': player.handle.toString(),
      });
      return wid;
    } catch (_) {
      return null;
    }
  }

  static void _installHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSurfaceReady':
          final wid = call.arguments as String?;
          if (wid != null) {
            onSurfaceReady?.call(wid);
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
