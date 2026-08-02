import 'dart:io';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/pages/video/introduction/local_file/controller.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/local_video_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class LocalFileIntroPanel extends StatefulWidget {
  const LocalFileIntroPanel({super.key, required this.heroTag});

  final String heroTag;

  @override
  State<LocalFileIntroPanel> createState() => _LocalFileIntroPanelState();
}

class _LocalFileIntroPanelState extends State<LocalFileIntroPanel>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final _controller = Get.find<LocalFileIntroController>(
    tag: widget.heroTag,
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Obx(() {
      final currIndex = _controller.index.value;
      return SliverFixedExtentList.builder(
        itemCount: _controller.list.length,
        itemExtent: localFileItemExtent,
        itemBuilder: (context, index) {
          final item = _controller.list[index];
          return _buildItem(theme, currIndex == index, index, item);
        },
      );
    });
  }

  Widget _buildItem(
    ThemeData theme,
    bool isCurr,
    int index,
    LocalVideoItem item,
  ) {
    final sizeText = formatLocalFileSize(item.size);
    final timeText = DateFormatUtils.format(
      item.lastModified.millisecondsSinceEpoch ~/ 1000,
    );
    final secondary = [
      if (sizeText.isNotEmpty) sizeText,
      if (timeText.isNotEmpty) timeText,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            if (isCurr) {
              return;
            }
            _controller.playIndex(index, item: item);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              spacing: 12,
              children: [
                _LocalVideoThumb(item: item, showPlaying: isCurr),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: theme.textTheme.bodyMedium?.fontSize,
                          height: 1.42,
                          color: isCurr ? theme.colorScheme.primary : null,
                          fontWeight: isCurr ? FontWeight.bold : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 本地视频选集底部面板.
class LocalFileEpisodeSheet extends StatefulWidget {
  const LocalFileEpisodeSheet({super.key, required this.heroTag});

  final String heroTag;

  @override
  State<LocalFileEpisodeSheet> createState() => _LocalFileEpisodeSheetState();
}

class _LocalFileEpisodeSheetState extends State<LocalFileEpisodeSheet> {
  late final _controller = Get.find<LocalFileIntroController>(
    tag: widget.heroTag,
  );
  final _scrollCtr = ScrollController();

  @override
  void dispose() {
    _scrollCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          _buildToolbar(theme),
          Expanded(
            child: Obx(() {
              final currIndex = _controller.index.value;
              return ListView.builder(
                controller: _scrollCtr,
                padding: EdgeInsets.only(
                  top: 7,
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
                ),
                itemCount: _controller.list.length,
                itemBuilder: (context, index) {
                  final item = _controller.list[index];
                  return _buildItem(
                    theme,
                    currIndex == index,
                    index,
                    item,
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('选集', style: theme.textTheme.titleMedium),
          ),
          iconButton(
            iconSize: 22,
            tooltip: '跳至顶部',
            icon: const Icon(Icons.vertical_align_top),
            onPressed: () {
              _scrollCtr.animateTo(
                0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            },
          ),
          iconButton(
            iconSize: 22,
            tooltip: '跳至底部',
            icon: const Icon(Icons.vertical_align_bottom),
            onPressed: () {
              if (_scrollCtr.hasClients) {
                _scrollCtr.animateTo(
                  _scrollCtr.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            },
          ),
          iconButton(
            iconSize: 22,
            tooltip: '跳至当前',
            icon: const Icon(Icons.my_location),
            onPressed: () {
              final index = _controller.index.value;
              if (index >= 0) {
                _scrollCtr.animateTo(
                  index * 112.0 + 7,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            },
          ),
          iconButton(
            iconSize: 22,
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: () => Get.back(),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    ThemeData theme,
    bool isCurr,
    int index,
    LocalVideoItem item,
  ) {
    final sizeText = formatLocalFileSize(item.size);
    final timeText = DateFormatUtils.format(
      item.lastModified.millisecondsSinceEpoch ~/ 1000,
    );
    final secondary = [
      if (sizeText.isNotEmpty) sizeText,
      if (timeText.isNotEmpty) timeText,
    ].join(' · ');
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: 110,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () {
              if (isCurr) {
                return;
              }
              SmartDialog.showToast('切换到:$item.name');
              Get.back();
              _controller.playIndex(index, item: item);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Style.safeSpace,
                vertical: 5,
              ),
              child: Row(
                spacing: 10,
                children: [
                  SizedBox(
                    width: 36,
                    child: isCurr
                        ? Image.asset(
                            Assets.livingStatic,
                            color: primary,
                            height: 12,
                            semanticLabel: '正在播放',
                          )
                        : Text(
                            (index + 1).toString().padLeft(2, '0'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontSize: theme.textTheme.bodyMedium!.fontSize,
                              height: 1.42,
                              letterSpacing: 0.3,
                              fontWeight: isCurr ? FontWeight.bold : null,
                              color: isCurr ? primary : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          secondary,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 本地视频缩略图, 异步生成并缓存.
class _LocalVideoThumb extends StatefulWidget {
  const _LocalVideoThumb({
    required this.item,
    this.width = 96,
    this.height = 60,
    this.showPlaying = false,
  });

  final LocalVideoItem item;
  final double width;
  final double height;
  final bool showPlaying;

  @override
  State<_LocalVideoThumb> createState() => _LocalVideoThumbState();
}

class _LocalVideoThumbState extends State<_LocalVideoThumb> {
  late final Future<String?> _future = getVideoThumbnail(widget.item);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<String?>(
              future: _future,
              builder: (context, snapshot) {
                final thumbPath = snapshot.data;
                if (thumbPath != null && File(thumbPath).existsSync()) {
                  return Image.file(
                    File(thumbPath),
                    fit: BoxFit.cover,
                    cacheWidth: widget.width.round(),
                    errorBuilder: (_, _, _) => _placeholder(theme),
                  );
                }
                return _placeholder(theme);
              },
            ),
            if (widget.showPlaying)
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie_outlined,
        size: 22,
        color: theme.colorScheme.outline,
      ),
    );
  }
}
