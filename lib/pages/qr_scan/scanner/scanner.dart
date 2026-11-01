import 'dart:io';

import 'package:PiliPlus/pages/qr_scan/scanner/mobile_scanner.dart';
import 'package:PiliPlus/pages/qr_scan/scanner/wechat_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 扫码引擎. 界面由 [QrScanPage] 统一绘制, 引擎只负责相机预览和识别.
///
/// Android 使用微信开源的二维码引擎 (深色背景, 白边很窄的二维码也能识别),
/// 其它平台使用 mobile_scanner.
abstract class QrScanner {
  factory QrScanner() =>
      Platform.isAndroid ? WeChatQrScanner() : MobileQrScanner();

  /// 手电筒是否打开, null 表示不可用.
  ValueListenable<bool?> get torch;

  Widget buildPreview(
    BuildContext context, {
    required Rect scanWindow,
    required ValueChanged<String> onDetect,
  });

  Future<void> toggleTorch();

  /// 识别图片文件中的二维码.
  Future<String?> analyzeImage(String path);

  void stop();

  void dispose();
}

class QrScanMessage extends StatelessWidget {
  const QrScanMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
