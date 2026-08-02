import 'dart:io';

import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/pages/local_video/folder/controller.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/local_video_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LocalVideoFolderPage extends StatefulWidget {
  const LocalVideoFolderPage({super.key});

  @override
  State<LocalVideoFolderPage> createState() => _LocalVideoFolderPageState();
}

class _LocalVideoFolderPageState extends State<LocalVideoFolderPage> {
  late final _controller = Get.put(LocalVideoFolderController());

  /// 缩略图生成结果缓存, 避免列表重建时重复生成.
  final _thumbCache = <String, Future<String?>>{};

  @override
  void dispose() {
    Get.delete<LocalVideoFolderController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_controller.folderName)),
      body: Obx(() {
        if (_controller.items.isEmpty && _controller.isScanning.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            if (_controller.isScanning.value)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _controller.items.isEmpty
                  ? Center(
                      child: Text(
                        '该文件夹下没有视频',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _controller.onRefresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _controller.items.length,
                        itemBuilder: (context, index) {
                          final item = _controller.items[index];
                          return _buildItem(theme, index, item);
                        },
                      ),
                    ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildItem(ThemeData theme, int index, LocalVideoItem item) {
    final sizeText = formatLocalFileSize(item.size);
    final timeText = DateFormatUtils.format(
      item.lastModified.millisecondsSinceEpoch ~/ 1000,
    );
    final secondary = [
      if (sizeText.isNotEmpty) sizeText,
      if (timeText.isNotEmpty) timeText,
    ].join(' · ');
    return InkWell(
      onTap: () => _controller.openVideo(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            _buildThumb(theme, item),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 3),
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
    );
  }

  Widget _buildThumb(ThemeData theme, LocalVideoItem item) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 96,
        height: 60,
        child: FutureBuilder<String?>(
          future: _thumbCache.putIfAbsent(
            item.path,
            () => getVideoThumbnail(item),
          ),
          builder: (context, snapshot) {
            final thumbPath = snapshot.data;
            if (thumbPath != null && File(thumbPath).existsSync()) {
              return Image.file(
                File(thumbPath),
                fit: BoxFit.cover,
                cacheWidth: 96,
                errorBuilder: (_, _, _) => _buildThumbPlaceholder(theme),
              );
            }
            return _buildThumbPlaceholder(theme);
          },
        ),
      ),
    );
  }

  Widget _buildThumbPlaceholder(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie_outlined,
        size: 28,
        color: theme.colorScheme.outline,
      ),
    );
  }
}
