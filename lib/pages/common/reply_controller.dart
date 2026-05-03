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
  Future<void> queryData([bool isRefresh = true]) async {
    await super.queryData(isRefresh);
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
        (cacheSortType == .time ? Mode.MAIN_LIST_TIME : Mode.MAIN_LIST_HOT).obs;
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
      if (subjectControl?.title == ReplySortType.select.title) {
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
    return super.onRefresh();
  }

  // 排序搜索评论
  void queryBySort() {
    if (isLoading) return;
    switch (sortType.value) {
      case ReplySortType.time:
        sortType.value = ReplySortType.hot;
        mode.value = Mode.MAIN_LIST_HOT;
        break;
      case ReplySortType.hot:
        sortType.value = ReplySortType.time;
        mode.value = Mode.MAIN_LIST_TIME;
        break;
      case ReplySortType.select:
        return;
    }
    feedBack();
    onReload();
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
                    response.insert(hasUpTop ? 1 : 0, replyInfo);
                  } else {
                    replyItem!
                      ..count += 1
                      ..replies.add(replyInfo);
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
      if (!isUpTop && index != 0) {
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
