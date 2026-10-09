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
  static const _temporaryOptions = {'video-sync': 'audio', 'framedrop': 'vo'};
  Timer? _calibration;
  int _generation = 0;
  int _checks = 0;
  int _stableChecks = 0;
  String? _path;

  /// 在 lock 内调用. 不暂停, 不 seek, 不重选音轨.
  Future<void> switchSurface(Future<void> Function() switchOutput) async {
    _cancelCalibration();
    if (!isUsable()) {
      return;
    }
    final videoTrack = player.getProperty('vid');
    final audioPts = double.tryParse(player.getProperty('audio-pts'));
    if (videoTrack.isEmpty || videoTrack == 'no' ||
        audioPts == null || !audioPts.isFinite) {
      // 无音轨时不能临时关闭唯一的视频轨, 否则 mpv 会结束播放.
      await restore();
      if (isUsable()) {
        await switchOutput();
      }
      return;
    }
    final generation = _generation;
    _path = player.getProperty('path');
    if (_savedOptions.isEmpty) {
      for (final name in _temporaryOptions.keys) {
        _savedOptions[name] = player.getProperty(name);
      }
    }
    debugPrint('MiniOverlay: switch surface without audio seek');
    try {
      try {
        // mpv 0.41 的 UPDATE_VO 会在有视频轨时排入整体 seek.
        // 先取消视频轨选择, 改 wid 后恢复, 只让视频解码器追上当前音频.
        await _set('vid', 'no');
        for (final option in _temporaryOptions.entries) {
          await _set(option.key, option.value);
        }
        if (isUsable()) {
          await switchOutput();
        }
      } finally {
        if (isUsable()) {
          await _set('vid', videoTrack);
        }
      }
      if (isUsable()) {
        _checks = 0;
        _stableChecks = 0;
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
          final ready = player.getProperty('vo-configured') == 'yes';
          _stableChecks = ready && difference != null &&
              difference.isFinite && difference.abs() <= 0.08
              ? _stableChecks + 1 : 0;
          // 连续 3 次接近音频才恢复设置. 最多等 3 s, 避免临时设置长期残留.
          _checks++;
          if (_stableChecks >= 3 || _checks >= 15) {
            debugPrint('MiniOverlay: calibration '
                '${_stableChecks >= 3 ? 'settled' : 'timed out'}, '
                'avsync=$difference');
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
  }
}
