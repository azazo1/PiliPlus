import 'dart:convert';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/app_sign.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 账号中心 H5 在官方 App 内依赖 native 注入的 BiliJsBridge 发请求,
/// 这里提供同等能力, 让扫码确认与额外验证流程可以在应用内完成.
abstract final class ScanWebBridge {
  /// 当前用于确认登录的账号, 页面的"切换账号"会改它.
  static Account? _account;

  static Account get _current =>
      _account ??= Accounts.main;

  /// 打开页面时重置, 避免沿用上一次扫码的选择.
  static void reset() => _account = null;

  /// 页面声明支持的能力, 缺一项都会被页面判定为不可用.
  static const _methods = [
    'global.getAllSupport',
    'global.getContainerInfo',
    'global.import',
    'global.registerChannel',
    'global.unregisterChannel',
    'global.closeBrowser',
    'global.switchBizModule',
    'net.request',
    'net.requestV2',
    'net.requestWithSign',
    'net.requestWithSignV2',
    'net.requestWithoutParams',
    'net.getCsrf',
    'auth.getUserInfo',
    'auth.getUserVipInfo',
    'auth.login',
    'auth.exchangeTicket',
    'ability.reportEvent',
    'ability.reportEventV3',
    'ability.alert',
    'ability.canOpenScheme',
    'ability.openScheme',
    'ability.openApplication',
    'ability.sendMsg',
    'ui.hideNavigation',
    'ui.showNavigation',
    'ui.currentThemeType',
    'ui.toast',
  ];

  /// 注入到文档开始处的脚本: 只负责把页面消息转给 Flutter, 不做业务.
  ///
  /// 页面脚本一执行就会检测 `window.biliInjectV2`, 因此必须早于页面脚本注入,
  /// 否则页面判定不在官方 App 内, 直接放弃渲染.
  static const script = r'''
(function () {
  if (String(location.href || '').indexOf('/h5/account-h5/auth/scan-web') < 0) return;
  var inject = {
    postMessage: function (raw) {
      var msg = typeof raw === 'string' ? raw : JSON.stringify(raw);
      try {
        window.flutter_inappwebview.callHandler('scanBridgeMessage', msg);
      } catch (e) {}
    },
    biliCallbackReceived: null,
  };
  window.biliInjectV2 = inject;
  window.biliInject = inject;
  if (window.BiliJsBridge) {
    window.BiliJsBridge.biliInjectV2 = inject;
    window.BiliJsBridge.biliInject = inject;
  }
})();
''';

  static bool isScanWeb(String url) =>
      url.contains('/h5/account-h5/auth/scan-web');

