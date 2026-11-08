import 'package:PiliPlus/pages/qr_scan/login.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 扫码结果分发, 参考官方客户端: 扫码登录 > 站内链接路由 > 其它内容.
abstract final class QrScanHandler {
  static final _officialHostRegExp = RegExp(
    r'(^|\.)(bilibili\.(com|tv|cn)|b23\.tv|bili2233\.cn|bili(22|23|33)\.cn)$',
    caseSensitive: false,
  );

  static bool _isPassportHost(String host) =>
      host == 'passport.bilibili.com' || host == 'account.bilibili.com';

  static Future<void> handle(String? raw) async {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      SmartDialog.showToast('未识别到二维码内容');
      return;
    }
    logger.i('扫码结果: $text');

    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      final scheme = uri.scheme.toLowerCase();
      final isHttp = scheme == 'http' || scheme == 'https';
      final host = uri.host.toLowerCase();

      if (isHttp && _isPassportHost(host)) {
        // 网页端扫码登录: account.bilibili.com/h5/account-h5/auth/scan-web?qrcode_key=***
        // 官方 App 扫码后进入该 H5 页面, 由页面完成状态检查, 异地/环境/
        // 手机号等额外验证以及确认登录, 原生对话框无法覆盖这些验证流程.
        final qrcodeKey = uri.queryParameters['qrcode_key'];
        if (qrcodeKey != null && qrcodeKey.isNotEmpty) {
          // 打开前确保当前账号的 cookie 已同步到 webview.
          await LoginUtils.setWebCookie(Accounts.main);
          PageUtils.inAppWebview(text, parameters: {'uaType': 'app'});
          return;
        }
        // TV/HD 端扫码登录: passport.bilibili.com/x/passport-tv-login/h5/qrcode/auth?auth_code=***
        final authCode = uri.queryParameters['auth_code'];
        if (authCode != null &&
            authCode.isNotEmpty &&
            uri.path.contains('passport-tv-login')) {
          return ScanLogin.tv(authCode);
        }
      }

      if (scheme == 'bilibili' ||
          (isHttp && _officialHostRegExp.hasMatch(host))) {
        await PiliScheme.routePushFromUrl(text);
        return;
      }
    }

    _showOther(text, uri);
  }

  static void _showOther(String text, Uri? uri) {
    final context = Get.context;
    if (context == null) return;
    final isWebLink =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫码结果'),
        content: SelectableText(text),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '关闭',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              Utils.copyText(text);
            },
            child: const Text('复制'),
          ),
          if (isWebLink)
            TextButton(
              onPressed: () {
                Get.back();
                PageUtils.launchURL(text);
              },
              child: const Text('浏览器打开'),
            ),
        ],
      ),
    );
  }
}
