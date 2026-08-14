import 'package:PiliPlus/common/skeleton/video_reply.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/colored_box_transition.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/simple_colored_box.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/reply_filter.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/controller.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/widget_ext.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class VideoReplyReplyPanel extends CommonSlidePage {
  const VideoReplyReplyPanel({
    super.key,
    super.enableSlide,
    this.id,
    required this.oid,
    required this.rpid,
    this.dialog,
    this.firstFloor,
    required this.isVideoDetail,
    required this.replyType,
    this.isNested = false,
    this.upMid,
  });
  final int? id;
  final int oid;
  final int rpid;
  final int? dialog;
  final ReplyInfo? firstFloor;
  final bool isVideoDetail;
  final int replyType;
  final bool isNested;
  final Int64? upMid;

  @override
  State<VideoReplyReplyPanel> createState() => _VideoReplyReplyPanelState();

  static Future<void>? toReply({
    required int oid,
    required int rootId,
    String? rpIdStr,
    required int type,
    Uri? uri,
  }) {
    final rpId = rpIdStr == null ? null : int.tryParse(rpIdStr);
    return Get.to(
      arguments: {
        'oid': oid,
        'rpid': rootId,
        'id': ?rpId,
        'type': type,
        'enterUri': ?uri?.toString(), // save panel
      },
      () => SimpleScaffold(
        appBar: AppBar(
          title: const Text('评论详情'),
          actions: [
            IconButton(
              tooltip: '前往',
              onPressed: uri == null
                  ? null
                  : () => PiliScheme.routePush(
                      uri,
                      businessId: type,
                      videoArguments: {'replyFocusRootId': rootId},
                      preferVideoDirect: true,
                    ),
              icon: const Icon(Icons.open_in_browser),
            ),
          ],
        ),
        body: ViewSafeArea(
          child: VideoReplyReplyPanel(
            enableSlide: false,
            oid: oid,
            rpid: rootId,
            isVideoDetail: false,
            replyType: type,
            firstFloor: null,
            id: rpId,
          ),
        ).constraintWidth(),
      ),
    );
  }
}

