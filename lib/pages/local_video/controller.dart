import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/local_video_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class LocalVideoPageController extends GetxController {
  /// 媒体库文件夹列表及其扫描结果.
  final folders = Rx<LoadingState<List<LocalVideoFolder>>>(
    LoadingState.loading(),
  );

  final _dirs = <String>[];
  List<String> get dirs => List.unmodifiable(_dirs);

  @override
  void onInit() {
    super.onInit();
    _dirs.addAll(_loadDirs());
    onRefresh();
  }

  List<String> _loadDirs() =>
      (GStorage.setting.get(SettingBoxKey.localVideoDirs) as List?)
          ?.fromCast<String>() ??
      const [];

  void _saveDirs() {
    GStorage.setting.put(SettingBoxKey.localVideoDirs, List.of(_dirs));
  }

  Future<void> onRefresh() async {
    folders.value = LoadingState.loading();
    folders.value = Success(await scanLocalFolders(_dirs));
  }

  /// 通过系统目录选择器添加媒体库文件夹.
  Future<void> addFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null || path.isEmpty) {
      return;
    }
    if (_dirs.contains(path)) {
      SmartDialog.showToast('该文件夹已在媒体库中');
      return;
    }
    _dirs.add(path);
    _saveDirs();
    await onRefresh();
  }

  /// 从媒体库移除文件夹, 不删除磁盘文件.
  void removeFolder(String path) {
    _dirs.remove(path);
    _saveDirs();
    onRefresh();
  }
}
