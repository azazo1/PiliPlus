import 'package:PiliPlus/models/common/video/source_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/local_video_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:get/get.dart';

class LocalVideoFolderController extends GetxController {
  /// 扫描到的视频, 增量追加.
  final items = RxList<LocalVideoItem>([]);

  /// 是否正在扫描.
  final isScanning = false.obs;

  /// 扫描版本号, 递增以取消进行中的扫描.
  int _scanVersion = 0;

  late final String folderPath;
  late final String folderName;

  @override
  void onInit() {
    super.onInit();
    folderPath = Get.arguments['folderPath'];
    folderName = Get.arguments['folderName'];
    onRefresh();
  }

  Future<void> onRefresh() async {
    final version = ++_scanVersion;
    isScanning.value = true;
    items.clear();
    final customExtensions =
        (GStorage.setting.get(SettingBoxKey.localVideoExts) as List?)
            ?.fromCast<String>() ??
        const <String>[];
    final includeNoExt =
        GStorage.setting.get(SettingBoxKey.localVideoNoExt) == true;
    final subFolders =
        GStorage.setting.get(SettingBoxKey.localVideoSubFolders) != false;
    final noMedia =
        GStorage.setting.get(SettingBoxKey.localVideoNoMedia) != false;
    await scanLocalVideos(
      folderPath,
      customExtensions: customExtensions.toSet(),
      includeNoExt: includeNoExt,
      recursive: subFolders,
      ignoreNoMedia: !noMedia,
      onItem: (item) {
        if (version == _scanVersion) {
          items.add(item);
        }
      },
      isCancelled: () => version != _scanVersion,
    );
    isScanning.value = false;
  }

  /// 打开视频详情页播放.
  void openVideo(int index) {
    if (index >= items.length) {
      return;
    }
    final item = items[index];
    Get.toNamed(
      '/videoV',
      arguments: {
        'videoType': VideoType.ugc,
        'sourceType': SourceType.localFile,
        'localVideoItems': items.toList(),
        'localVideoIndex': index,
        'title': item.name,
        'heroTag': Utils.makeHeroTag(item.fakeCid),
        'aid': item.fakeAid,
        'bvid': item.fakeBvid,
        'cid': item.fakeCid,
      },
    );
  }

  @override
  void onClose() {
    _scanVersion++;
    super.onClose();
  }
}
