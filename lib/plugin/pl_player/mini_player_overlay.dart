import 'dart:async';

import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/overlay_surface_switcher.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
// ignore: implementation_imports
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';
import 'package:synchronized/synchronized.dart';

/// 小窗会话状态. closing 期间播放器已经交还给页面 (或即将释放), 不算 active.
enum _OverlayState { idle, opening, shown, closing }

enum _CloseMode {
  /// 回到播放页: 把 mpv 输出切回 Flutter 纹理.
  restore,

  /// 关小窗且不回播放页: 暂停, 放下小窗 Surface, 释放播放器.
  release,

  /// 换另一支视频: 暂停, 放下小窗 Surface, 播放器留给新页面 setDataSource.
  newVideo,
}

/// 把同一个播放器的画面输出在主页面与系统悬浮窗之间切换.
///
/// 参考 B 站 com.bilibili.mini.player.common.view.MiniPlayerFloatViewManager:
/// 它把承载播放器的 View 在 activity window 与 system window 之间搬来搬去,
/// 播放器实例全程不重建, 因此小窗是无缝的 (不重新拉流, 不重新缓冲).
///
/// Flutter 的画面纹理搬不了, 所以改 mpv 的输出目标 (wid).
///
/// 同样对齐 B 站 MiniPlayerManagerDelegate: 所有切换按顺序串行执行 ([_lock]),
/// 每次开窗分配新的会话号, 过期的异步步骤与原生事件直接丢弃.
abstract final class MiniPlayerOverlay {
  static const _channel = MethodChannel('com.azazo1.piliplus/mini_player');

  /// mpv 输出切换, 拆窗等步骤按顺序执行.
  static final _lock = Lock();

  /// 会话号. 每开一次小窗 +1, 小窗持有的播放器被销毁时也 +1.
  static int _session = 0;
  static _OverlayState _state = _OverlayState.idle;

  static Player? _player;
  static OverlaySurfaceSwitcher? _surfaceSwitcher;

  /// 已经开始销毁的播放器, 之后任何步骤都不再碰它.
  static Player? _disposedPlayer;
  static bool _keepPage = false;
  static bool _expanding = false;
  static Timer? _expandTimeout;
  static void Function()? _release;
  static _ResumeArgs? _resume;

  /// 悬浮窗权限缓存. 离开播放页时要同步判断能否开窗.
  static bool? _canDraw;
  static bool _handlerInstalled = false;

  static StreamSubscription<Duration>? _progress;
  static DateTime? _lastProgressPush;

  /// 展开时 _resume 为空, 让播放器把 aid/cid 再写进来.
  static void Function()? onNeedResume;

  /// 小窗 session 期间 (打开中或已显示): 播放页不要进系统 PiP, 也不要因为离开就 dispose 播放器.
  static bool get isActive =>
      _state == _OverlayState.opening || _state == _OverlayState.shown;

  /// 点小窗展开的是同一支视频, 才把正在播的播放器接回页面.
  static bool isSameVideo({required int aid, required int cid}) {
    final args = _resume;
    if (args == null || args.roomId != null) {
      return false;
    }
    return args.aid == aid && args.cid == cid;
  }

  /// 点小窗展开的是同一直播间, 才把正在播的播放器接回页面.
  static bool isSameLive(int roomId) {
    final args = _resume;
    return roomId > 0 && args?.roomId == roomId;
  }

