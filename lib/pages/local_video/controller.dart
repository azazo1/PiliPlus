import 'dart:io' show Platform;

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/local_video_utils.dart';
import 'package:PiliPlus/utils/permission_handler.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class LocalVideoPageController extends GetxController {
  /// 媒体库文件夹列表及其扫描结果.
  final folders = Rx<LoadingState<List<LocalVideoFolder>>>(
    LoadingState.loading(),
  );

  final _dirs = <String>[];
  List<String> get dirs => List.unmodifiable(_dirs);

  /// 用户自定义的视频扩展名.
  final exts = RxList<String>([]);

  /// 是否把无扩展名的文件也视为视频.
  final includeNoExt = false.obs;

  @override
  void onInit() {
    super.onInit();
    _dirs.addAll(_loadDirs());
    exts.addAll(_loadExts());
    includeNoExt.value = _loadNoExt();
    onRefresh();
  }

  List<String> _loadDirs() =>
      (GStorage.setting.get(SettingBoxKey.localVideoDirs) as List?)
          ?.fromCast<String>() ??
      const [];

  void _saveDirs() {
    GStorage.setting.put(SettingBoxKey.localVideoDirs, List.of(_dirs));
  }

  List<String> _loadExts() =>
      (GStorage.setting.get(SettingBoxKey.localVideoExts) as List?)
          ?.fromCast<String>() ??
      const [];

  void _saveExts(List<String> value) {
    GStorage.setting.put(SettingBoxKey.localVideoExts, value);
  }

  bool _loadNoExt() =>
      GStorage.setting.get(SettingBoxKey.localVideoNoExt) == true;

  void _saveNoExt(bool value) {
    GStorage.setting.put(SettingBoxKey.localVideoNoExt, value);
  }

  Future<void> onRefresh() async {
    folders.value = LoadingState.loading();
    folders.value = Success(
      await scanLocalFolders(
        _dirs,
        customExtensions: exts.toSet(),
        includeNoExt: includeNoExt.value,
      ),
    );
  }

  /// 保存自定义扩展名与无后缀开关并重新扫描.
  void saveLibraryOptions(String input, {required bool includeNoExt}) {
    final parsed = parseCustomVideoExtensions(input).toList()..sort();
    exts.value = parsed;
    _saveExts(parsed);
    this.includeNoExt.value = includeNoExt;
    _saveNoExt(includeNoExt);
    onRefresh();
  }

  /// 通过系统目录选择器添加媒体库文件夹.
  Future<void> addFolder() async {
    if (!await _requestVideoPermission()) {
      return;
    }
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

  /// Android 分区存储下需要视频读取权限才能通过路径扫描媒体文件.
  Future<bool> _requestVideoPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }
    final status = await Permission.videos.request();
    if (status == PermissionStatus.denied ||
        status == PermissionStatus.permanentlyDenied) {
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: const Text('需要视频读取权限才能扫描本地视频'),
          actions: [
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                openAppSettings();
              },
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  /// 从媒体库移除文件夹, 不删除磁盘文件.
  void removeFolder(String path) {
    _dirs.remove(path);
    _saveDirs();
    onRefresh();
  }
}
