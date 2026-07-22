import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/reply/vote/reply_vote_mixin.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

class VideoReplyController extends ReplyController<MainListReply>
    with GetSingleTickerProviderStateMixin, ReplyVoteMixin {
  VideoReplyController({
    required this.aid,
    required this.videoType,
    required this.heroTag,
    this.focusRootId,
  });
  int aid;
  final VideoType videoType;
  late final isPugv = videoType == VideoType.pugv;
  final int? focusRootId;

  final String heroTag;
  late final videoCtr = Get.find<VideoDetailController>(tag: heroTag);
  bool _focusApplied = false;
  final focusReplyId = RxnInt();

  AnimationController? _controller;
  AnimationController get animController => _controller ??= AnimationController(
    duration: const Duration(milliseconds: 1000),
    vsync: this,
  );

  @override
  dynamic get sourceId => IdUtils.av2bv(aid);

  @override
  List<ReplyInfo>? getDataList(MainListReply response) {
    return response.replies;
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    oid: isPugv ? videoCtr.epId! : aid,
    type: videoType.replyType,
    mode: mode,
    cursorNext: cursorNext,
    offset: paginationReply?.nextOffset,
    seekRpid: page == 1 ? focusRootId : null,
  );

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    await super.queryData(isRefresh);
    if (isRefresh) {
      await _applyReplyFocus();
    }
  }

  void _highlightItem(int replyId) {
    focusReplyId.value = replyId;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isClosed) {
        return;
      }
      animController.forward(from: 0);
    });
  }

  Future<void> _applyReplyFocus() async {
    final targetRootId = focusRootId;
    if (_focusApplied || targetRootId == null) {
      return;
    }
    final currentList = loadingState.value.dataOrNull;
    if (currentList == null) {
      return;
    }

    final currentIndex = currentList.indexWhere(
      (item) => item.id.toInt() == targetRootId,
    );
    if (currentIndex != -1) {
      _focusApplied = true;
      _highlightItem(targetRootId);
    }
  }

  @override
  void onClose() {
    _controller?.dispose();
    _controller = null;
    super.onClose();
  }
}