  /// 处理页面发来的一条 bridge 消息, 并把结果回调给页面.
  static Future<void> handle(
    InAppWebViewController controller,
    String rawMsg,
  ) async {
    Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(rawMsg) as Map).cast<String, dynamic>();
    } catch (e) {
      logger.w('H5 bridge 消息解析失败: $e');
      return;
    }
    final method = msg['method'] as String? ?? '';
    final data = (msg['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final callbackId = msg['callbackId'] ?? data['callbackId'];

    // 页面为一条消息可能注册多个回调: callback(通用) / onLoad(数据) /
    // onError 等, 它们的 ID 以 <name>CallbackId 放在 data 里.
    // 页面侧派发逻辑是 callback(n || t): 数据必须作为第一个参数传.
    final callbackIds = <Object>{
      ?callbackId,
      for (final entry in data.entries)
        if (entry.key.endsWith('CallbackId') && entry.value != null)
          entry.value,
    };

    void sendRaw(Object? value) {
      if (callbackIds.isEmpty) return;
      final arg = jsonEncode(value);
      final calls = callbackIds
          .map(
            (id) =>
                'try{window.biliInjectV2.biliCallbackReceived('
                '${jsonEncode(id)}, $arg);}catch(e){}',
          )
          .join(';');
      controller.evaluateJavascript(source: calls);
    }

    // V2 风格: 回 {code, msg, data}, 页面按 code 判定成功.
    void reply(int code, Object? payload, [String? message]) => sendRaw({
      'code': code,
      'msg': message ?? '',
      'data': payload,
    });

    switch (method) {
      case 'global.getAllSupport':
        reply(0, {'methods': _methods});
      case 'global.getContainerInfo':
        reply(0, {
          'mid': _current.isLogin ? _current.mid : 0,
          'statusBarHeight': 24,
          'safeAreaTop': 24,
          'isDarkMode': false,
        });
      case 'net.getCsrf':
        reply(0, {'csrf': _current.isLogin ? _current.csrf : ''});
      case 'ui.currentThemeType':
        reply(0, {'themeType': 'light'});
      case 'global.closeBrowser':
        // 确认登录成功后页面用这个方法关闭自己, 没有单独的完成页.
        reply(0, {});
        Get.back();
        SmartDialog.showToast('已确认登录');
      case 'auth.getUserInfo':
        // 页面用 state === '0' 判断未登录, 否则读 mid/face/userName.
        final account = _current;
        final info = Pref.userInfoCache;
        if (!account.isLogin) {
          sendRaw({'state': '0'});
        } else {
          sendRaw({
            'state': '1',
            'mid': account.mid,
            'face': info?.face ?? '',
            'userName': info?.uname ?? '',
          });
        }
      case 'ability.openScheme':
        // 页面里的"切换账号"会发出 bilibili://account/switch, 官方 App 会
        // 打开原生账号选择; 这里弹出本地的账号选择, 并让页面改用该账号.
        final scheme = data['url'] as String? ?? '';
        reply(0, {});
        if (scheme.contains('account/switch') ||
            scheme.contains('login/switch')) {
          await _switchAccount(controller);
        }
      case final m when m.startsWith('net.request'):
        await _request(controller, method, data, reply);
      default:
        // 其余方法 (导航栏, 上报, scheme) 回空成功, 页面不依赖其数据.
        reply(0, {});
    }
  }

  /// 把 check 的"未扫描/已扫码未确认"状态归一成成功, 让页面继续走确认流程.
  static String _normalizeQrcodeCheck(String text) {
    try {
      final json = jsonDecode(text);
      if (json is Map && (json['code'] == 86101 || json['code'] == 86090)) {
        return jsonEncode({...json, 'code': 0, 'message': 'OK'});
      }
    } catch (_) {
      // 不是 JSON 就原样返回.
    }
    return text;
  }

  /// 让页面改用另一个已登录账号重新确认.
  static Future<void> _switchAccount(InAppWebViewController controller) async {
    final candidates = Accounts.account.values.where((e) => e.isLogin).toSet();
    if (candidates.length <= 1) {
      SmartDialog.showToast('没有其他已登录账号, 请先在登录页添加账号');
      return;
    }
    final context = Get.context;
    if (context == null) return;
    final picked = await showDialog<LoginAccount>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择确认登录的账号'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in candidates)
                ListTile(
                  title: Text('UID ${item.mid}'),
                  subtitle: item.mid == Accounts.main.mid
                      ? const Text('当前账号')
                      : null,
                  onTap: () => Get.back(result: item),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
        ],
      ),
    );
    if (picked == null) return;
    _account = picked;
    // 页面用当前账号查 UID 与 csrf, 切换后重新加载让它读回新的账号.
    await LoginUtils.setWebCookie(picked);
    await controller.reload();
  }

  /// 确认前先用当前账号补一次 check.
  ///
  /// 服务端要求 confirm 紧跟在同一个账号成功的 check 之后, 否则返回
  /// 86100 登录失败请重试; 页面重载或切换账号后, 页面自己那次 check
  /// 可能用的是旧账号, 所以这里按当前账号重新做一遍.
  static Future<void> _prepareCheck(Uri uri) async {
    final qrcodeKey = uri.queryParameters['qrcode_key'];
    if (qrcodeKey == null || qrcodeKey.isEmpty) return;
    final params = <String, dynamic>{
      'qrcode_key': qrcodeKey,
      'csrf': _current.csrf,
    };
    final accessKey = _current.accessKey;
    if (accessKey != null) params['access_key'] = accessKey;
    AppSign.appSign(params);
    await Request().get(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/check',
      queryParameters: params,
      options: Options(
        headers: {'user-agent': BrowserUa.app},
        extra: {'account': _current},
      ),
    );
  }

  static Future<void> _request(
    InAppWebViewController controller,
    String method,
    Map<String, dynamic> data,
    void Function(int code, Object? payload, [String? message]) reply,
  ) async {
    try {
      final url = data['url'] as String? ?? '';
      final httpMethod = (data['method'] as String? ?? 'GET').toUpperCase();
      final headers = (data['header'] as Map?)?.cast<String, dynamic>() ?? {};
      final params = (data['params'] as Map?)?.cast<String, dynamic>() ?? {};
      final body = data['data'];
      final withSign = method.contains('WithSign');

      // passport 的扫码 check/confirm 对非官方通道固定返回 -400 请求错误,
      // 带上 App 签名与 access_key 后才会按真实状态应答. 签名覆盖全部参数
      // (含 csrf), 漏掉任何一个都会让服务端回 -3 签名错误.
      final needSign = withSign || url.contains('passport.bilibili.com');
      final mergedParams = <String, dynamic>{
        ...params,
        ...Uri.parse(url).queryParameters,
      };
      if (needSign) {
        final accessKey = _current.accessKey;
        if (accessKey != null) mergedParams['access_key'] = accessKey;
        AppSign.appSign(mergedParams);
      }
      // 确认前先按当前账号补一次 check, 否则服务端会回 86100.
      if (url.contains('/qrcode/confirm')) {
        await _prepareCheck(Uri.parse(url));
      }
      final options = Options(
        headers: headers.map((k, v) => MapEntry(k, '$v')),
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': _current},
      );
      final query = mergedParams.isEmpty ? null : mergedParams;
      // query 已并入 mergedParams, 请求时用不带查询串的地址, 避免重复.
      final baseUrl = Uri.parse(url).replace(query: '').toString();
      final res = httpMethod == 'GET'
          ? await Request().get(baseUrl, queryParameters: query, options: options)
          : await Request().post(
              baseUrl,
              data: body,
              queryParameters: query,
              options: options,
            );
      var text = res.data is String ? res.data as String : jsonEncode(res.data);
      // check 接口用返回码表达二维码状态: 86101 未扫描, 86090 已扫码未确认.
      // 页面只把 0 当成功, 其它值会直接中断并停在"二维码已扫描未确认",
      // 导致确认按钮不可用 (切换账号后重新加载就会命中). 这里把它们归一成 0,
      // 真实状态仍由后续的 scene 与 confirm 决定.
      if (url.contains('/qrcode/check')) {
        text = _normalizeQrcodeCheck(text);
      }
      final payload = {
        'response': text,
        'httpStatus': res.statusCode ?? 200,
        'headers': res.headers.map.map((k, v) => MapEntry(k, v.join(','))),
      };
      // net.request 走旧版 callNative:
      //   callback 的第一个参数必须严格是字符串 "ok", 否则页面报
      //   "Request callback status is not ok";
      //   onLoad 收到的必须是响应对象本身 (不能再套一层 JSON 字符串).
      final onLoadId = data['onLoadCallbackId'];
      final callbackOnly = data['callbackId'];
      if (onLoadId != null || callbackOnly != null) {
        final script = <String>[
          if (callbackOnly != null)
            "try{window.biliInjectV2.biliCallbackReceived("
                "${jsonEncode(callbackOnly)}, 'ok');}catch(e){}",
          if (onLoadId != null)
            'try{window.biliInjectV2.biliCallbackReceived('
                '${jsonEncode(onLoadId)}, ${jsonEncode(payload)});}catch(e){}',
        ].join(';');
        controller.evaluateJavascript(source: script);
      } else {
        reply(0, payload);
      }
    } catch (e, s) {
      logger.w('H5 bridge 请求失败: $e', error: e, stackTrace: s);
      reply(-1, null, '$e');
    }
  }
}
