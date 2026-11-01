import 'package:PiliPlus/pages/qr_scan/scanner/scanner.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// Android 原生的微信二维码引擎, 相机预览以 PlatformView 嵌入.
class WeChatQrScanner implements QrScanner {
  static const _channel = MethodChannel('com.azazo1.piliplus/qr_scan');
  static const _viewType = 'com.azazo1.piliplus/qr_scan/view';

  MethodChannel? _viewChannel;
  ValueChanged<String>? _onDetect;

  @override
  final ValueNotifier<bool?> torch = ValueNotifier(false);

  void _attach(int viewId) {
    _viewChannel = MethodChannel('com.azazo1.piliplus/qr_scan/view_$viewId')
      ..setMethodCallHandler((call) async {
        if (call.method == 'onDetect' && call.arguments is String) {
          _onDetect?.call(call.arguments as String);
        }
      });
  }

  @override
  Widget buildPreview(
    BuildContext context, {
    required Rect scanWindow,
    required ValueChanged<String> onDetect,
  }) {
    _onDetect = onDetect;
    return _WeChatPreview(onCreated: _attach);
  }

  @override
  Future<void> toggleTorch() async {
    final channel = _viewChannel;
    if (channel == null) return;
    final on = await channel.invokeMethod<bool>('toggleTorch');
    if (on == null) {
      SmartDialog.showToast('当前设备没有闪光灯');
      return;
    }
    torch.value = on;
  }

  @override
  Future<String?> analyzeImage(String path) =>
      _channel.invokeMethod<String>('decodeImage', path);

  @override
  void stop() => _viewChannel?.invokeMethod('setAnalyze', false).ignore();

  @override
  void dispose() {
    _viewChannel?.setMethodCallHandler(null);
    _onDetect = null;
    torch.dispose();
  }
}

class _WeChatPreview extends StatefulWidget {
  const _WeChatPreview({required this.onCreated});

  final PlatformViewCreatedCallback onCreated;

  @override
  State<_WeChatPreview> createState() => _WeChatPreviewState();
}

class _WeChatPreviewState extends State<_WeChatPreview> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _error = '没有相机权限, 可以从相册选择图片识别');
      return;
    }
    bool ready;
    try {
      // 首次加载模型需要一点时间, 在后台线程完成.
      ready = await WeChatQrScanner._channel.invokeMethod<bool>('init') ?? false;
    } catch (e, s) {
      logger.e('加载扫码引擎失败', error: e, stackTrace: s);
      ready = false;
    }
    if (!mounted) return;
    setState(() {
      if (ready) {
        _ready = true;
      } else {
        _error = '扫码引擎加载失败, 可以从相册选择图片识别';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return QrScanMessage(error);
    }
    if (!_ready) {
      return const SizedBox.shrink();
    }
    return AndroidView(
      viewType: WeChatQrScanner._viewType,
      onPlatformViewCreated: widget.onCreated,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }
}
