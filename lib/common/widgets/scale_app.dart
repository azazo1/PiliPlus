import 'dart:io' show Platform;
import 'dart:async' show scheduleMicrotask;
import 'dart:collection' show Queue;
import 'dart:ui' show PointerDataPacket;

import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDeviceKind,
        PointerEvent,
        PointerEventConverter,
        PointerRemovedEvent;
import 'package:flutter/rendering.dart' show RenderView, ViewConfiguration;
import 'package:flutter/widgets.dart';

/// ref https://github.com/LastMonopoly/scaled_app

/// Adapted from [WidgetsFlutterBinding]
///
class ScaledWidgetsFlutterBinding extends WidgetsFlutterBinding {
  ScaledWidgetsFlutterBinding._({double scaleFactor = 1.0})
    : _scaleFactor = scaleFactor;

  /// Calculate scale factor from device size.
  double _scaleFactor;

  /// Update scaleFactor callback, then rebuild layout
  set scaleFactor(double scaleFactor) {
    if (_scaleFactor == scaleFactor) return;
    _scaleFactor = scaleFactor;
    handleMetricsChanged();
  }

  double devicePixelRatioScaled = 0;

  static ScaledWidgetsFlutterBinding? _binding;

  static ScaledWidgetsFlutterBinding get instance => _binding!;

  /// Scaling will be applied based on [scaleFactor] callback.
  ///
  static WidgetsBinding ensureInitialized({double scaleFactor = 1.0}) =>
      _binding ??= ScaledWidgetsFlutterBinding._(scaleFactor: scaleFactor);

  /// Override the method from [RendererBinding.createViewConfiguration] to
  /// change what size or device pixel ratio the [RenderView] will use.
  ///
  /// See more:
  /// * [RendererBinding.createViewConfiguration]
  /// * [TestWidgetsFlutterBinding.createViewConfiguration]
  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    final view = renderView.flutterView;
    final devicePixelRatio = view.devicePixelRatio;
    devicePixelRatioScaled = devicePixelRatio * _scaleFactor;
    final BoxConstraints physicalConstraints =
        BoxConstraints.fromViewConstraints(view.physicalConstraints);
    return ViewConfiguration(
      physicalConstraints: physicalConstraints,
      logicalConstraints: physicalConstraints / devicePixelRatioScaled,
      devicePixelRatio: devicePixelRatioScaled,
    );
  }

  /// Adapted from [GestureBinding.initInstances]
  @override
  void initInstances() {
    super.initInstances();
    platformDispatcher.onPointerDataPacket = _handlePointerDataPacket;
  }

  @override
  void unlocked() {
    super.unlocked();
    _flushPointerEventQueue();
  }

  final Queue<PointerEvent> _pendingPointerEvents = Queue<PointerEvent>();
  final Set<int> _suppressedMouseDevices = <int>{};

  /// When we scale UI using [ViewConfiguration], [ui.window] stays the same.
  ///
  /// [GestureBinding] uses [platformDispatcher.implicitView.devicePixelRatio] for calculations,
  /// so we override corresponding methods.
  ///
  void _handlePointerDataPacket(PointerDataPacket packet) {
    // We convert pointer data to logical pixels so that e.g. the touch slop can be
    // defined in a device-independent manner.
    try {
      _pendingPointerEvents.addAll(
        _normalizePointerEvents(
          PointerEventConverter.expand(
            packet.data,
            _devicePixelRatioForView,
          ),
        ),
      );
      if (!locked) {
        _flushPointerEventQueue();
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'gestures library',
          context: ErrorDescription('while handling a pointer data packet'),
        ),
      );
    }
  }

  double _devicePixelRatioForView(int viewId) => devicePixelRatioScaled;

  Iterable<PointerEvent> _normalizePointerEvents(
    Iterable<PointerEvent> events,
  ) sync* {
    for (final event in events) {
      if (_shouldSuppressMouseEvent(event)) {
        final shouldClearState = _suppressedMouseDevices.add(event.device);
        if (event is PointerRemovedEvent) {
          _suppressedMouseDevices.remove(event.device);
        }
        if (shouldClearState) {
          yield PointerRemovedEvent(
            viewId: event.viewId,
            timeStamp: event.timeStamp,
            pointer: event.pointer,
            kind: event.kind,
            device: event.device,
            position: event.position,
            obscured: event.obscured,
            pressureMin: event.pressureMin,
            pressureMax: event.pressureMax,
            distanceMax: event.distanceMax,
            radiusMin: event.radiusMin,
            radiusMax: event.radiusMax,
            embedderId: event.embedderId,
          );
        }
        continue;
      }
      yield event;
    }
  }

  bool _shouldSuppressMouseEvent(PointerEvent event) {
    // Android 上的幽灵悬浮不是单个 hover 事件问题, 而是 MouseTracker
    // 会持续记住 mouse 设备的最后坐标, 所以这里直接屏蔽整条 mouse 事件链.
    return Platform.isAndroid && event.kind == PointerDeviceKind.mouse;
  }

  /// Dispatch a [PointerCancelEvent] for the given pointer soon.
  ///
  /// The pointer event will be dispatched before the next pointer event and
  /// before the end of the microtask but not within this function call.
  @override
  void cancelPointer(int pointer) {
    if (_pendingPointerEvents.isEmpty && !locked) {
      scheduleMicrotask(_flushPointerEventQueue);
    }
    _pendingPointerEvents.addFirst(PointerCancelEvent(pointer: pointer));
  }

  void _flushPointerEventQueue() {
    assert(!locked);

    while (_pendingPointerEvents.isNotEmpty) {
      handlePointerEvent(_pendingPointerEvents.removeFirst());
    }
  }
}
