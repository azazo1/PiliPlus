import 'package:PiliPlus/utils/id_utils.dart';

/// 本地视频库中的单个视频文件.
class LocalVideoItem {
  final String path;
  final String name;
  final String folderPath;
  final int size;
  final DateTime lastModified;

  const LocalVideoItem({
    required this.path,
    required this.name,
    required this.folderPath,
    required this.size,
    required this.lastModified,
  });

  /// 由路径哈希生成的占位 id, 本地视频不参与任何 B 站请求.
  int get fakeAid => path.hashCode & 0x3fffffff;

  String get fakeBvid => IdUtils.av2bv(fakeAid);

  int get fakeCid => fakeAid;
}

/// 本地视频库中的文件夹.
class LocalVideoFolder {
  final String path;
  final String name;
  final int videoCount;

  const LocalVideoFolder({
    required this.path,
    required this.name,
    required this.videoCount,
  });
}
