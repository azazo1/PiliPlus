import 'dart:async';

import 'package:PiliPlus/common/widgets/flutter/text_field/controller.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo, SubjectControl, Mode;
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/models/common/reply/reply_sort_type.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/pages/common/reply_filter.dart';
import 'package:PiliPlus/pages/video/reply_new/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/reply_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

abstract class ReplyController<R> extends CommonListController<R, ReplyInfo> {
  final RxInt count = (-1).obs;
  final Rx<ReplyFilterState> filterState = const ReplyFilterState().obs;
  final RxBool _likeSortDirty = false.obs;
  bool _isResolvingFilteredReplies = false;

  late final Rx<ReplySortType> sortType;
  late final Rx<Mode> mode;

  final savedReplies = <Object, List<RichTextItem>?>{};

  Int64? upMid;
  Int64? rootMid;
  Int64? cursorNext;
  SubjectControl? subjectControl;
  FeedPaginationReply? paginationReply;
  late bool hasUpTop = false;

  @override
  bool? get hasFooter => true;

  // comment antifraud
  late final _enableCommAntifraud = Pref.enableCommAntifraud;
  late final _biliSendCommAntifraud = Pref.biliSendCommAntifraud;
  bool get enableCommAntifraud =>
      _enableCommAntifraud || _biliSendCommAntifraud;
  dynamic get sourceId;
  bool get includeChildRepliesInVisibleResults => true;
  bool get hasActiveReplyFilter => filterState.value.isActive;
  bool get isLikeSort => sortType.value == ReplySortType.like;
  String get sortDisplayTitle => isLikeSort
      ? (_likeSortDirty.value
            ? '按点赞排序(点击重排)'
            : ReplySortType.like.title)
      : sortType.value.title;
  String get sortDisplayLabel => isLikeSort
      ? (_likeSortDirty.value ? '点赞*' : ReplySortType.like.label)
      : sortType.value.label;

  void applyReplyFilter(ReplyFilterState value) {
    filterState.value = value;
    loadingState.refresh();
    unawaited(_ensureFilteredRepliesVisible());
  }

  void clearReplyFilter() {
    if (!hasActiveReplyFilter) {
      return;
    }
    filterState.value = const ReplyFilterState();
    loadingState.refresh();
  }

  List<ReplyInfo> visibleReplies(
    List<ReplyInfo> replies, {
    bool includeChildReplies = true,
  }) {
    if (!hasActiveReplyFilter) {
      return replies;
    }
    final shouldIncludeChildReplies =
        includeChildReplies &&
        filterState.value.searchChildReplies &&
        !filterState.value.hasTimeRange;
    return replies
        .where(
          (item) => shouldIncludeChildReplies
              ? matchesReplyOrChildReply(item)
              : matchesReply(item),
        )
        .toList(growable: false);
  }

  List<ReplyInfo> visibleChildReplies(ReplyInfo reply) {
    final replies = reply.replies;
    if (!hasActiveReplyFilter || replies.isEmpty) {
      return replies;
    }
    return replies.where(matchesReply).toList(growable: false);
  }

  int visibleReplyCount(
    List<ReplyInfo>? replies, {
    bool includeChildReplies = true,
  }) {
    if (replies == null) {
      return 0;
    }
    return visibleReplies(
      replies,
      includeChildReplies: includeChildReplies,
    ).length;
  }

  bool matchesReplyOrChildReply(ReplyInfo item) {
    if (matchesReply(item)) {
      return true;
    }
    return item.replies.any(matchesReply);
  }