  static Future<bool> hasPermission() async {
    _installHandler();
    try {
      final value =
          await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
      _canDraw = value;
      return value;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermission() =>
      _channel.invokeMethod('requestOverlayPermission');

  /// 提前缓存悬浮窗权限, 否则第一次离开播放页时无法同步判断.
  static void prefetchPermission() {
    if (_canDraw == null) {
      hasPermission();
    }
  }

  /// 回到所属播放页: 先把画面切回主页面纹理, 再拆小窗.
  static Future<void> closeAndRestore() => _close(_CloseMode.restore);

  /// 点了另一支视频: 拆小窗但留下播放器, 让新页面 setDataSource.
  static Future<void> dismissForNewVideo() => _close(_CloseMode.newVideo);

  /// 小窗期间所属播放页被关掉: 之后关小窗没有页面可回, 需要释放播放器.
  static void markPageLeft(void Function()? release) {
    if (!isActive) {
      return;
    }
    _keepPage = false;
    if (release != null) {
      _release = release;
    }
  }

  /// 播放器即将销毁. 小窗还持有它时立刻作废会话并拆窗, 之后不再碰这个播放器.
  static void onPlayerDisposing(Player? player) {
    if (player == null) {
      return;
    }
    _disposedPlayer = player;
    if (identical(player, _surfaceSwitcher?.player)) {
      _surfaceSwitcher?.dispose();
      _surfaceSwitcher = null;
    }
    if (!identical(player, _player)) {
      return;
    }
    final session = _session;
    _log('player disposing while overlay holds it, session=$session');
    _session++;
    _stopPlaybackPush();
    _cancelExpandTimeout();
    _player = null;
    _release = null;
    _keepPage = false;
    _expanding = false;
    _setState(_OverlayState.idle);
    // 原生拆窗后 Surface 延迟释放, 覆盖 mpv_terminate_destroy 的耗时.
    _hideNative(session);
  }

  /// 退出播放页时调用: 有悬浮窗权限就把同一 Player 切到小窗.
  ///
  /// 返回前同步决定是否占用播放器 ([isActive]), 调用方据此决定是否 dispose.
  static Future<bool> enterFromLeavingVideo({
    required Player? player,
    required int aid,
    required String bvid,
    required int cid,
    required VideoType videoType,
    int? seasonId,
    int? epId,
    int? pgcType,
    int? roomId,
    String? cover,
    String? title,
    void Function()? onUserClosed,
    bool keepPage = false,
  }) async {
    final live = roomId != null && roomId > 0;
    if (player == null ||
        (!live && cid <= 0) ||
        identical(player, _disposedPlayer) ||
        player.disposed) {
      return false;
    }
    if (_canDraw == false) {
      // 已知没有悬浮窗权限: 不占用播放器, 让播放页照常释放. 顺便刷新缓存.
      hasPermission();
      return false;
    }
    captureResume(
      aid: aid,
      bvid: bvid,
      cid: cid,
      videoType: videoType,
      seasonId: seasonId,
      epId: epId,
      pgcType: pgcType,
      roomId: roomId,
      cover: cover,
      title: title,
    );
    if (isActive) {
      _keepPage = keepPage;
      _release = onUserClosed ?? _release;
      return true;
    }
    // 上一个会话可能还在 closing, 新会话的步骤排在它后面执行.
    _installHandler();
    final session = ++_session;
    _player = player;
    _keepPage = keepPage;
    _release = onUserClosed;
    _expanding = false;
    _setState(_OverlayState.opening);
    _lock.synchronized(() => _open(session, player));
    return true;
  }

  static void captureResume({
    required int aid,
    required String bvid,
    required int cid,
    required VideoType videoType,
    int? seasonId,
    int? epId,
    int? pgcType,
    int? roomId,
    String? cover,
    String? title,
  }) {
    final live = roomId != null && roomId > 0;
    if (!live && (cid <= 0 || bvid.isEmpty)) {
      return;
    }
    _resume = _ResumeArgs(
      aid: aid,
      bvid: bvid,
      cid: cid,
      videoType: videoType,
      seasonId: seasonId,
      epId: epId,
      pgcType: pgcType,
      roomId: live ? roomId : null,
      cover: cover,
      title: title,
    );
  }

  static void _log(String message) {
    debugPrint('MiniOverlay: $message');
  }

  static void _setState(_OverlayState next) {
    if (_state != next) {
      _log('state ${_state.name} -> ${next.name}, session=$_session');
      _state = next;
    }
  }

  static bool _isCurrent(int session, _OverlayState state) =>
      session == _session && _state == state;

  static bool _usable(Player? player) =>
      player != null &&
      !identical(player, _disposedPlayer) &&
      !player.disposed;

  static OverlaySurfaceSwitcher _switcherFor(Player player) {
    if (!identical(player, _surfaceSwitcher?.player)) {
      _surfaceSwitcher?.dispose();
      _surfaceSwitcher = OverlaySurfaceSwitcher(
        player, _lock, () => _usable(player),
      );
    }
    return _surfaceSwitcher!;
  }

  /// 在 [_lock] 内执行: 检查权限并起窗. Surface 就绪后由 [_onSurfaceReady] 接管画面.
  static Future<void> _open(int session, Player player) async {
    if (!_isCurrent(session, _OverlayState.opening)) {
      return;
    }
    if (!await hasPermission()) {
      _log('no overlay permission, session=$session');
      if (_isCurrent(session, _OverlayState.opening)) {
        _abortOpen(session);
      }
      return;
    }
    if (!_isCurrent(session, _OverlayState.opening)) {
      return;
    }
    var ok = false;
    try {
      ok =
          await _channel.invokeMethod<bool>('showOverlay', {
            'session': session,
            'width': player.state.width,
            'height': player.state.height,
            'live': PlPlayerController.instance?.isLive ?? false,
          }) ??
          false;
    } catch (e) {
      _log('showOverlay failed: $e');
    }
    if (session != _session) {
      // 播放器在此期间被销毁: 窗口如果起来了就收掉.
      if (ok) {
        _hideNative(session);
      }
      return;
    }
    // 状态变成 closing 时, 排在后面的关闭步骤会负责拆窗.
    if (!ok && _state == _OverlayState.opening) {
      _abortOpen(session);
    }
  }

  /// 小窗开不起来: 页面已经走了就释放播放器, 不要后台无画面地继续出声.
  static void _abortOpen(int session) {
    final release = _keepPage ? null : _release;
    _finish(session);
    release?.call();
  }

  /// 在 [_lock] 内执行: 把 mpv 输出切到小窗 Surface.
  static Future<void> _onSurfaceReady(int session, int wid) async {
    if (!_isCurrent(session, _OverlayState.opening)) {
      _log('drop surface ready, session=$session state=${_state.name}');
      return;
    }
    final player = _player;
    if (!_usable(player)) {
      return;
    }
    final controller = AndroidVideoController.of(player!);
    if (controller == null) {
      _log('android video controller missing, close overlay');
      _close(_keepPage ? _CloseMode.restore : _CloseMode.release);
      return;
    }
    final width = player.state.width;
    final height = player.state.height;
    try {
      await _switcherFor(player).switchSurface(() => controller.attachOverlayWid(
        wid,
        width: width,
        height: height,
      ));
    } catch (e) {
      _log('attach overlay surface failed: $e');
      _close(_keepPage ? _CloseMode.restore : _CloseMode.release);
      return;
    }
    // 期间被关闭或销毁时, 排在后面的步骤会把输出切走.
    if (!_isCurrent(session, _OverlayState.opening)) {
      return;
    }
    _setState(_OverlayState.shown);
    _startPlaybackPush(player);
  }

  /// 关小窗. 立即隐藏窗口给出反馈, 输出切换与拆窗排进 [_lock] 依次执行:
  /// 先把 mpv 从小窗 Surface 切走, 再拆窗, 原生侧再延迟释放 Surface.
  static Future<void> _close(_CloseMode mode) {
    if (!isActive) {
      // 已经在关或已关: 等排在前面的步骤做完即可.
      return _lock.synchronized<void>(() {});
    }
    final session = _session;
    final player = _player;
    _setState(_OverlayState.closing);
    _stopPlaybackPush();
    _cancelExpandTimeout();
    if (mode != _CloseMode.restore && _usable(player)) {
      player!.pause().ignore();
    }
    _invoke('concealOverlay');
    return _lock.synchronized(() async {
      if (_usable(player)) {
        final controller = AndroidVideoController.of(player!);
        if (mode == _CloseMode.restore && controller != null) {
          try {
            if (controller.overlayAttached) {
              await _switcherFor(player).switchSurface(controller.detachOverlayWid);
            } else {
              await controller.detachOverlayWid();
            }
          } catch (e) {
            _log('restore page surface failed: $e');
            if (_usable(player)) {
              await player.pause();
              if (_usable(player)) {
                // detach 可能在清除 attached 标记后失败, 直接放下原生输出.
                await player.command(['set', 'vo', 'null'])
                    .timeout(const Duration(seconds: 3));
                if (_usable(player)) {
                  await player.command(['set', 'wid', '0'])
                      .timeout(const Duration(seconds: 3));
                }
              }
            }
          }
        } else {
          if (identical(player, _surfaceSwitcher?.player)) {
            await _surfaceSwitcher?.restore();
          }
          await controller?.releaseOverlayWid();
        }
      }
      _hideNative(session);
      if (session != _session) {
        return;
      }
      final release = mode == _CloseMode.release ? _release : null;
      _finish(session);
      release?.call();
    });
  }

  /// 会话结束后清状态. [_resume] 留给下一次展开补; 真正换视频时由 captureResume 覆盖.
  static void _finish(int session) {
    if (session != _session) {
      return;
    }
    _stopPlaybackPush();
    _cancelExpandTimeout();
    _player = null;
    _release = null;
    _keepPage = false;
    _expanding = false;
    _setState(_OverlayState.idle);
  }

  static void _cancelExpandTimeout() {
    _expandTimeout?.cancel();
    _expandTimeout = null;
  }

  static void _hideNative(int session) {
    _invoke('hideOverlay', {'session': session});
  }

  static Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod(method, args);
    } catch (e) {
      _log('$method failed: $e');
    }
  }

