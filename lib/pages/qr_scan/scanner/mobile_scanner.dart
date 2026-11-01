import 'package:PiliPlus/pages/qr_scan/scanner/scanner.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 基于 mobile_scanner 的扫码引擎.
class MobileQrScanner implements QrScanner {
  MobileQrScanner() {
    _controller.addListener(_syncTorch);
  }

  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  final ValueNotifier<bool?> torch = ValueNotifier(null);

  void _syncTorch() {
    torch.value = switch (_controller.value.torchState) {
      TorchState.unavailable => null,
      TorchState.on => true,
      _ => false,
    };
  }

  static String? _firstValue(BarcodeCapture? capture) => capture?.barcodes
      .map((e) => e.rawValue)
      .firstWhere((e) => e != null && e.isNotEmpty, orElse: () => null);

  @override
  Widget buildPreview(
    BuildContext context, {
    required Rect scanWindow,
    required ValueChanged<String> onDetect,
  }) {
    return MobileScanner(
      controller: _controller,
      scanWindow: scanWindow,
      onDetect: (capture) {
        final value = _firstValue(capture);
        if (value != null) {
          onDetect(value);
        }
      },
      errorBuilder: (context, error) => QrScanMessage(
        error.errorCode == MobileScannerErrorCode.permissionDenied
            ? '没有相机权限, 可以从相册选择图片识别'
            : '相机启动失败: ${error.errorCode.message}',
      ),
    );
  }

  @override
  Future<void> toggleTorch() => _controller.toggleTorch();

  @override
  Future<String?> analyzeImage(String path) async => _firstValue(
    await _controller.analyzeImage(
      path,
      formats: const [BarcodeFormat.qrCode],
    ),
  );

  @override
  void stop() => _controller.stop();

  @override
  void dispose() {
    _controller
      ..removeListener(_syncTorch)
      ..dispose();
    torch.dispose();
  }
}
