import 'package:PiliPlus/models_new/local_video/local_video_item.dart';
import 'package:PiliPlus/models_new/video/video_detail/stat_detail.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/local_video_utils.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:get/get.dart';

/// 本地视频列表面板中单个条目的高度, 用于滚动定位.
const double localFileItemExtent = 112;

class LocalFileIntroController extends CommonIntroController {
  @override
  void queryVideoIntro() {}

  @override
  int get copyright => throw UnimplementedError();

  @override
  void actionLikeVideo() {}

  @override
  void actionShareVideo(context) {}

  @override
  void actionTriple() {}

  @override
  Future<void> actionFavVideo({bool isQuick = false}) async {}

  @override
  (Object, int) get getFavRidType => throw UnimplementedError();

  @override
  StatDetail? getStat() => null;

  @override
  bool get isShowOnlineTotal => false;

  final index = (-1).obs;
  late final RxList<LocalVideoItem> list;

  @override
  void onInit() {
    super.onInit();
    videoDetail.value.title = videoDetailCtr.args['title'];
    list = RxList<LocalVideoItem>.of(
      videoDetailCtr.args['localVideoItems'] as List<LocalVideoItem>,
    );
    final currIndex = videoDetailCtr.args['localVideoIndex'] as int;
    index.value = currIndex;
    if (currIndex != 0) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        try {
          final state = videoDetailCtr.scrollKey.currentState;
          if (state != null && state.mounted) {
            (state.innerController as ExtendedNestedScrollController)
                .nestedPositions
                .first
                .localJumpTo(_offset);
          } else if (videoDetailCtr.introScrollCtr?.hasClients ?? false) {
            videoDetailCtr.introScrollCtr!.jumpTo(_offset);
          }
        } catch (_) {
          if (kDebugMode) rethrow;
        }
      });
    }
  }

  double get _offset => index.value * localFileItemExtent + 7 - 35;

  @override
  bool nextPlay() {
    final next = nextLocalVideoIndex(
      index.value,
      list.length,
      listCycle:
          videoDetailCtr.plPlayerController.playRepeat == PlayRepeat.listCycle,
    );
    if (next != null) {
      playIndex(next);
      return true;
    }
    return false;
  }

  @override
  bool prevPlay() {
    final prev = prevLocalVideoIndex(index.value, list.length);
    if (prev != null) {
      playIndex(prev);
      return true;
    }
    return false;
  }

  void playIndex(int index, {LocalVideoItem? item}) {
    item ??= list[index];
    videoDetailCtr
      ..onReset()
      ..cover.value = ''
      ..aid = item.fakeAid
      ..bvid = item.fakeBvid
      ..cid.value = item.fakeCid
      ..initLocalFileSource(item, isInit: false)
      ..playerInit();
    videoDetail
      ..value.title = item.name
      ..refresh();
    this.index.value = index;
  }

  @override
  void onClose() {
    videoPlayerServiceHandler?.onVideoDetailDispose(heroTag);
    super.onClose();
  }
}
