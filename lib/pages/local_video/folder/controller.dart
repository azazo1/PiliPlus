import 'package:PiliPlus/http/loading_state.dart';
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
  final items = Rx<LoadingState<List<LocalVideoItem>>>(
    LoadingState.loading(),
  );

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
    items.value = LoadingState.loading();
    final customExtensions =
        (GStorage.setting.get(SettingBoxKey.localVideoExts) as List?)
            ?.fromCast<String>() ??
        const <String>[];
    final includeNoExt =
        GStorage.setting.get(SettingBoxKey.localVideoNoExt) == true;
    items.value = Success(
      await scanLocalVideos(
        folderPath,
        customExtensions: customExtensions.toSet(),
        includeNoExt: includeNoExt,
      ),
    );
  }

  /// 打开视频详情页播放.
  void openVideo(int index) {
    final list = items.value.dataOrNull;
    if (list == null || index >= list.length) {
      return;
    }
    final item = list[index];
    Get.toNamed(
      '/videoV',
      arguments: {
        'videoType': VideoType.ugc,
        'sourceType': SourceType.localFile,
        'localVideoItems': list,
        'localVideoIndex': index,
        'title': item.name,
        'heroTag': Utils.makeHeroTag(item.fakeCid),
        'aid': item.fakeAid,
        'bvid': item.fakeBvid,
        'cid': item.fakeCid,
      },
    );
  }
}
