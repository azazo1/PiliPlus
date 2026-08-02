import 'dart:io' show Platform;

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
import 'package:path/path.dart' as path;

class LocalVideoPageController extends GetxController {
  /// 媒体库文件夹列表及其扫描结果.
  final folders = RxList<LocalVideoFolder>([]);

  /// 是否正在扫描.
  final isScanning = false.obs;

  /// 扫描版本号, 递增以取消进行中的扫描.
  int _scanVersion = 0;

  final _dirs = <String>[];
  List<String> get dirs => List.unmodifiable(_dirs);

  /// 用户自定义的视频扩展名.
  final exts = RxList<String>([]);

  /// 是否把无扩展名的文件也视为视频.
  final includeNoExt = false.obs;

  /// 是否递归扫描子文件夹.
  final subFolders = true.obs;

  /// 是否跳过带 .nomedia 标记的目录.
  final noMedia = true.obs;

  @override
  void onInit() {
    super.onInit();
    _dirs.addAll(_loadDirs());
    exts.addAll(_loadExts());
    includeNoExt.value = _loadNoExt();
    subFolders.value = _loadSubFolders();
    noMedia.value = _loadNoMedia();
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

  bool _loadSubFolders() =>
      GStorage.setting.get(SettingBoxKey.localVideoSubFolders) != false;

  void _saveSubFolders(bool value) {
    GStorage.setting.put(SettingBoxKey.localVideoSubFolders, value);
  }

  bool _loadNoMedia() =>
      GStorage.setting.get(SettingBoxKey.localVideoNoMedia) != false;

  void _saveNoMedia(bool value) {
    GStorage.setting.put(SettingBoxKey.localVideoNoMedia, value);
  }

  Future<void> onRefresh() async {
    final version = ++_scanVersion;
    isScanning.value = true;
    folders.value = [
      for (final dirPath in _dirs)
        LocalVideoFolder(
          path: dirPath,
          name: _folderName(dirPath),
          videoCount: 0,
        ),
    ];
    for (var i = 0; i < folders.length; i++) {
      if (version != _scanVersion) {
        break;
      }
      final videos = await scanLocalVideos(
        folders[i].path,
        customExtensions: exts.toSet(),
        includeNoExt: includeNoExt.value,
        recursive: subFolders.value,
        ignoreNoMedia: noMedia.value,
        isCancelled: () => version != _scanVersion,
      );
      if (version != _scanVersion) {
        break;
      }
      folders[i] = LocalVideoFolder(
        path: folders[i].path,
        name: folders[i].name,
        videoCount: videos.length,
      );
    }
    isScanning.value = false;
  }

  String _folderName(String dirPath) {
    final name = path.basename(dirPath);
    return name.isEmpty ? dirPath : name;
  }

  /// 保存媒体库选项并重新扫描.
  void saveLibraryOptions({
    required String extInput,
    required bool includeNoExt,
    required bool subFolders,
    required bool noMedia,
  }) {
    final parsed = parseCustomVideoExtensions(extInput).toList()..sort();
    exts.value = parsed;
    _saveExts(parsed);
    this.includeNoExt.value = includeNoExt;
    _saveNoExt(includeNoExt);
    this.subFolders.value = subFolders;
    _saveSubFolders(subFolders);
    this.noMedia.value = noMedia;
    _saveNoMedia(noMedia);
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
    _scanVersion++;
    _dirs.remove(path);
    _saveDirs();
    onRefresh();
  }

  @override
  void onClose() {
    _scanVersion++;
    super.onClose();
  }
}
