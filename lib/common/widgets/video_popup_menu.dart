import 'package:PiliPlus/common/widgets/video_dislike_action.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/models_new/space/space_archive/item.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/video/ai_conclusion/view.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class _VideoCustomAction {
  final String title;
  final Widget icon;
  final VoidCallback onTap;
  const _VideoCustomAction(this.title, this.icon, this.onTap);
}

class VideoPopupMenu extends StatelessWidget {
  final double? iconSize;
  final double menuItemHeight;
  final BaseSimpleVideoItemModel videoItem;
  final VoidCallback? onRemove;

  const VideoPopupMenu({
    super.key,
    required this.iconSize,
    required this.videoItem,
    this.onRemove,
    this.menuItemHeight = 45,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert_outlined,
        color: Theme.of(context).colorScheme.outline,
        size: iconSize,
      ),
      position: PopupMenuPosition.under,
      itemBuilder: (context) =>
          [
                if (videoItem.bvid?.isNotEmpty == true) ...[
                  _VideoCustomAction(
                    videoItem.bvid!,
                    const Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(MdiIcons.identifier, size: 16),
                        Icon(MdiIcons.circleOutline, size: 16),
                      ],
                    ),
                    () => Utils.copyText(videoItem.bvid!),
                  ),
                  _VideoCustomAction(
                    '稍后再看',
                    const Icon(MdiIcons.clockTimeEightOutline, size: 16),
                    () => UserHttp.toViewLater(bvid: videoItem.bvid),
                  ),
                  if (videoItem.cid != null && Pref.enableAi)
                    _VideoCustomAction(
                      'AI总结',
                      const Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Icon(Icons.circle_outlined, size: 16),
                          ExcludeSemantics(
                            child: Text(
                              'AI',
                              style: TextStyle(
                                fontSize: 10,
                                height: 1,
                                fontWeight: FontWeight.w700,
                              ),
                              strutStyle: StrutStyle(
                                fontSize: 10,
                                height: 1,
                                leading: 0,
                                fontWeight: FontWeight.w700,
                              ),
                              textScaler: TextScaler.noScaling,
                            ),
                          ),
                        ],
                      ),
                      () async {
                        final res = await UgcIntroController.getAiConclusion(
                          videoItem.bvid!,
                          videoItem.cid!,
                          videoItem.owner.mid,
                        );
                        if (res != null && context.mounted) {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              child: Padding(
                                padding: const .symmetric(vertical: 14),
                                child: AiConclusionPanel.buildContent(
                                  context,
                                  Theme.of(context),
                                  res,
                                  tap: false,
                                ),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                ],
                if (videoItem is! SpaceArchiveItem) ...[
                  _VideoCustomAction(
                    '访问：${videoItem.owner.name}',
                    const Icon(MdiIcons.accountCircleOutline, size: 16),
                    () => Get.toNamed('/member?mid=${videoItem.owner.mid}'),
                  ),
                  _VideoCustomAction(
                    '不感兴趣',
                    const Icon(MdiIcons.thumbDownOutline, size: 16),
                    () => showVideoDislikeDialog(
                      context,
                      videoItem: videoItem,
                      onRemove: onRemove,
                    ),
                  ),
                  _VideoCustomAction(
                    '拉黑：${videoItem.owner.name}',
                    const Icon(MdiIcons.cancel, size: 16),
                    () => showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('提示'),
                          content: Text(
                            '确定拉黑:${videoItem.owner.name}(${videoItem.owner.mid})?'
                            '\n\n注：被拉黑的Up可以在隐私设置-黑名单管理中解除',
                          ),
                          actions: [
                            TextButton(
                              onPressed: Get.back,
                              child: Text(
                                '点错了',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outline,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                Get.back();
                                final res = await VideoHttp.relationMod(
                                  mid: videoItem.owner.mid!,
                                  act: 5,
                                  reSrc: 11,
                                );
                                if (res.isSuccess) {
                                  onRemove?.call();
                                } else {
                                  res.toast();
                                }
                              },
                              child: const Text('确认'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                _VideoCustomAction(
                  "${MineController.anonymity.value ? '退出' : '进入'}无痕模式",
                  MineController.anonymity.value
                      ? const Icon(MdiIcons.incognitoOff, size: 16)
                      : const Icon(MdiIcons.incognito, size: 16),
                  MineController.onChangeAnonymity,
                ),
              ]
              .map(
                (e) => PopupMenuItem(
                  height: menuItemHeight,
                  onTap: e.onTap,
                  child: Row(
                    children: [
                      e.icon,
                      const SizedBox(width: 6),
                      Text(e.title, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}
