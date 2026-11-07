import 'dart:convert';

import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/json_file_handler.dart';
import 'package:catcher_2/catcher_2.dart';
import 'package:crypto/crypto.dart';

/// 扫码登录链路的临时诊断探针.
///
/// 只有带 `--dart-define=probe.scanLogin=true` 的构建才会生效, 诊断信息以
/// catcher_2 报告的格式追加到 `.pili_logs.json`, 在 设置 -> 日志 里可以
/// 直接复制全文. 不记录 cookie / access_key / csrf / auth_code 的明文,
/// 只记录长度和 sha1 前缀.
/// todo remove
abstract final class ScanLoginDiag {
  static const bool enabled = bool.fromEnvironment('probe.scanLogin');

  static const _wantedCookies = {
    'SESSDATA',
    'bili_jct',
    'DedeUserID',
    'DedeUserID__ckMd5',
    'buvid3',
    'buvid4',
  };

  static void event(String name, [Map<String, Object?>? data]) {
    if (!enabled) return;
    final buffer = StringBuffer('[${DateTime.now().toIso8601String()}] $name');
    data?.forEach((key, value) {
      if (value == null) return;
      buffer
        ..writeln()
        ..write('  $key: $value');
    });
    final message = buffer.toString();
    logger.i(message);
    try {
      final report = Report(
        message,
        null,
        DateTime.now(),
        const {},
        const {},
        const {},
        null,
      );
      JsonFileHandler.add(
        (raf) => raf.writeString(
          '${jsonEncode(report.toJson(enableDeviceParameters: false, enableApplicationParameters: false, enableStackTrace: false))}\n',
        ),
      );
    } catch (e) {
      logger.w('ScanLoginDiag 写入日志失败', error: e);
    }
  }

  /// 敏感值只留长度与 sha1 前缀, 方便比较变化, 不泄露原文.
  static String mask(Object? value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return 'empty';
    final digest = sha1.convert(utf8.encode(text)).toString();
    return 'len=${text.length},sha1=${digest.substring(0, 8)}';
  }

  static Map<String, String> cookieSummary(Account? account) {
    if (account == null || !account.isLogin) return const {};
    try {
      final result = <String, String>{};
      for (final cookie in account.cookieJar.toList()) {
        if (!_wantedCookies.contains(cookie.name)) continue;
        result[cookie.name] = mask(cookie.value);
      }
      return result;
    } catch (e) {
      return {'error': '$e'};
    }
  }

  static Map<String, Object?> accountSummary(Account? account) {
    if (account == null) return const {'account': 'null'};
    try {
      return {
        'type': account.runtimeType.toString(),
        'isLogin': account.isLogin,
        'mid': account.isLogin ? account.mid : null,
        'accessKey': account.isLogin ? mask(account.accessKey) : null,
        'csrf': account.isLogin ? mask(account.csrf) : null,
        'cookies': cookieSummary(account),
      };
    } catch (e) {
      return {'error': '$e'};
    }
  }
}