  bool matchesReply(ReplyInfo item) {
    final filter = filterState.value;
    if (!filter.isActive) {
      return true;
    }

    final authorTokens = filter.authorTokens;
    if (authorTokens.isNotEmpty &&
        !authorTokens.any(
          (token) => matchesReplyAuthorToken(
            mid: item.mid.toInt(),
            name: item.member.name,
            rawToken: token,
          ),
        )) {
      return false;
    }

    final locationTokens = filter.locationTokens;
    if (locationTokens.isNotEmpty) {
      final location = item.replyControl.hasLocation()
          ? item.replyControl.location
          : '';
      if (!locationTokens.any(
        (token) => matchesReplyLocationToken(
          location: location,
          rawToken: token,
        ),
      )) {
        return false;
      }
    }

    if (filter.onlyFriend &&
        !(item.replyControl.following && item.replyControl.followed)) {
      return false;
    }

    final selfMid = Accounts.main.mid;
    if (filter.onlySelf && (selfMid == 0 || item.mid.toInt() != selfMid)) {
      return false;
    }

    final replyTime = item.ctime.toInt();
    if (filter.startTime != null && replyTime < filter.startTime!) {
      return false;
    }

    if (filter.endTime != null && replyTime > filter.endTime!) {
      return false;
    }

    final replyLike = item.like.toInt();
    if (filter.minLike != null && replyLike < filter.minLike!) {
      return false;
    }

    if (filter.maxLike != null && replyLike > filter.maxLike!) {
      return false;
    }

    final keyword = filter.keyword.trim().toLowerCase();
    if (keyword.isNotEmpty) {
      final hasKeyword =
          item.content.message.toLowerCase().contains(keyword) ||
          (item.hasTranslatedContent() &&
              item.translatedContent.message.toLowerCase().contains(keyword));
      if (!hasKeyword) {
        return false;
      }
    }

    if (filter.onlyUp && upMid != null && item.mid != upMid) {
      return false;
    }

    if (filter.onlyRoot && rootMid != null && item.mid != rootMid) {
      return false;
    }

    if (filter.onlyWithPicture && item.content.pictures.isEmpty) {
      return false;
    }

    if (filter.onlyWithReply && item.count <= Int64.ZERO) {
      return false;
    }

    return true;
  }

  void filterByAuthor(ReplyInfo reply) {
    applyReplyFilter(ReplyFilterState(authorQuery: reply.mid.toString()));
    SmartDialog.showToast('已筛选 ${reply.member.name} 的评论');
  }

