import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

abstract final class Update {
  // 检查上游更新
  static Future<void> checkUpdate([bool isAuto = true]) async {
    if (kDebugMode) return;
    SmartDialog.dismiss();
    try {
      final res = await Request().get(
        Api.latestApp,
        options: Options(
          headers: {'user-agent': BrowserUa.mob},
          extra: {'account': const NoAccount()},
        ),
      );
      if (res.data is! List || res.data.isEmpty) {
        if (!isAuto) {
          SmartDialog.showToast('检查上游更新失败, GitHub 接口未返回数据, 请检查网络');
        }
        return;
      }
      final Map<String, dynamic> data = Map<String, dynamic>.from(
        res.data[0] as Map,
      );
      final String releaseTag = data['tag_name']?.toString() ?? 'unknown';
      final int latest =
          DateTime.parse(data['created_at'] as String)
                  .millisecondsSinceEpoch ~/
              1000;
      if (BuildConfig.buildTime >= latest) {
        if (!isAuto) {
          SmartDialog.showToast('当前 fork 暂未检测到新的上游 release');
        }
      } else {
        SmartDialog.show(
          animationType: SmartAnimationType.centerFade_otherSlide,
          builder: (context) {
            final colorScheme = ColorScheme.of(context);
            final String releaseBody =
                data['body'] is String &&
                    (data['body'] as String).trim().isNotEmpty
                ? data['body'] as String
                : '暂无 release 说明';
            void openUpstream(String url) {
              SmartDialog.dismiss();
              PageUtils.launchURL(url);
            }
            return AlertDialog(
              title: const Text('发现上游新版本'),
              content: SizedBox(
                height: 320,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        releaseTag,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '当前项目是 fork, 检测到上游 release 后请优先 merge 上游仓库的变更, 而不是直接更新安装包.',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(releaseBody),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => openUpstream(
                          '${Constants.upstreamSourceCodeUrl}/releases/tag/$releaseTag',
                        ),
                        child: Text(
                          '查看上游 release 详情',
                          style: TextStyle(
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => openUpstream(
                          '${Constants.upstreamSourceCodeUrl}/commits/main',
                        ),
                        child: Text(
                          '查看上游 main 分支提交',
                          style: TextStyle(
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (isAuto)
                  TextButton(
                    onPressed: () {
                      SmartDialog.dismiss();
                      GStorage.setting.put(SettingBoxKey.autoUpdate, false);
                    },
                    child: Text(
                      '不再提醒',
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  ),
                TextButton(
                  onPressed: SmartDialog.dismiss,
                  child: Text(
                    '取消',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () => openUpstream(
                    Constants.upstreamSourceCodeUrl,
                  ),
                  child: const Text('前往上游仓库'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
    }
  }
}
