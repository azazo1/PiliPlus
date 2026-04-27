import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

bool canShowVideoDislike({
  BaseSimpleVideoItemModel? videoItem,
  String? bvid,
}) {
  return videoItem?.bvid?.isNotEmpty == true || bvid?.isNotEmpty == true;
}

Future<void> showVideoDislikeDialog(
  BuildContext context, {
  BaseSimpleVideoItemModel? videoItem,
  String? bvid,
  VoidCallback? onRemove,
}) async {
  final dislikeBvid = videoItem?.bvid ?? bvid;
  if (videoItem case final RcmdVideoItemAppModel item) {
    final accessKey = Accounts.get(AccountType.recommend).accessKey;
    if (accessKey == null || accessKey.isEmpty) {
      SmartDialog.showToast('请退出账号后重新登录');
      return;
    }
    final tp = item.threePoint;
    if (tp == null) {
      SmartDialog.showToast('未能获取threePoint');
      return;
    }
    if (tp.dislikeReasons == null && tp.feedbacks == null) {
      SmartDialog.showToast('未能获取dislikeReasons或feedbacks');
      return;
    }

    Widget actionButton(Reason? reason, Reason? feedback) {
      return SearchText(
        text: reason?.name ?? feedback?.name ?? '未知',
        onTap: (_) async {
          Get.back();
          SmartDialog.showLoading(msg: '正在提交');
          final res = await VideoHttp.feedDislike(
            reasonId: reason?.id,
            feedbackId: feedback?.id,
            id: item.param!,
            goto: item.goto!,
          );
          SmartDialog.dismiss();
          if (res.isSuccess) {
            SmartDialog.showToast(reason?.toast ?? feedback!.toast!);
            onRemove?.call();
          } else {
            res.toast();
          }
        },
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tp.dislikeReasons != null) ...[
                  const Text('我不想看'),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: tp.dislikeReasons!.map((item) {
                      return actionButton(item, null);
                    }).toList(),
                  ),
                ],
                if (tp.feedbacks != null) ...[
                  const SizedBox(height: 5),
                  const Text('反馈'),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: tp.feedbacks!.map((item) {
                      return actionButton(null, item);
                    }).toList(),
                  ),
                ],
                const Divider(),
                Center(
                  child: FilledButton.tonal(
                    onPressed: () async {
                      SmartDialog.showLoading(msg: '正在提交');
                      final res = await VideoHttp.feedDislikeCancel(
                        id: item.param!,
                        goto: item.goto!,
                      );
                      SmartDialog.dismiss();
                      SmartDialog.showToast(
                        res.isSuccess ? '成功' : res.toString(),
                      );
                      Get.back();
                    },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('撤销'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return;
  }

  if (dislikeBvid?.isNotEmpty != true) {
    SmartDialog.showToast('未能获取bvid');
    return;
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      content: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 5),
            const Text('当前视频支持点踩与撤销'),
            const SizedBox(height: 5),
            Wrap(
              spacing: 5.0,
              runSpacing: 2.0,
              children: [
                FilledButton.tonal(
                  onPressed: () async {
                    Get.back();
                    SmartDialog.showLoading(msg: '正在提交');
                    final res = await VideoHttp.dislikeVideo(
                      bvid: dislikeBvid!,
                      type: true,
                    );
                    SmartDialog.dismiss();
                    if (res.isSuccess) {
                      SmartDialog.showToast('点踩成功');
                      onRemove?.call();
                    } else {
                      res.toast();
                    }
                  },
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('点踩'),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    Get.back();
                    SmartDialog.showLoading(msg: '正在提交');
                    final res = await VideoHttp.dislikeVideo(
                      bvid: dislikeBvid!,
                      type: false,
                    );
                    SmartDialog.dismiss();
                    SmartDialog.showToast(
                      res.isSuccess ? '取消踩' : res.toString(),
                    );
                  },
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('撤销'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
