import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/pages/local_video/controller.dart';
import 'package:PiliPlus/pages/local_video/folder/view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class LocalVideoPage extends StatefulWidget {
  const LocalVideoPage({super.key});

  @override
  State<LocalVideoPage> createState() => _LocalVideoPageState();
}

class _LocalVideoPageState extends State<LocalVideoPage> {
  late final _controller = Get.put(LocalVideoPageController());

  @override
  void dispose() {
    Get.delete<LocalVideoPageController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地视频'),
        actions: [
          IconButton(
            tooltip: '自定义后缀',
            onPressed: _showExtDialog,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: '添加文件夹',
            onPressed: _controller.addFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Obx(() => switch (_controller.folders.value) {
        Error(:final errMsg) => Center(
          child: Text(errMsg ?? '加载失败', style: theme.textTheme.bodyMedium),
        ),
        Success(:final response) => response.isEmpty
            ? _buildEmpty(theme)
            : _buildList(theme, response),
        _ => const Center(child: CircularProgressIndicator()),
      }),
    );
  }

  /// 编辑自定义视频扩展名.
  Future<void> _showExtDialog() async {
    final controller = TextEditingController(
      text: _controller.exts.join(', '),
    );
    var includeNoExt = _controller.includeNoExt.value;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('自定义视频后缀'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '把视频文件改名为这些后缀后也会被识别, 多个后缀用逗号或空格分隔',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '例如: pdf, bin, myvid',
                ),
              ),
              CheckboxListTile(
                value: includeNoExt,
                onChanged: (value) {
                  setState(() => includeNoExt = value ?? false);
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '包含无后缀文件',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Get.back(result: controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      _controller.saveLibraryOptions(
        result,
        includeNoExt: includeNoExt,
      );
    }
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            MdiIcons.folderPlayOutline,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '媒体库为空, 点击右上角添加文件夹',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme, List<LocalVideoFolder> folders) {
    return RefreshIndicator(
      onRefresh: _controller.onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          return ListTile(
            leading: Icon(
              MdiIcons.folderPlayOutline,
              size: 28,
              color: theme.colorScheme.primary,
            ),
            title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${folder.videoCount} 个视频\n${folder.path}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Get.toNamed(
                '/localVideoFolder',
                arguments: {
                  'folderPath': folder.path,
                  'folderName': folder.name,
                },
              );
            },
            trailing: IconButton(
              tooltip: '移除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirm = await showConfirmDialog(
                  context: context,
                  title: const Text('从媒体库移除该文件夹?'),
                  content: const Text('不会删除磁盘上的文件'),
                );
                if (confirm) {
                  _controller.removeFolder(folder.path);
                }
              },
            ),
          );
        },
      ),
    );
  }
}
