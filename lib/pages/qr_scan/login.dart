import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/login.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

enum _ConfirmType { normal, transient }

/// 扫码登录确认. 官方客户端由 H5 页面在已登录 webview 中完成,
/// 这里用原生对话框调用同样的接口.
abstract final class ScanLogin {
  /// 二维码已失效
  static const _codeExpired = 86038;

  static bool _checkLogin() {
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('请先登录账号再扫码登录');
      return false;
    }
    return true;
  }

  static String get _uname => Pref.userInfoCache?.uname ?? '当前账号';

  static void _toastError(Error res) {
    SmartDialog.showToast(
      res.code == _codeExpired ? '二维码已失效, 请刷新后重新扫描' : '登录失败: ${res.errMsg}',
    );
  }

  /// 网页端二维码
  static Future<void> web(String qrcodeKey) async {
    if (!_checkLogin()) return;

    SmartDialog.showLoading(msg: '获取登录信息...');
    final scene = await LoginHttp.webQrcodeScene(qrcodeKey);
    SmartDialog.dismiss();

    final Map<String, dynamic> data;
    switch (scene) {
      case Error():
        logger.w('扫码登录获取场景失败: ${scene.code} ${scene.errMsg}');
        _toastError(scene);
        return;
      case Success(:final response):
        data = response;
      default:
        return;
    }

    final needVerifyTel = (data['verify_tel'] ?? 0) != 0;
    final envList = data['env_show_list'];
    final needEnv =
        data['obtain_env'] == true && envList is List && envList.isNotEmpty;
    if (needVerifyTel || needEnv) {
      SmartDialog.showToast('本次登录需要额外验证, 请使用官方客户端扫码');
      return;
    }

    final appTitle = (data['app'] as Map?)?['title'] as String?;
    final locationDiff = data['location_diff'] == true;
    final location = data['qrcode_location'] as String?;
    final allowTransient = data['transient'] == true;

    final context = Get.context;
    if (context == null) return;
    final type = await showDialog<_ConfirmType>(
      context: context,
      builder: (context) {
        final colorScheme = ColorScheme.of(context);
        return AlertDialog(
          title: const Text('扫码登录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('将使用 $_uname 登录${appTitle ?? '网页端'}'),
              if (locationDiff) ...[
                const SizedBox(height: 8),
                Text(
                  '异地登录提醒: 登录地点${location?.isNotEmpty == true ? ' $location ' : ''}与当前位置不同, '
                  '请确认是本人操作.',
                  style: TextStyle(color: colorScheme.error),
                ),
              ],
              if (allowTransient) ...[
                const SizedBox(height: 8),
                Text(
                  '非常用设备可选择短期登录, 登录状态仅保持一天.',
                  style: TextStyle(fontSize: 13, color: colorScheme.outline),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '取消',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            if (allowTransient)
              TextButton(
                onPressed: () => Get.back(result: _ConfirmType.transient),
                child: const Text('短期登录'),
              ),
            TextButton(
              onPressed: () => Get.back(result: _ConfirmType.normal),
              child: const Text('确认登录'),
            ),
          ],
        );
      },
    );
    if (type == null) return;

    SmartDialog.showLoading(msg: '正在确认登录...');
    final res = await LoginHttp.webQrcodeConfirm(
      qrcodeKey,
      transient: type == _ConfirmType.transient,
    );
    SmartDialog.dismiss();
    if (res case Error()) {
      logger.w('网页端扫码登录确认失败: ${res.code} ${res.errMsg}');
      _toastError(res);
    } else {
      logger.i('网页端扫码登录已确认');
      SmartDialog.showToast('已确认登录');
    }
  }

  /// TV/HD 端二维码
  static Future<void> tv(String authCode) async {
    if (!_checkLogin()) return;
    final context = Get.context;
    if (context == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫码登录'),
        content: Text('将使用 $_uname 登录 TV/HD 客户端, 请确认是本人操作.'),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('确认登录'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    SmartDialog.showLoading(msg: '正在确认登录...');
    final res = await LoginHttp.tvQrcodeConfirm(authCode);
    SmartDialog.dismiss();
    if (res case Error()) {
      logger.w('TV 端扫码登录确认失败: ${res.code} ${res.errMsg}');
      _toastError(res);
    } else {
      logger.i('TV 端扫码登录已确认');
      SmartDialog.showToast('已确认登录');
    }
  }
}