  @override
  void handleListResponse(List<ReplyInfo> dataList) {
    if (isLikeSort) {
      _sortReplyTreeByLike(dataList);
    }
  }

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    final int previousLength = loadingState.value.dataOrNull?.length ?? 0;
    await super.queryData(isRefresh);
    if (isLikeSort) {
      if (isRefresh) {
        _likeSortDirty.value = false;
      } else {
        final int currentLength = loadingState.value.dataOrNull?.length ?? 0;
        if (currentLength > previousLength) {
          _likeSortDirty.value = true;
        }
      }
    }
    await _ensureFilteredRepliesVisible();
  }

  Future<void> _ensureFilteredRepliesVisible() async {
    if (_isResolvingFilteredReplies ||
        isLoading ||
        !hasActiveReplyFilter ||
        isEnd ||
        isClosed) {
      return;
    }
    final response = loadingState.value.dataOrNull;
    if (response == null ||
        response.isEmpty ||
        visibleReplyCount(
              response,
              includeChildReplies: includeChildRepliesInVisibleResults,
            ) >
            0) {
      return;
    }

    _isResolvingFilteredReplies = true;
    try {
      while (!isClosed && hasActiveReplyFilter && !isEnd) {
        final current = loadingState.value.dataOrNull;
        if (isLoading ||
            current == null ||
            current.isEmpty ||
            visibleReplyCount(
                  current,
                  includeChildReplies: includeChildRepliesInVisibleResults,
                ) >
                0) {
          break;
        }
        await super.queryData(false);
      }
    } finally {
      _isResolvingFilteredReplies = false;
    }
  }

  @override
  void onInit() {
    super.onInit();
    final cacheSortType = Pref.replySortType;
    sortType = cacheSortType.obs;
    mode =
        ((cacheSortType == .time) ? Mode.MAIN_LIST_TIME : Mode.MAIN_LIST_HOT)
            .obs;
  }

  @override
  void checkIsEnd(int length) {
    final count = this.count.value;
    if (count != -1 && length >= count) {
      isEnd = true;
    }
  }

  @override
  bool customHandleResponse(bool isRefresh, Success response) {
    MainListReply data = response.response;
    cursorNext = data.cursor.next;
    paginationReply = data.paginationReply;
    count.value = data.subjectControl.count.toInt();
    if (isRefresh) {
      subjectControl = data.subjectControl;
      upMid ??= data.subjectControl.upMid;
      hasUpTop = data.hasUpTop();
      if (data.hasUpTop()) {
        data.replies.insert(0, data.upTop);
      }
      if (!isLikeSort && subjectControl?.title == ReplySortType.select.title) {
        sortType.value = .select;
      }
    }
    isEnd = data.cursor.isEnd;
    return false;
  }

  @override
  Future<void> onRefresh() {
    cursorNext = null;
    subjectControl = null;
    paginationReply = null;
    _likeSortDirty.value = false;
    return super.onRefresh();
  }

  List<(ReplySortType, String)> get _sortOptions {
    final options = <(ReplySortType, String)>[
      (ReplySortType.hot, ReplySortType.hot.title),
      (ReplySortType.time, ReplySortType.time.title),
      (ReplySortType.like, ReplySortType.like.title),
    ];
    if (sortType.value == ReplySortType.select) {
      options.insert(0, (ReplySortType.select, ReplySortType.select.title));
    }
    return options;
  }

  int _compareReplyLike(ReplyInfo a, ReplyInfo b) {
    final int likeCompare = b.like.compareTo(a.like);
    if (likeCompare != 0) {
      return likeCompare;
    }
    final int timeCompare = b.ctime.compareTo(a.ctime);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return b.id.compareTo(a.id);
  }

  void _sortReplyTreeByLike(List<ReplyInfo> replies) {
    replies.sort(_compareReplyLike);
    for (final ReplyInfo item in replies) {
      if (item.replies.isNotEmpty) {
        item.replies.sort(_compareReplyLike);
      }
    }
  }

  void _applyLikeSort() {
    sortType.value = ReplySortType.like;
    mode.value = Mode.MAIN_LIST_HOT;
    _likeSortDirty.value = false;
    final replies = loadingState.value.dataOrNull;
    if (replies == null) {
      onReload();
      return;
    }
    _sortReplyTreeByLike(replies);
    loadingState.refresh();
  }

  void _applySortType(ReplySortType nextSortType) {
    if (nextSortType == ReplySortType.select) {
      return;
    }
    if (nextSortType == ReplySortType.like) {
      _applyLikeSort();
      return;
    }
    if (sortType.value == nextSortType) {
      return;
    }
    sortType.value = nextSortType;
    _likeSortDirty.value = false;
    mode.value =
        nextSortType == ReplySortType.time
            ? Mode.MAIN_LIST_TIME
            : Mode.MAIN_LIST_HOT;
    onReload();
  }

  Future<void> queryBySort() async {
    if (isLoading || Get.context == null) {
      return;
    }
    final options = _sortOptions;
    final ReplySortType? currentValue = options.any(
          (item) => item.$1 == sortType.value,
        )
        ? sortType.value
        : null;
    final ReplySortType? selected = await showDialog<ReplySortType>(
      context: Get.context!,
      builder:
          (context) => AlertDialog(
            title: const Text('评论排序'),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            content: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      options
                          .map(
                            (item) => RadioListTile<ReplySortType>(
                              dense: true,
                              value: item.$1,
                              groupValue: currentValue,
                              title: Text(item.$2),
                              onChanged:
                                  (value) =>
                                      Navigator.of(context).pop(value),
                            ),
                          )
                          .toList(growable: false),
                ),
              ),
            ),
          ),
    );
    if (selected == null) {
      return;
    }
    feedBack();
    _applySortType(selected);
  }

  (bool inputDisable, String? hint) get replyHint {
    String? hint;
    bool inputDisable = false;
    try {
      if (subjectControl case final subjectControl?) {
        inputDisable = subjectControl.inputDisable;
        if (subjectControl.hasRootText()) {
          final rootText = subjectControl.rootText;
          if (inputDisable) {
            SmartDialog.showToast(rootText);
          }
          if (rootText.contains('可发') || rootText.contains('可见')) {
            hint = rootText;
          }
        }
      }
    } catch (_) {}
    return (inputDisable, hint);
  }

  void onReply(
    ReplyInfo? replyItem, {
    int? oid,
    int? replyType,
  }) {
    if (loadingState.value case Error(:final errMsg, :final code)) {
      if (errMsg != null && (code == 12061 || code == 12002)) {
        SmartDialog.showToast(errMsg);
        return;
      }
    }

    assert(replyItem != null || (oid != null && replyType != null));

    final (bool inputDisable, String? hint) = replyHint;
    if (inputDisable) {
      return;
    }

    final key = oid ?? replyItem!.oid + replyItem.id;
    Get.key.currentState!
        .push(
          PublishRoute(
            pageBuilder: (buildContext, animation, secondaryAnimation) {
              return ReplyPage(
                hint: hint,
                oid: oid ?? replyItem!.oid.toInt(),
                root: oid != null ? 0 : replyItem!.id.toInt(),
                parent: oid != null ? 0 : replyItem!.id.toInt(),
                replyType: replyItem?.type.toInt() ?? replyType!,
                replyItem: replyItem,
                items: savedReplies[key],

                /// hd api deprecated
                // canUploadPic: canUploadPic,
                onSave: (reply) {
                  if (reply.isEmpty) {
                    savedReplies.remove(key);
                  } else {
                    savedReplies[key] = reply.toList();
                  }
                },
              );
            },
            settings: RouteSettings(arguments: Get.arguments),
          ),
        )
        .then(
          (replyInfo) {
            if (replyInfo is ReplyInfo) {
              savedReplies.remove(key);
              if (loadingState.value case Success(:final response)) {
                if (response == null) {
                  loadingState.value = Success([replyInfo]);
                } else {
                  if (oid != null) {
                    if (isLikeSort) {
                      response.add(replyInfo);
                      _likeSortDirty.value = true;
                    } else {
                      response.insert(hasUpTop ? 1 : 0, replyInfo);
                    }
                  } else {
                    replyItem!
                      ..count += 1
                      ..replies.add(replyInfo);
                    if (isLikeSort) {
                      _likeSortDirty.value = true;
                    }
                  }
                  loadingState.refresh();
                }
              } else {
                loadingState.value = Success([replyInfo]);
              }
              count.value += 1;

              // check reply
              if (enableCommAntifraud) {
                onCheckReply(replyInfo, isManual: false);
              }
            }
          },
        );
  }

  void onRemove(int index, ReplyInfo item, int? subIndex) {
    if (subIndex == null) {
      if (index < 0 || index >= loadingState.value.data!.length) {
        return;
      }
      loadingState.value.data!.removeAt(index);
    } else {
      if (subIndex < 0 || subIndex >= item.replies.length) {
        return;
      }
      item
        ..count -= 1
        ..replies.removeAt(subIndex);
    }
    count.value -= 1;
    loadingState.refresh();
  }

  void onCheckReply(ReplyInfo replyInfo, {required bool isManual}) {
    ReplyUtils.onCheckReply(
      replyInfo: replyInfo,
      biliSendCommAntifraud: _biliSendCommAntifraud,
      sourceId: sourceId,
      isManual: isManual,
    );
  }

  Future<void> onToggleTop(
    ReplyInfo item,
    int index,
    oid,
    int type,
  ) async {
    bool isUpTop = item.replyControl.isUpTop;
    final res = await ReplyHttp.replyTop(
      oid: oid,
      type: type,
      rpid: item.id,
      isUpTop: isUpTop,
    );
    if (res.isSuccess) {
      item.replyControl.isUpTop = !isUpTop;
      if (!isLikeSort && !isUpTop && index != 0) {
        final list = loadingState.value.data!;
        list
          ..first.replyControl.isUpTop = false
          ..insert(0, list.removeAt(index));
      }
      loadingState.refresh();
      SmartDialog.showToast('${isUpTop ? '取消' : ''}置顶成功');
    } else {
      res.toast();
    }
  }

  @override
  void onClose() {
    savedReplies.clear();
    super.onClose();
  }
}
