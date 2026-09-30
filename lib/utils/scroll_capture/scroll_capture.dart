import 'dart:async';
import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/scale_app.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/scroll_capture/scroll_target.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 系统长截屏: Android 12 及以上系统截图界面里的 "截取更多".
///
/// Flutter 界面绘制在一张纹理上, 系统无法自行滚动界面来拼接长图, 因此滚动和定位
/// 由 Dart 侧负责, 原生侧只把指定区域的画面拷贝到系统提供的 Surface:
///   - search: 找到当前界面上的主滚动列表, 上报滚动区域;
///   - start: 记录起始滚动位置;
///   - request: 按系统请求滚动列表, 上报要拷贝的画面区域和内容位置;
///   - end: 恢复起始滚动位置.
abstract final class ScrollCaptureSupport {
  static const MethodChannel _channel = MethodChannel(
    'com.azazo1.piliplus/scroll_capture',
  );

  /// 等待重绘的超时时间. 超时说明界面没有在绘制, 此时放弃本次长截屏.
  static const Duration _frameTimeout = Duration(milliseconds: 500);

  static bool _registered = false;
  static ScrollTarget? _pendingTarget;
  static _Session? _session;

  /// 注册方法通道, Android 平台启动时调用.
  static void init() {
    if (_registered || DeviceUtils.sdkInt < 31) return;
    _registered = true;
    _channel.setMethodCallHandler(_onMethodCall);
  }

