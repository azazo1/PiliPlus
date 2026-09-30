import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 长截屏的目标列表.
class ScrollTarget {
  const ScrollTarget({
    required this.state,
    required this.bounds,
    required this.reversed,
  });

  final ScrollableState state;

  /// 上报给系统的滚动区域, 物理像素, 相对 FlutterView 左上角.
  final Rect bounds;

  /// 列表是否为从下往上排列 (reverse 列表).
  final bool reversed;

  ScrollPosition get position => state.position;

  /// 列表当前在屏幕上的位置, 全局逻辑像素.
  Rect? get viewportRect {
    final renderObject = state.context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
}

/// 在当前界面上查找适合长截屏的主滚动列表.
///
/// 被其它页面, 弹窗盖住的列表会因命中测试失败而被排除, 只有用户真正能滚动到的
/// 列表才会上报给系统.
abstract final class ScrollTargetFinder {
  /// 滚动区域的可见高度下限, 逻辑像素.
  static const double _minVisibleHeight = 128;

  /// 可滚动距离下限, 逻辑像素.
  static const double _minScrollExtent = 32;

  /// 采样步长, 用于找出列表没有被盖住的部分, 逻辑像素.
  static const double _sampleStep = 16;

  static ScrollTarget? find(double devicePixelRatio) {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;

    final candidates = <_Candidate>[];
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final candidate = _asCandidate(
          element.state as ScrollableState,
          devicePixelRatio,
        );
        if (candidate != null) candidates.add(candidate);
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    if (candidates.isEmpty) return null;

    // 可滚动距离最大的列表最可能是用户想截取的内容.
    candidates.sort((a, b) => b.extent.compareTo(a.extent));
    for (final candidate in candidates) {
      final target = _toTarget(candidate, devicePixelRatio);
      if (target != null) return target;
    }
    return null;
  }

  static _Candidate? _asCandidate(
    ScrollableState state,
    double devicePixelRatio,
  ) {
    final position = state.position;
    if (!position.hasContentDimensions || !position.hasPixels) return null;
    final axisDirection = position.axisDirection;
    final reversed = axisDirection == AxisDirection.up;
    if (!reversed && axisDirection != AxisDirection.down) return null;
    final extent = position.maxScrollExtent - position.minScrollExtent;
    if (extent < _minScrollExtent) return null;

    final renderObject = state.context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final size = renderObject.size;
    if (size.width < 64 || size.height < _minVisibleHeight) return null;

    final view = View.of(state.context);
    return _Candidate(
      state: state,
      renderObject: renderObject,
      rect: renderObject.localToGlobal(Offset.zero) & size,
      viewRect: _viewRect(view, devicePixelRatio),
      viewId: view.viewId,
      reversed: reversed,
      extent: extent,
    );
  }

  static ScrollTarget? _toTarget(
    _Candidate candidate,
    double devicePixelRatio,
  ) {
    final viewRect = candidate.viewRect;
    if (viewRect == null) return null;
    final rect = candidate.rect;
    final visible = rect.intersect(viewRect);
    if (visible.width < 64 || visible.height < _minVisibleHeight) return null;
    final renderObject = candidate.renderObject;
    if (!_isHit(renderObject, visible.center, candidate.viewId)) return null;

    // 滚动时始终停留在列表前缘的内容 (如 pinned 的 SliverAppBar) 不属于可滚动
    // 内容, 不排除的话每一屏都会重复截取到它.
    var top = visible.top;
    var bottom = visible.bottom;
    final sticky = _stickyExtent(renderObject);
    if (sticky > 0) {
      if (candidate.reversed) {
        bottom = math.min(bottom, rect.bottom - sticky);
      } else {
        top = math.max(top, rect.top + sticky);
      }
    }
    if (bottom - top < _minVisibleHeight) return null;

    final band = _exposedBand(
      renderObject,
      Rect.fromLTRB(visible.left, top, visible.right, bottom),
      candidate.viewId,
    );
    if (band == null) return null;

    final bounds = Rect.fromLTRB(
      (band.left * devicePixelRatio).roundToDouble(),
      (band.top * devicePixelRatio).roundToDouble(),
      (band.right * devicePixelRatio).roundToDouble(),
      (band.bottom * devicePixelRatio).roundToDouble(),
    );
    if (bounds.width < 64 || bounds.height < 2) return null;

    return ScrollTarget(
      state: candidate.state,
      bounds: bounds,
      reversed: candidate.reversed,
    );
  }

  static Rect? _viewRect(View view, double devicePixelRatio) {
    final size = view.physicalSize;
    if (size.isEmpty || devicePixelRatio <= 0) return null;
    return Rect.fromLTWH(
      0,
      0,
      size.width / devicePixelRatio,
      size.height / devicePixelRatio,
    );
  }

  /// 采样找出 [band] 中真正显示列表的一段连续区域.
  ///
  /// 底部弹窗, 悬浮控件等会盖住列表, 被盖住的部分不能上报给系统, 否则拼接长图
  /// 时每一屏都会重复截到这些控件.
  static Rect? _exposedBand(RenderObject renderObject, Rect band, int viewId) {
    final count = math.max(1, (band.height / _sampleStep).ceil());
    final step = band.height / count;
    var runStart = -1;
    for (var index = 0; index <= count; index++) {
      // 取每一段的中间位置采样, 避开边界.
      final y = band.top + step * (index + 0.5);
      if (index < count &&
          _isHit(renderObject, Offset(band.center.dx, y), viewId)) {
        if (runStart < 0) runStart = index;
        continue;
      }
      if (runStart >= 0) {
        final start = band.top + step * runStart;
        final end = math.min(band.top + step * index, band.bottom);
        if (end - start >= _minVisibleHeight) {
          return Rect.fromLTRB(band.left, start, band.right, end);
        }
        runStart = -1;
      }
    }
    return null;
  }

  /// 命中测试: 判断该位置显示的内容是否属于 [renderObject].
  static bool _isHit(RenderObject renderObject, Offset point, int viewId) {
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(result, point, viewId);
    for (final entry in result.path) {
      final hit = entry.target;
      if (hit is! RenderObject) continue;
      RenderObject? node = hit;
      while (node != null) {
        if (identical(node, renderObject)) return true;
        node = node.parent;
      }
    }
    return false;
  }

  /// 滚动时始终停留在列表前缘的内容高度, 逻辑像素.
  static double _stickyExtent(RenderObject root) {
    var extent = 0.0;
    void visit(RenderObject node) {
      if (node is RenderSliver) {
        final geometry = node.geometry;
        if (geometry != null &&
            geometry.visible &&
            geometry.paintOrigin == 0 &&
            geometry.maxScrollObstructionExtent > extent) {
          extent = geometry.maxScrollObstructionExtent;
        }
        // 列表项里不会再出现需要排除的固定内容.
        return;
      }
      node.visitChildren(visit);
    }

    root.visitChildren(visit);
    return extent;
  }
}

/// 候选的滚动列表.
class _Candidate {
  const _Candidate({
    required this.state,
    required this.renderObject,
    required this.rect,
    required this.viewRect,
    required this.viewId,
    required this.reversed,
    required this.extent,
  });

  final ScrollableState state;
  final RenderObject renderObject;

  /// 列表在屏幕上的位置, 全局逻辑像素.
  final Rect rect;

  /// 视图可见区域, 全局逻辑像素.
  final Rect? viewRect;

  final int viewId;
  final bool reversed;

  /// 可滚动距离, 逻辑像素.
  final double extent;
}
