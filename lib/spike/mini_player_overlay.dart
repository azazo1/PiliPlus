import 'dart:async';
import 'dart:convert';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 小窗 spike: 悬浮窗 (SYSTEM_ALERT_WINDOW) + 第二个 FlutterEngine 里跑迷你播放器.
///
/// 验证目标:
/// 1. 悬浮窗里能跑起 Flutter 并渲染 media_kit 视频
/// 2. 悬浮窗期间应用自身任务仍是普通任务 (最近任务里有卡片)
///
/// 参考: B 站 MiniPlayerFloatViewManager (WindowManager + TYPE_APPLICATION_OVERLAY)
/// 与 flutter_overlay_window (Service + FlutterEngineGroup 独立入口 + FlutterView).
///
/// todo remove 小窗 spike 验证完成后删除本文件与相关调用
abstract final class MiniPlayerOverlaySpike {
  static const _channel = MethodChannel('com.azazo1.piliplus/spike');

  static Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;

  static Future<void> requestPermission() =>
      _channel.invokeMethod('requestOverlayPermission');

  static Future<void> stop() => _channel.invokeMethod('stopOverlay');

  /// 把当前播放会话的媒体串交给悬浮窗里的第二个播放器.
  static Future<bool> startFromPlayer({
    required PlPlayerController controller,
    required String title,
    required Duration position,
    required bool isLive,
  }) async {
    final url = controller.spikeLastMediaUrl;
    if (url == null) {
      return false;
    }
    final payload = jsonEncode({
      'url': url,
      'extras': controller.spikeLastMediaExtras,
      'positionMs': position.inMilliseconds,
      'title': title,
      'isLive': isLive,
    });
    await _channel.invokeMethod('startOverlay', payload);
    return true;
  }
}

/// 悬浮窗里的入口体: 由 lib/main.dart 的 miniPlayerMain 调用.
/// 自定义入口函数必须位于 root library (main.dart), 所以这里只放实现.
void runMiniPlayerOverlay() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  print('[overlay] entrypoint started');
  runApp(const _MiniPlayerOverlayApp());
}

class _MiniPlayerOverlayApp extends StatelessWidget {
  const _MiniPlayerOverlayApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MiniPlayerOverlayPage(),
    );
  }
}

class MiniPlayerOverlayPage extends StatefulWidget {
  const MiniPlayerOverlayPage({super.key});

  @override
  State<MiniPlayerOverlayPage> createState() => _MiniPlayerOverlayPageState();
}

class _MiniPlayerOverlayPageState extends State<MiniPlayerOverlayPage> {
  static const _channel = MethodChannel('com.azazo1.piliplus/spike');

  Player? _player;
  VideoController? _controller;
  String _status = 'loading payload';
  String _title = '小窗 spike';

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'reload') {
        await _reload();
      }
      return null;
    });
    _boot();
  }

  Future<void> _reload() async {
    // 等首次 boot 结束再重启, 否则两个播放器会同时出声
    await _bootFuture;
    final old = _player;
    _player = null;
    _controller = null;
    if (mounted) {
      setState(() => _status = 'reloading');
    }
    await old?.dispose();
    await _boot();
  }

  /// 第二个 engine 的 isolate 可能比原生侧的 channel handler 更早就绪, 所以这里重试取参数.
  Future<String?> _fetchPayload() async {
    for (var attempt = 0; attempt < 12; attempt++) {
      try {
        final raw = await _channel
            .invokeMethod<String>('getPayload')
            .timeout(const Duration(milliseconds: 500));
        if (raw != null && raw.isNotEmpty) {
          return raw;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<void> _log(Object message) async {
    // release 包里 Dart 的 stdout 会进 logcat 的 I/flutter, 方便排查
    print('[overlay] $message');
    try {
      await _channel.invokeMethod('log', message.toString());
    } catch (_) {}
  }

  /// 正在进行的 boot, reload 需要等它结束, 否则会出现两个播放器 (声音重复)
  Future<void>? _bootFuture;

  Future<void> _boot() {
    final future = _bootInternal();
    _bootFuture = future;
    return future;
  }

  Future<void> _bootInternal() async {
    try {
      final raw = await _fetchPayload();
      await _log('payload: ${raw?.length ?? 0} chars');
      if (raw == null || raw.isEmpty) {
        setState(() => _status = 'no payload');
        return;
      }
      final payload = jsonDecode(raw) as Map;
      _title = (payload['title'] as String?)?.trim() ?? '';
      if (_title.isEmpty) {
        _title = '小窗 spike';
      }
      // 防御: 万一是重建, 先收掉旧播放器
      final stale = _player;
      _player = null;
      _controller = null;
      if (stale != null) {
        await stale.dispose();
      }
      // 和主播放器保持一致: fork 版 media_kit 需要 androidAttachSurfaceAfterVideoParameters: false,
      // 否则小窗里的视频纹理尺寸会对不上 (画面静止 / 只画一角)
      final player = await Player.create(
        configuration: const PlayerConfiguration(
          logLevel: MPVLogLevel.error,
          options: {'ao': 'audiotrack'},
        ),
      );
      final controller = await VideoController.create(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );
      _player = player;
      _controller = controller;
      player.setMediaHeader(userAgent: BrowserUa.pc, referer: HttpString.baseUrl);
      // todo remove 小窗 spike: 渲染诊断
      player.stream.videoParams.listen(
        (p) => _log('videoParams: ${p.w}x${p.h}'),
      );
      player.stream.error.listen((e) => _log('player error: $e'));
      Timer.periodic(const Duration(seconds: 2), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final state = player.state;
        _log(
          'state: pos=${state.position.inSeconds}s playing=${state.playing} '
          'buffering=${state.buffering} ${state.width}x${state.height}',
        );
      });
      if (mounted) {
        setState(() => _status = 'opening');
      }
      await _log('payload title=$_title url=${(payload['url'] as String).length} chars');
      await player.open(
        Media(
          payload['url'] as String,
          start: Duration(
            milliseconds: (payload['positionMs'] as int?) ?? 0,
          ),
          extras: (payload['extras'] as Map?)?.cast<String, String>(),
        ),
      );
      await _log('opened, playing');
      if (mounted) {
        setState(() => _status = '');
      }
    } catch (e) {
      await _log('boot failed: $e');
      if (mounted) {
        setState(() => _status = 'failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          if (controller != null)
            Positioned.fill(
              child: SimpleVideo(controller: controller),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const Icon(Icons.drag_indicator, size: 14, color: Colors.white70),
                  Expanded(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      tooltip: '关闭小窗',
                      onPressed: () => _channel.invokeMethod('close'),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_status.isNotEmpty)
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
