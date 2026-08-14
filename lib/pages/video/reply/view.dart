import 'package:PiliPlus/common/skeleton/video_reply.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/colored_box_transition.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/fab_mixin.dart';
import 'package:PiliPlus/pages/common/reply_filter.dart';
import 'package:PiliPlus/pages/video/reply/controller.dart';
import 'package:PiliPlus/pages/video/reply/vote/reply_vote_item.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class VideoReplyPanel extends StatefulWidget {
  const VideoReplyPanel({
    super.key,
    this.replyLevel = 1,
    required this.heroTag,
    required this.isNested,
  });

  final int replyLevel;
  final String heroTag;
  final bool isNested;

  @override
  State<VideoReplyPanel> createState() => _VideoReplyPanelState();
}

class _VideoReplyPanelState extends State<VideoReplyPanel>
    with
        AutomaticKeepAliveClientMixin,
        SingleTickerProviderStateMixin,
        BaseFabMixin,
        FabMixin {
  late ColorScheme colorScheme;
  late VideoReplyController _videoReplyController;
  Animation<Color?>? _colorAnimation;

  String get heroTag => widget.heroTag;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _videoReplyController = Get.find<VideoReplyController>(tag: heroTag);
    if (_videoReplyController.loadingState.value is Loading) {
      _videoReplyController.queryData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorScheme = ColorScheme.of(context);
    bottom = MediaQuery.viewPaddingOf(context).bottom;
    _colorAnimation = null;
  }

  late double bottom;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return fabAnimWrapper(
      child: refreshIndicator(
        onRefresh: _videoReplyController.onRefresh,
        isClampingScrollPhysics: widget.isNested,
        child: ScaffoldLayout(
          body: CustomScrollView(
            controller: widget.isNested
                ? null
                : _videoReplyController.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            key: const PageStorageKey(_VideoReplyPanelState),
            slivers: [
              SliverFloatingHeaderWidget(
                backgroundColor: colorScheme.surface,
                child: Padding(
                  padding: const .fromLTRB(12, 2.5, 6, 2.5),
                  child: Obx(() {
                    final response =
                        _videoReplyController.loadingState.value.dataOrNull;
                    final active = _videoReplyController.hasActiveReplyFilter;
                    final visibleCount = _videoReplyController
                        .visibleReplyCount(response);
                    return Row(
                      mainAxisAlignment: .spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            active
                                ? '已筛选 $visibleCount 条'
                                : _videoReplyController.sortDisplayTitle,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        TextButton.icon(
                          style: Style.buttonStyle,
                          onPressed: _showFilterSheet,
                          icon: Icon(
                            Icons.manage_search,
                            size: 16,
                            color: active
                                ? colorScheme.primary
                                : colorScheme.secondary,
                          ),
                          label: Text(
                            '查找',
                            style: TextStyle(
                              fontSize: 13,
                              color: active
                                  ? colorScheme.primary
                                  : colorScheme.secondary,
                            ),
                          ),
                        ),
                        if (active)
                          IconButton(
                            tooltip: '清空查找',
                            onPressed: _videoReplyController.clearReplyFilter,
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                          ),
                        TextButton.icon(
                          style: Style.buttonStyle,
                          onPressed: _videoReplyController.queryBySort,
                          icon: Icon(
                            Icons.sort,
                            size: 16,
                            color: colorScheme.secondary,
                          ),
                          label: Text(
                            _videoReplyController.sortDisplayLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
              Obx(
                () => _buildBody(
                  theme,
                  _videoReplyController.loadingState.value,
                ),
              ),
            ],
          ),
          fab: SlideTransition(
            position: fabAnimation,
            child: Padding(
              padding: .only(
                right: kFloatingActionButtonMargin,
                bottom: kFloatingActionButtonMargin + bottom,
              ),
              child: FloatingActionButton(
                heroTag: null,
                onPressed: () {
                  feedBack();
                  _videoReplyController.onReply(
                    null,
                    oid: _videoReplyController.aid,
                    replyType: _videoReplyController.videoType.replyType,
                  );
                },
                tooltip: '发表评论',
                child: const Icon(Icons.reply),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    LoadingState<List<ReplyInfo>?> loadingState,
  ) {
    final jumpReplyId = _videoReplyController.focusReplyId.value;
    switch (loadingState) {
      case Loading():
        return SliverList.builder(
          itemBuilder: (context, index) => const VideoReplySkeleton(),
          itemCount: 5,
        );
      case Success(:final response):
        final voteCard = _videoReplyController.voteCard;
        final visibleResponse = _videoReplyController.visibleReplies(
          response ?? const [],
        );
        Widget body;
        if (visibleResponse.isNotEmpty) {
          body = SliverList.builder(
            itemBuilder: (context, index) {
              if (voteCard != null) {
                if (index == 0) {
                  return buildVoteCard(context, colorScheme, voteCard);
                }
                index--;
              }
              if (index == visibleResponse.length) {
                _videoReplyController.onLoadMore();
                return Container(
                  height: 125,
                  alignment: .center,
                  margin: .only(bottom: bottom),
                  child: Text(
                    _videoReplyController.isEnd ? '没有更多了' : '加载中...',
                    textAlign: .center,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                );
              }
              final replyItem = visibleResponse[index];
              final originalIndex = response?.indexWhere(
                (item) => item.id == replyItem.id,
              );
              final effectiveIndex = originalIndex == null || originalIndex == -1
                  ? index
                  : originalIndex;
              final child = ReplyItemGrpc(
                replyItem: replyItem,
                childReplies: _videoReplyController.visibleChildReplies(
                  replyItem,
                ),
                replyLevel: widget.replyLevel,
                replyReply: replyReply,
                onReply: _videoReplyController.onReply,
                onDelete: (item, subIndex) => _videoReplyController.onRemove(
                  effectiveIndex,
                  item,
                  subIndex,
                ),
                upMid: _videoReplyController.upMid,
                getTag: () => heroTag,
                onCheckReply: (item) =>
                    _videoReplyController.onCheckReply(item, isManual: true),
                onFilterByAuthor: _videoReplyController.filterByAuthor,
                onToggleTop: (item) => _videoReplyController.onToggleTop(
                  item,
                  effectiveIndex,
                  _videoReplyController.aid,
                  _videoReplyController.videoType.replyType,
                ),
              );
              if (jumpReplyId == replyItem.id.toInt()) {
                return ColoredBoxTransition(
                  color: _colorAnimation ??= _videoReplyController.animController
                      .drive(
                        ColorTween(
                          begin: theme.colorScheme.onInverseSurface,
                          end: theme.colorScheme.surface,
                        ).chain(
                          CurveTween(curve: const Interval(0.8, 1.0)),
                        ),
                      ),
                  child: child,
                );
              }
              return child;
            },
            itemCount:
                visibleResponse.length + 1 + (voteCard == null ? 0 : 1),
          );
        } else {
          final active = _videoReplyController.hasActiveReplyFilter;
          body = HttpError(
            errMsg: active
                ? (_videoReplyController.isEnd
                      ? '当前筛选条件下暂无结果'
                      : '当前已加载评论中暂无匹配项')
                : '还没有评论',
            onReload: active
                ? (_videoReplyController.isEnd
                      ? _videoReplyController.clearReplyFilter
                      : _videoReplyController.onLoadMore)
                : _videoReplyController.onReload,
            btnText: active
                ? (_videoReplyController.isEnd ? '清空筛选' : '继续加载')
                : null,
          );
        }
        if (voteCard != null && visibleResponse.isEmpty) {
          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: buildVoteCard(context, colorScheme, voteCard),
              ),
              body,
            ],
          );
        }
        return body;
      case Error(:final errMsg):
        return HttpError(
          errMsg: errMsg,
          onReload: _videoReplyController.onReload,
        );
    }
  }

  void _showFilterSheet() {
    feedBack();
    showReplyFilterSheet(
      context: context,
      value: _videoReplyController.filterState.value,
      replies: _videoReplyController.loadingState.value.dataOrNull ?? const [],
      upMid: _videoReplyController.upMid,
      showSearchChildReplies: true,
      showOnlyUp: _videoReplyController.upMid != null,
      onApply: _videoReplyController.applyReplyFilter,
    );
  }

  // 展示二级回复
  void replyReply(ReplyInfo replyItem, int? id) {
    EasyThrottle.throttle('replyReply', const Duration(milliseconds: 500), () {
      int oid = replyItem.oid.toInt();
      int rpid = replyItem.id.toInt();
      MiniScaffold.of(context).showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => VideoReplyReplyPanel(
          id: id,
          oid: oid,
          rpid: rpid,
          firstFloor: replyItem.replyControl.isNote ? null : replyItem,
          replyType: _videoReplyController.videoType.replyType,
          isVideoDetail: true,
          isNested: widget.isNested,
          upMid: _videoReplyController.upMid,
        ),
      );
    });
  }
}