  /// 点小窗展开按钮回播放页. 原生侧已经先隐藏了小窗.
  static Future<void> _expand() async {
    if (_state != _OverlayState.shown || _expanding) {
      if (_state == _OverlayState.opening) {
        // 画面还没接管, 先恢复显示, 就绪后再点.
        _invoke('revealOverlay');
      }
      return;
    }
    onNeedResume?.call();
    final session = _session;
    final args = _resume;
    _expanding = true;
    // 只等拉起 Activity 的调用返回, 不等 onResume: 页面可以先 push, 转场在回到前台后播放.
    await _invoke('bringToFront');
    if (!_isCurrent(session, _OverlayState.shown)) {
      return;
    }
    if (_keepPage) {
      await closeAndRestore();
      return;
    }
    if (args == null) {
      // 没有可回的页面, 只能收掉小窗.
      await _close(_CloseMode.release);
      return;
    }
    // 播放页 playerInit 发现是同一支视频会调 closeAndRestore, 否则 dismissForNewVideo.
    // 页面迟迟没接上 (拉流失败等) 时恢复显示, 不留一个看不见却还在出声的小窗.
    _cancelExpandTimeout();
    _expandTimeout = Timer(const Duration(seconds: 8), () {
      _expandTimeout = null;
      if (_isCurrent(session, _OverlayState.shown) && _expanding) {
        _log('page did not take over after expand, reveal overlay');
        _expanding = false;
        _invoke('revealOverlay');
      }
    });
    if (args.roomId case final roomId?) {
      PageUtils.toLiveRoom(roomId);
      return;
    }
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

  static void _startPlaybackPush(Player player) {
    _progress?.cancel();
    _pushPlayback(player, force: true);
    _progress = player.stream.position.listen((_) {
      if (_state != _OverlayState.shown) {
        return;
      }
      _pushPlayback(player);
    });
  }

  static void _stopPlaybackPush() {
    _progress?.cancel();
    _progress = null;
    _lastProgressPush = null;
  }

  static void _pushPlayback(Player player, {bool force = false}) {
    if (!_usable(player)) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastProgressPush != null &&
        now.difference(_lastProgressPush!) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastProgressPush = now;
    final playing =
        PlPlayerController.instance?.playerStatus.value.isPlaying ??
        player.state.playing;
    _invoke('overlayPlayback', {
      'playing': playing,
      'position': player.state.position.inMilliseconds,
      'duration': player.state.duration.inMilliseconds,
      'buffered': player.state.buffer.inMilliseconds,
    });
  }

  static Future<void> _onPlayPause() async {
    final controller = PlPlayerController.instance;
    final player = _player;
    if (!_usable(player)) {
      return;
    }
    if (controller != null) {
      if (controller.playerStatus.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } else if (player!.state.playing) {
      await player.pause();
    } else {
      await player.play();
    }
    _pushPlayback(player!, force: true);
  }

  static Future<void> _onSeekBy(int deltaMs) async {
    final player = _player;
    if (!_usable(player) ||
        deltaMs == 0 ||
        PlPlayerController.instance?.isLive == true) {
      return;
    }
    final duration = player!.state.duration;
    if (duration <= Duration.zero) {
      return;
    }
    var next = player.state.position + Duration(milliseconds: deltaMs);
    if (next < Duration.zero) {
      next = Duration.zero;
    } else if (next > duration) {
      next = duration;
    }
    if (PlPlayerController.instance != null) {
      await PlPlayerController.seekToIfExists(next, isSeek: false);
    } else {
      try {
        await player.seek(next);
      } catch (_) {}
    }
    _pushPlayback(player, force: true);
  }

  static void _installHandler() {
    if (_handlerInstalled) {
      return;
    }
    _handlerInstalled = true;
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'onActivityResumed') {
      _onActivityResumed();
      return;
    }
    final args = call.arguments is Map ? call.arguments as Map : const {};
    final session = (args['session'] as num?)?.toInt();
    if (session == null || session != _session || !isActive) {
      _log('drop ${call.method}, session=$session current=$_session');
      return;
    }
    switch (call.method) {
      case 'onSurfaceReady':
        final wid = int.tryParse(args['wid']?.toString() ?? '') ?? 0;
        if (wid != 0) {
          await _lock.synchronized(() => _onSurfaceReady(session, wid));
        }
      case 'onSurfaceLost':
        // 小窗 Surface 意外丢失.
        _close(_keepPage ? _CloseMode.restore : _CloseMode.release);
      case 'onHostFinishing':
        // 宿主 Activity 结束 (划掉任务等): 停播并收窗.
        _close(_CloseMode.release);
      case 'onOverlayClose':
        if (_keepPage) {
          if (_usable(_player)) {
            _player!.pause().ignore();
          }
          _close(_CloseMode.restore);
        } else {
          _close(_CloseMode.release);
        }
      case 'onOverlayTap':
        await _expand();
      case 'onOverlayPlayPause':
        await _onPlayPause();
      case 'onOverlaySeekBy':
        await _onSeekBy((args['delta'] as num?)?.toInt() ?? 0);
    }
  }

  static void _onActivityResumed() {
    // 用户可能刚在设置里改了悬浮窗权限.
    hasPermission();
    // HOME 开的小窗: 回到所属播放页才收窗, 页内继续播.
    if (isActive &&
        _keepPage &&
        !_expanding &&
        (Get.currentRoute == '/videoV' || Get.currentRoute == '/liveRoom')) {
      closeAndRestore();
    }
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
    this.roomId,
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
  final int? roomId;
  final String? cover;
  final String? title;
}
