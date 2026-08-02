import 'dart:io';

import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/services/logger.dart';
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
Future<List<LocalVideoItem>> scanLocalVideos(
  String folderPath, {
  Set<String> customExtensions = const {},
  bool includeNoExt = false,
}) async {
  final dir = Directory(folderPath);
  if (!dir.existsSync()) {
    logger.d('scanLocalVideos: dir not exists or not accessible: $folderPath');
    return const [];
  }
  final extensions = {...localVideoExtensions, ...customExtensions};
  final items = <LocalVideoItem>[];
  try {
    await for (final entity in dir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final name = path.basename(entity.path);
      final ext = path.extension(name).toLowerCase().replaceFirst('.', '');
      final isNoExt = ext.isEmpty && !name.startsWith('.');
      if (!extensions.contains(ext) && !(includeNoExt && isNoExt)) {
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
      } catch (e) {
        // 单个文件读取失败时跳过, 不中断整个扫描.
        logger.d('scanLocalVideos: stat failed for ${entity.path}: $e');
      }
    }
  } catch (e) {
    // 目录遍历失败 (例如无权限子目录) 时保留已扫描结果.
    logger.d('scanLocalVideos: list failed for $folderPath: $e');
  }
  items.sort((a, b) => a.name.compareTo(b.name));
  logger.d('scanLocalVideos: found ${items.length} videos in $folderPath');
  return items;
}

/// 扫描一组文件夹, 汇总为媒体库文件夹列表.
Future<List<LocalVideoFolder>> scanLocalFolders(
  List<String> folderPaths,
  {
  Set<String> customExtensions = const {},
  bool includeNoExt = false,
}
) async {
  final folders = <LocalVideoFolder>[];
  for (final folderPath in folderPaths) {
    final videos = await scanLocalVideos(
      folderPath,
      customExtensions: customExtensions,
      includeNoExt: includeNoExt,
    );
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

/// 解析用户输入的自定义扩展名, 支持逗号/空格/换行分隔, 自动去点转小写.
Set<String> parseCustomVideoExtensions(String input) {
  final exts = <String>{};
  for (final part in input.split(RegExp(r'[,\s]+'))) {
    final ext = part.trim().toLowerCase().replaceFirst(RegExp(r'^\.+'), '');
    if (ext.isNotEmpty) {
      exts.add(ext);
    }
  }
  return exts;
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
