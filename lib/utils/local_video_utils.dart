import 'dart:io';

import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:get_thumbnail_video/get_thumbnail_video.dart'
    show ImageFormat, VideoThumbnail;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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
  bool recursive = true,
  bool ignoreNoMedia = false,
  void Function(LocalVideoItem item)? onItem,
  bool Function()? isCancelled,
}) async {
  final dir = Directory(folderPath);
  if (!dir.existsSync()) {
    logger.d('scanLocalVideos: dir not exists or not accessible: $folderPath');
    return const [];
  }
  final extensions = {...localVideoExtensions, ...customExtensions};
  final items = <LocalVideoItem>[];
  await _scanDirectory(
    dir,
    extensions: extensions,
    includeNoExt: includeNoExt,
    recursive: recursive,
    ignoreNoMedia: ignoreNoMedia,
    onItem: (item) {
      items.add(item);
      onItem?.call(item);
    },
    isCancelled: isCancelled,
  );
  items.sort((a, b) => a.name.compareTo(b.name));
  logger.d('scanLocalVideos: found ${items.length} videos in $folderPath');
  return items;
}

/// 手动递归遍历目录, 支持 .nomedia 跳过、增量回调与取消.
Future<void> _scanDirectory(
  Directory dir, {
  required Set<String> extensions,
  required bool includeNoExt,
  required bool recursive,
  required bool ignoreNoMedia,
  required void Function(LocalVideoItem item) onItem,
  required bool Function()? isCancelled,
}) async {
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (isCancelled?.call() ?? false) {
        return;
      }
      if (entity is File) {
        final name = path.basename(entity.path);
        final ext = path.extension(name).toLowerCase().replaceFirst('.', '');
        final isNoExt = ext.isEmpty && !name.startsWith('.');
        if (!extensions.contains(ext) && !(includeNoExt && isNoExt)) {
          continue;
        }
        try {
          final stat = entity.statSync();
          onItem(
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
      } else if (entity is Directory) {
        if (recursive && (ignoreNoMedia || !_hasNoMedia(entity))) {
          await _scanDirectory(
            entity,
            extensions: extensions,
            includeNoExt: includeNoExt,
            recursive: recursive,
            ignoreNoMedia: ignoreNoMedia,
            onItem: onItem,
            isCancelled: isCancelled,
          );
        }
      }
    }
  } catch (e) {
    // 目录遍历失败 (例如无权限子目录) 时保留已扫描结果.
    logger.d('scanLocalVideos: list failed for ${dir.path}: $e');
  }
}

/// 目录是否包含 .nomedia 标记文件.
bool _hasNoMedia(Directory dir) {
  try {
    return File(path.join(dir.path, '.nomedia')).existsSync();
  } catch (_) {
    return false;
  }
}

/// 扫描一组文件夹, 汇总为媒体库文件夹列表.
Future<List<LocalVideoFolder>> scanLocalFolders(
  List<String> folderPaths,
  {
  Set<String> customExtensions = const {},
  bool includeNoExt = false,
  bool recursive = true,
  bool ignoreNoMedia = false,
}
) async {
  final folders = <LocalVideoFolder>[];
  for (final folderPath in folderPaths) {
    final videos = await scanLocalVideos(
      folderPath,
      customExtensions: customExtensions,
      includeNoExt: includeNoExt,
      recursive: recursive,
      ignoreNoMedia: ignoreNoMedia,
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

/// 生成或获取视频缩略图文件路径, 失败时返回 null.
Future<String?> getVideoThumbnail(LocalVideoItem item) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final thumbDir = Directory(path.join(tempDir.path, 'local_video_thumbs'));
    await thumbDir.create(recursive: true);
    final thumbPath = path.join(thumbDir.path, '${item.fakeCid}.jpg');
    if (File(thumbPath).existsSync()) {
      return thumbPath;
    }
    final result = await VideoThumbnail.thumbnailFile(
      video: item.path,
      thumbnailPath: thumbPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 320,
      quality: 75,
    );
    return result.path;
  } catch (e) {
    logger.d('getVideoThumbnail: failed for ${item.path}: $e');
    return null;
  }
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
