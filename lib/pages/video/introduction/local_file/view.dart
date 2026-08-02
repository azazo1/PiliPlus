import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/pages/video/introduction/local_file/controller.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/local_video_utils.dart';
import 'package:flutter/material.dart';
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
                Icon(
                  isCurr ? Icons.play_circle_fill : Icons.play_circle_outline,
                  size: 36,
                  color: isCurr ? theme.colorScheme.primary : null,
                ),
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
