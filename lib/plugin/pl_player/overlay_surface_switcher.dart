import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synchronized/synchronized.dart';

/// 小窗切换只重建视频轨, 音频继续运行, 画面追上音频后恢复同步设置.
/// 调用方与延迟校准共用同一个锁, 避免快速进出小窗时交错修改属性.
final class OverlaySurfaceSwitcher {
  OverlaySurfaceSwitcher(this.player, this.lock, this.isUsable);

  final Player player;
  final Lock lock;
  final bool Function() isUsable;
  final Map<String, String> _savedOptions = {};
  static const _temporaryOptions = {
    'cache-pause': 'no',
    'video-sync': 'audio',
    'framedrop': 'vo',
  };
  Timer? _calibration;
  int _generation = 0;
  int _checks = 0;
  int _stableChecks = 0;
  String? _path;
  double? _lastAudioPts;

  // todo remove: 真机切换诊断, 不记录媒体地址或用户数据.
  final Stopwatch _diagnosticClock = Stopwatch();
  String _target = '';
  bool? _lastPausedForCache;

  /// 在 lock 内调用. 不暂停, 不 seek, 不重选音轨.
  ///
  /// 不再临时关闭视频轨: mpv 已在原生层去掉 UPDATE_VO 的整体 seek, 保持
  /// 视频轨直接切输出即可同时保住 demux 缓存和音频.
  Future<void> switchSurface(
    Future<void> Function() switchOutput, {
    required String target,
  }) async {
    _cancelCalibration();
    if (!isUsable()) {
      return;
    }
    _target = target;
    _diagnosticClock..reset()..start();
    _lastPausedForCache = null;
    _trace('begin');
    final generation = _generation;
    _path = player.getProperty('path');
    if (_savedOptions.isEmpty) {
      for (final name in _temporaryOptions.keys) {
        _savedOptions[name] = player.getProperty(name);
      }
    }
    try {
      // 先关闭缓存暂停, 避免视频暂时缺帧经 paused-for-cache 把仍有数据的
      // 音频一起暂停和 flush.
      for (final option in _temporaryOptions.entries) {
        await _set(option.key, option.value);
      }
      if (isUsable()) {
        await switchOutput();
        _trace('output switched');
      }
      if (isUsable()) {
        _checks = 0;
        _stableChecks = 0;
        _lastAudioPts = double.tryParse(player.getProperty('audio-pts'));
        _scheduleCalibration(generation);
      }
    } catch (_) {
      await restore();
      rethrow;
    }
  }

  void _scheduleCalibration(int generation) {
    _calibration = Timer(const Duration(milliseconds: 200), () {
      _calibration = null;
      lock.synchronized(() async {
        if (generation != _generation) {
          return;
        }
        if (!isUsable()) {
          dispose();
          return;
        }
        try {
          if (player.getProperty('path') != _path || !player.state.playing) {
            await restore();
            return;
          }
          final difference = double.tryParse(player.getProperty('avsync'));
          final audioPts = double.tryParse(player.getProperty('audio-pts'));
          final audioAdvancing = audioPts != null && audioPts.isFinite &&
              _lastAudioPts != null && audioPts > _lastAudioPts!;
          _lastAudioPts = audioPts;
          final pausedForCache = player.getProperty('paused-for-cache') == 'yes';
          final ready = player.getProperty('vo-configured') == 'yes' &&
              player.getProperty('seeking') == 'no' && !pausedForCache;
          final cacheDuration = double.tryParse(
            player.getProperty('demuxer-cache-duration'),
          );
          final cacheWait = double.tryParse(
            player.getProperty('cache-pause-wait'),
          ) ?? 1.0;
          final cacheReady = _savedOptions['cache-pause'] != 'yes' ||
              player.getProperty('cache') == 'no' ||
              player.getProperty('demuxer-cache-idle') == 'yes' ||
              (cacheDuration != null && cacheDuration >= cacheWait);
          if (_checks == 0 || _lastPausedForCache != pausedForCache) {
            _trace('calibrating');
          }
          _lastPausedForCache = pausedForCache;
          _stableChecks = ready && audioAdvancing && cacheReady &&
              difference != null && difference.isFinite && difference.abs() <= 0.08
              ? _stableChecks + 1 : 0;
          // 连续 3 次接近音频才恢复设置. 最多等 6 s, 避免临时设置长期残留.
          // avsync 在视频重建时会清零, 必须同时确认音频前进和缓存恢复.
          _checks++;
          if (_stableChecks >= 3 || _checks >= 30) {
            _trace(_stableChecks >= 3 ? 'settled' : 'timed out');
            await restore();
          } else {
            _scheduleCalibration(generation);
          }
        } catch (e) {
          debugPrint('MiniOverlay: surface calibration failed: $e');
          await restore();
        }
      }).ignore();
    });
  }

  /// 关窗或换视频前在 lock 内调用. 展开回页面时由校准完成后调用.
  Future<void> restore() async {
    _cancelCalibration();
    final options = _savedOptions.entries.toList();
    _savedOptions.clear();
    for (final option in options) {
      if (!isUsable()) {
        return;
      }
      try {
        // 设置页已改过的属性不再覆盖.
        if (option.value.isNotEmpty &&
            player.getProperty(option.key) == _temporaryOptions[option.key]) {
          await _set(option.key, option.value);
        }
      } catch (e) {
        debugPrint('MiniOverlay: restore ${option.key} failed: $e');
      }
    }
    if (options.isNotEmpty) {
      _trace('settings restored');
    }
    _diagnosticClock.stop();
  }

  // todo remove: 仅记录切换阶段和状态变化, 方便关联原生 AudioTrack 的暂停.
  void _trace(String stage) {
    if (!isUsable()) {
      return;
    }
    final state = {
      for (final name in const [
        'audio-pts', 'avsync', 'pause', 'paused-for-cache', 'seeking',
        'cache-pause', 'demuxer-cache-duration',
      ]) name: player.getProperty(name),
    };
    debugPrint('MiniOverlay: target=$_target stage=$stage '
        'elapsed=${_diagnosticClock.elapsedMilliseconds}ms $state');
  }

  Future<void> _set(String name, String value) async {
    if (isUsable()) {
      await player.command(['set', name, value])
          .timeout(const Duration(seconds: 3));
    }
  }

  void _cancelCalibration() {
    _generation++;
    _calibration?.cancel();
    _calibration = null;
  }

  /// 播放器销毁时仅取消延迟任务, 不再调用 mpv.
  void dispose() {
    _cancelCalibration();
    _savedOptions.clear();
    _diagnosticClock.stop();
  }
}
