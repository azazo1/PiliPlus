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
    return ListTile(
      leading: Icon(
        Icons.play_circle_outline,
        size: 32,
        color: theme.colorScheme.primary,
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _controller.openVideo(index),
    );
  }
}