class _VideoReplyReplyPanelState extends State<VideoReplyReplyPanel>
    with SingleTickerProviderStateMixin, CommonSlideMixin {
  late VideoReplyReplyController _controller;
  late final _tag = Utils.makeHeroTag('${widget.rpid}${widget.dialog}');
  Animation<Color?>? _colorAnimation;

  late final bool isDialogue = widget.dialog != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorAnimation = null;
    final controller = PrimaryScrollController.of(context);
    _controller
      ..didChangeDependencies(context)
      ..nestedController = controller is ExtendedNestedScrollController
          ? controller
          : null;
  }

  @override
  void initState() {
    super.initState();
    _controller = Get.put(
      VideoReplyReplyController(
        hasRoot: widget.firstFloor != null,
        id: widget.id,
        oid: widget.oid,
        rpid: widget.rpid,
        dialog: widget.dialog,
        replyType: widget.replyType,
        rootMid: widget.firstFloor?.mid,
      ),
      tag: _tag,
    );
  }

  @override
  void dispose() {
    Get.delete<VideoReplyReplyController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget buildPage(ThemeData theme) {
    Widget child() => enableSlide ? slideList(theme) : buildList(theme);
    return SimpleColoredBox(
      color: theme.canvasColor,
      child: MiniScaffold(
        body: widget.isVideoDetail
            ? Column(
                children: [
                  Container(
                    height: 45,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 1,
                          color: theme.dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.only(left: 12, right: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(isDialogue ? '对话列表' : '评论详情'),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: Get.back,
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: child()),
                ],
              )
            : child(),
      ),
    );
  }

  ReplyInfo? get firstFloor =>
      widget.firstFloor ?? _controller.firstFloor.value;

  ScrollController get scrollController =>
      _controller.nestedController ?? _controller.scrollController;

  @override
  Widget buildList(ThemeData theme) {
    return refreshIndicator(
      onRefresh: _controller.onRefresh,
      isClampingScrollPhysics: widget.isNested,
      child: CustomScrollView(
        key: ValueKey(scrollController.hashCode),
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (!isDialogue) ...[
            if ((widget.firstFloor ?? _controller.firstFloor.value)
                case final firstFloor?)
              _header(theme, firstFloor)
            else
              Obx(() {
                final firstFloor = _controller.firstFloor.value;
                if (firstFloor == null) {
                  return const SliverToBoxAdapter();
                }
                return _header(theme, firstFloor);
              }),
            _sortWidget(theme.colorScheme),
          ],
          Obx(
            () => _buildBody(theme.colorScheme, _controller.loadingState.value),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, ReplyInfo firstFloor) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: ReplyItemGrpc(
            replyItem: firstFloor,
            replyLevel: 2,
            needDivider: false,
            onReply: (replyItem) => _controller.onReply(replyItem, index: -1),
            upMid: widget.upMid ?? _controller.upMid,
            onCheckReply: (item) =>
                _controller.onCheckReply(item, isManual: true),
            onFilterByAuthor: _controller.filterByAuthor,
          ),
        ),
        SliverToBoxAdapter(
          child: Divider(
            height: 20,
            color: theme.dividerColor.withValues(alpha: 0.1),
            thickness: 6,
          ),
        ),
      ],
    );
  }

  Widget _sortWidget(ColorScheme colorScheme) {
    return SliverPinnedHeader(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 2.5, 6, 2.5),
        child: Obx(() {
          final active = _controller.hasActiveReplyFilter;
          final response = _controller.loadingState.value.dataOrNull;
          final visibleCount = _controller.visibleReplyCount(
            response,
            includeChildReplies: false,
          );
          final count = _controller.count.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: count != -1
                    ? Text(
                        active
                            ? '已筛选 $visibleCount 条'
                            : '相关回复共${NumUtils.numFormat(count)}条',
                        style: const TextStyle(fontSize: 13),
                      )
                    : const SizedBox.shrink(),
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
                  onPressed: _controller.clearReplyFilter,
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
              TextButton.icon(
                style: Style.buttonStyle,
                onPressed: _controller.queryBySort,
                icon: Icon(
                  Icons.sort,
                  size: 16,
                  color: colorScheme.secondary,
                ),
                label: Text(
                  _controller.sortDisplayLabel,
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
    );
  }

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<ReplyInfo>?> loadingState,
  ) {
    final jumpReplyId = _controller.highlightReplyId.value;
    return switch (loadingState) {
      Loading() => SliverPrototypeExtentList.builder(
        prototypeItem: const VideoReplySkeleton(),
        itemBuilder: (_, _) => const VideoReplySkeleton(),
        itemCount: 8,
      ),
      Success(:final response!) => switch (
          _controller.visibleReplies(response, includeChildReplies: false)
        ) {
          [] => HttpError(
            errMsg: _controller.hasActiveReplyFilter
                ? (_controller.isEnd
                      ? '当前筛选条件下暂无结果'
                      : '当前已加载回复中暂无匹配项')
                : '还没有回复',
            onReload: _controller.hasActiveReplyFilter
                ? (_controller.isEnd
                      ? _controller.clearReplyFilter
                      : _controller.onLoadMore)
                : _controller.onReload,
            btnText: _controller.hasActiveReplyFilter
                ? (_controller.isEnd ? '清空筛选' : '继续加载')
                : null,
          ),
          final visibleResponse => SuperSliverList.builder(
            listController: _controller.listController,
            itemBuilder: (context, index) {
              if (index == visibleResponse.length) {
                _controller.onLoadMore();
                return Container(
                  height: 125,
                  alignment: Alignment.center,
                  margin: EdgeInsets.only(
                    bottom: MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  child: Text(
                    _controller.isEnd ? '没有更多了' : '加载中...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
                );
              }
              final child = _replyItem(context, visibleResponse[index], index);
              if (jumpReplyId == visibleResponse[index].id.toInt()) {
                return ColoredBoxTransition(
                  color: _colorAnimation ??= _controller.animController.drive(
                    ColorTween(
                      begin: colorScheme.onInverseSurface,
                      end: colorScheme.surface,
                    ).chain(
                      CurveTween(
                        curve: const Interval(0.8, 1.0),
                      ),
                    ),
                  ),
                  child: child,
                );
              }
              return child;
            },
            itemCount: visibleResponse.length + 1,
          ),
        },
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
    };
  }

  Widget _replyItem(BuildContext context, ReplyInfo replyItem, int index) {
    final originalIndex = _controller.loadingState.value.dataOrNull?.indexWhere(
      (item) => item.id == replyItem.id,
    );
    return ReplyItemGrpc(
      replyItem: replyItem,
      replyLevel: isDialogue ? 3 : 2,
      onReply: (replyItem) =>
          _controller.onReply(replyItem, index: originalIndex ?? index),
      onDelete: (item, subIndex) =>
          _controller.onRemove(originalIndex ?? index, item, null),
      upMid: _controller.upMid,
      showDialogue: () => MiniScaffold.of(context).showBottomSheet(
        constraints: const BoxConstraints(),
        (context) => VideoReplyReplyPanel(
          oid: replyItem.oid.toInt(),
          rpid: replyItem.root.toInt(),
          dialog: replyItem.dialog.toInt(),
          replyType: widget.replyType,
          isVideoDetail: true,
          isNested: widget.isNested,
        ),
      ),
      jumpToDialogue: () {
        if (!_controller.setIndexById(replyItem.parent)) {
          SmartDialog.showToast(
            _controller.hasActiveReplyFilter ? '当前筛选条件下不可见' : '评论可能已被删除',
          );
        }
      },
      onCheckReply: (item) => _controller.onCheckReply(item, isManual: true),
      onFilterByAuthor: _controller.filterByAuthor,
    );
  }

  void _showFilterSheet() {
    final replies = [
      if (firstFloor != null) firstFloor!,
      ...?_controller.loadingState.value.dataOrNull,
    ];
    showReplyFilterSheet(
      context: context,
      value: _controller.filterState.value,
      replies: replies,
      upMid: _controller.upMid,
      rootMid: _controller.rootMid ?? firstFloor?.mid,
      showOnlyUp: _controller.upMid != null,
      showOnlyWithPicture: false,
      showOnlyWithReply: false,
      onApply: _controller.applyReplyFilter,
    );
  }
}