  static Future<Object?> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'search':
        return _search();
      case 'start':
        return _start();
      case 'request':
        return _request(call.arguments);
      case 'end':
        _end();
    }
    return null;
  }

  /// 系统询问可滚动区域, 返回 null 表示当前界面不支持长截屏.
  static Map<String, int>? _search() {
    final target = ScrollTargetFinder.find(_devicePixelRatio);
    _pendingTarget = target;
    if (target == null) return null;
    final bounds = target.bounds;
    return {
      'left': bounds.left.round(),
      'top': bounds.top.round(),
      'width': bounds.width.round(),
      'height': bounds.height.round(),
    };
  }

  static bool _start() {
    final target = _pendingTarget;
    _pendingTarget = null;
    if (target == null) return false;
    final position = target.position;
    final viewport = target.viewportRect;
    if (!position.hasPixels ||
        !position.hasContentDimensions ||
        viewport == null) {
      return false;
    }
    final devicePixelRatio = _devicePixelRatio;
    // 滚动区域顶部对应的内容位置, 之后所有请求坐标都以它为基准.
    final boundsTop = target.bounds.top / devicePixelRatio;
    final anchorContent = target.reversed
        ? position.pixels + (viewport.bottom - boundsTop)
        : position.pixels + (boundsTop - viewport.top);
    _session = _Session(
      target: target,
      devicePixelRatio: devicePixelRatio,
      startPixels: position.pixels,
      anchorContent: anchorContent,
    );
    return true;
  }

  static Future<Map<String, int>?> _request(Object? arguments) async {
    final session = _session;
    if (session == null || arguments is! Map) return null;
    final top = (arguments['top'] as num?)?.toDouble();
    final bottom = (arguments['bottom'] as num?)?.toDouble();
    if (top == null || bottom == null) return null;
    try {
      return await session.capture(top, bottom);
    } catch (e, stackTrace) {
      logger.w('长截屏取图失败', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  static void _end() {
    final session = _session;
    _session = null;
    if (session == null) return;
    try {
      final position = session.target.position;
      if (position.hasPixels &&
          (position.pixels - session.startPixels).abs() > 0.5) {
        position.jumpTo(session.startPixels);
      }
    } catch (e, stackTrace) {
      logger.w('长截屏恢复滚动位置失败', error: e, stackTrace: stackTrace);
    }
  }

  static double get _devicePixelRatio {
    final devicePixelRatio =
        ScaledWidgetsFlutterBinding.instance.devicePixelRatioScaled;
    if (devicePixelRatio > 0) return devicePixelRatio;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? 1 : views.first.devicePixelRatio;
  }
}

/// 等待下一次绘制完成, 返回 false 说明界面没有在绘制.
Future<bool> _waitNextFrame() async {
  try {
    await SchedulerBinding.instance.endOfFrame.timeout(
      ScrollCaptureSupport._frameTimeout,
    );
    return true;
  } on TimeoutException {
    return false;
  }
}

/// 一次长截屏会话.
class _Session {
  _Session({
    required this.target,
    required this.devicePixelRatio,
    required this.startPixels,
    required this.anchorContent,
  });

  final ScrollTarget target;
  final double devicePixelRatio;

  /// 会话开始时的滚动位置, 逻辑像素.
  final double startPixels;

  /// 会话开始时滚动区域顶部对应的内容位置, 逻辑像素.
  final double anchorContent;

  /// 按系统请求滚动列表, 返回需要拷贝的画面区域, null 表示没有可截取的内容.
  ///
  /// [requestTop] 和 [requestBottom] 相对滚动区域的起始滚动位置, 物理像素, 可以
  /// 落在起始位置上方 (负值).
  Future<Map<String, int>?> capture(
    double requestTop,
    double requestBottom,
  ) async {
    final position = target.position;
    if (!position.hasPixels || !position.hasContentDimensions) return null;
    if (requestBottom - requestTop < 1) return null;

    final bounds = target.bounds;
    final devicePixelRatio = this.devicePixelRatio;
    final reversed = target.reversed;

    // 滚动区域内的偏移 (物理像素) 换算成内容位置 (逻辑像素).
    double contentOf(double offset) => reversed
        ? anchorContent - offset / devicePixelRatio
        : anchorContent + offset / devicePixelRatio;

    final requestLow = math.min(
      contentOf(requestTop),
      contentOf(requestBottom),
    );
    final requestHigh = math.max(
      contentOf(requestTop),
      contentOf(requestBottom),
    );

    // 用最小的滚动量让请求的内容可见.
    final viewportDimension = position.viewportDimension;
    var targetPixels = position.pixels;
    if (requestLow < targetPixels) {
      targetPixels = requestLow;
    } else if (requestHigh > targetPixels + viewportDimension) {
      targetPixels = requestHigh - viewportDimension;
    }
    targetPixels = math.max(
      position.minScrollExtent,
      math.min(position.maxScrollExtent, targetPixels),
    );
    if ((targetPixels - position.pixels).abs() > 0.5) {
      position.jumpTo(targetPixels);
      if (!await _waitNextFrame()) return null;
    }

    final viewport = target.viewportRect;
    if (viewport == null) return null;
    final pixels = position.pixels;
    final viewportTop = viewport.top;
    final viewportBottom = viewport.bottom;

    // 内容位置 (逻辑像素) 换算成屏幕纵坐标 (全局逻辑像素).
    double screenYOf(double content) => reversed
        ? viewportBottom - (content - pixels)
        : viewportTop + (content - pixels);

    // 屏幕纵坐标换算成内容位置.
    double contentOfScreenY(double y) =>
        reversed ? pixels + (viewportBottom - y) : pixels + (y - viewportTop);

    // 只有当前可见, 并且落在滚动区域内的内容才能截取.
    final boundsContentA = contentOfScreenY(bounds.top / devicePixelRatio);
    final boundsContentB = contentOfScreenY(bounds.bottom / devicePixelRatio);
    final low = math.max(
      math.max(requestLow, pixels),
      math.min(boundsContentA, boundsContentB),
    );
    final high = math.min(
      math.min(requestHigh, pixels + position.viewportDimension),
      math.max(boundsContentA, boundsContentB),
    );
    if (high - low < 1) return null;

    var srcTop = screenYOf(low) * devicePixelRatio;
    var srcBottom = screenYOf(high) * devicePixelRatio;
    if (srcTop > srcBottom) {
      final swap = srcTop;
      srcTop = srcBottom;
      srcBottom = swap;
    }
    srcTop = math.max(srcTop.roundToDouble(), bounds.top);
    srcBottom = math.min(srcBottom.roundToDouble(), bounds.bottom);
    if (srcBottom - srcTop < 1) return null;

    // 屏幕纵坐标 (物理像素) 在长图中对应的位置 (相对滚动区域, 物理像素).
    double capturedOf(double srcY) {
      final content = contentOfScreenY(srcY / devicePixelRatio);
      return reversed
          ? (anchorContent - content) * devicePixelRatio
          : (content - anchorContent) * devicePixelRatio;
    }

    // 拷贝区域换算成长图中的位置, 相对起始滚动位置, 起始位置上方为负值.
    final height = (srcBottom - srcTop).round();
    final capturedTop = capturedOf(srcTop).round();
    return {
      'left': bounds.left.round(),
      'top': srcTop.round(),
      'width': bounds.width.round(),
      'height': height,
      'capturedTop': capturedTop,
    };
  }
}
