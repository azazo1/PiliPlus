import 'dart:io';

import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:path/path.dart' as path;

/// 本地视频库支持的视频扩展名.
const Set<String> localVideoExtensions = {
  'mp4',
  'mkv',
  'webm',
  'avi',
  'flv',
  'mov',
  'm4v',
  'ts',
  '3gp',
  'mpg',
  'mpeg',
};

/// 递归扫描文件夹下的视频文件, 按文件名排序.
Future<List<LocalVideoItem>> scanLocalVideos(String folderPath) async {
  final dir = Directory(folderPath);
  if (!dir.existsSync()) {
    return const [];
  }
  final items = <LocalVideoItem>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final name = path.basename(entity.path);
    final ext = path.extension(name).toLowerCase().replaceFirst('.', '');
    if (!localVideoExtensions.contains(ext)) {
      continue;
    }
    try {
      final stat = entity.statSync();
      items.add(
        LocalVideoItem(
          path: entity.path,
          name: name,
          folderPath: path.dirname(entity.path),
          size: stat.size,
          lastModified: stat.modified,
        ),
      );
    } catch (_) {
      // 单个文件读取失败时跳过, 不中断整个扫描.
    }
  }
  items.sort((a, b) => a.name.compareTo(b.name));
  return items;
}

/// 扫描一组文件夹, 汇总为媒体库文件夹列表.
Future<List<LocalVideoFolder>> scanLocalFolders(
  List<String> folderPaths,
) async {
  final folders = <LocalVideoFolder>[];
  for (final folderPath in folderPaths) {
    final videos = await scanLocalVideos(folderPath);
    folders.add(
      LocalVideoFolder(
        path: folderPath,
        name: _folderName(folderPath),
        videoCount: videos.length,
      ),
    );
  }
  return folders;
}

String _folderName(String folderPath) {
  final name = path.basename(folderPath);
  return name.isEmpty ? folderPath : name;
}

/// 计算文件夹内播放列表的下一项索引, 支持列表循环.
int? nextLocalVideoIndex(int current, int length, {required bool listCycle}) {
  final next = current + 1;
  if (next < length) {
    return next;
  }
  return listCycle && length > 1 ? 0 : null;
}

/// 计算文件夹内播放列表的上一项索引.
int? prevLocalVideoIndex(int current, int length) {
  final prev = current - 1;
  return prev >= 0 ? prev : null;
}

/// 文件大小的人类可读格式, 如 `1.5 MB`.
String formatLocalFileSize(int bytes) {
  if (bytes <= 0) {
    return '';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = unit == 0 || size >= 100 ? 0 : 1;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}
