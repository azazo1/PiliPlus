import 'package:PiliPlus/pages/qr_scan/handler.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫一扫: 相机扫码, 或从相册图片 (如评论/动态截图) 识别二维码.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  late final _imagePicker = ImagePicker();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onResult(String? value) {
    if (_handled) return;
    _handled = true;
    _controller.stop();
    Get.back();
    QrScanHandler.handle(value);
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes
        .map((e) => e.rawValue)
        .firstWhere((e) => e != null && e.isNotEmpty, orElse: () => null);
    if (value != null) {
      _onResult(value);
    }
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (pickedFile == null || !mounted) return;
      SmartDialog.showLoading(msg: '识别中...');
      final capture = await _controller.analyzeImage(
        pickedFile.path,
        formats: const [BarcodeFormat.qrCode],
      );
      SmartDialog.dismiss();
      final value = capture?.barcodes
          .map((e) => e.rawValue)
          .firstWhere((e) => e != null && e.isNotEmpty, orElse: () => null);
      if (value == null) {
        SmartDialog.showToast('图片中未识别到二维码');
        return;
      }
      _onResult(value);
    } catch (e, s) {
      SmartDialog.dismiss();
      logger.e('相册识别二维码失败', error: e, stackTrace: s);
      SmartDialog.showToast('识别失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final windowSize = size.shortestSide * 0.7;
    final scanWindow = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: windowSize,
      height: windowSize,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('扫一扫'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) {
              final torchState = state.torchState;
              if (torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: '手电筒',
                onPressed: _controller.toggleTorch,
                icon: Icon(
                  torchState == TorchState.on
                      ? Icons.flashlight_on
                      : Icons.flashlight_off,
                ),
              );
            },
          ),
          IconButton(
            tooltip: '从相册识别',
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            scanWindow: scanWindow,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? '没有相机权限, 可以从相册选择图片识别'
                      : '相机启动失败: ${error.errorCode.message}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _ScanWindowPainter(
                scanWindow: scanWindow,
                borderColor: colorScheme.primary,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: scanWindow.bottom + 24,
            child: Column(
              children: [
                const Text(
                  '将二维码放入框内, 即可自动扫描',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('从相册识别'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanWindowPainter extends CustomPainter {
  _ScanWindowPainter({
    required this.scanWindow,
    required this.borderColor,
  });

  final Rect scanWindow;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final window = RRect.fromRectAndRadius(
      scanWindow,
      const Radius.circular(12),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(window),
      ),
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(
      window,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ScanWindowPainter oldDelegate) =>
      scanWindow != oldDelegate.scanWindow ||
      borderColor != oldDelegate.borderColor;
}
