import 'dart:async';
import 'dart:collection';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/flutter/layout_builder.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_popup_menu.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/dimension_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/material.dart' hide LayoutBuilder;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:intl/intl.dart';

final class _PendingPubdateTask {
  final String bvid;
  final Completer<int?> completer;

  const _PendingPubdateTask({
    required this.bvid,
    required this.completer,
  });
}

abstract final class _RcmdPubdatePrefetcher {
  static const int _maxConcurrent = 3;
  static const Duration _requestInterval = Duration(milliseconds: 250);

  static final Queue<_PendingPubdateTask> _queue = Queue<_PendingPubdateTask>();
  static final Map<String, int?> _cache = <String, int?>{};
  static final Map<String, Future<int?>> _inflight = <String, Future<int?>>{};

  static int _activeCount = 0;
  static int _generation = 0;
  static DateTime? _lastStartedAt;
  static Timer? _pumpTimer;

  static Future<int?> fetchPubdate(String bvid, {bool prioritize = false}) {
    if (_cache.containsKey(bvid)) {
      return Future<int?>.value(_cache[bvid]);
    }
    if (_inflight[bvid] case final future?) {
      if (prioritize) {
        _moveQueuedTaskToFront(bvid);
      }
      return future;
    }
    final completer = Completer<int?>();
    final task = _PendingPubdateTask(
      bvid: bvid,
      completer: completer,
    );
    if (prioritize) {
      _queue.addFirst(task);
    } else {
      _queue.add(task);
    }
    _inflight[bvid] = completer.future;
    _schedulePump();
    return completer.future;
  }

  static void _moveQueuedTaskToFront(String bvid) {
    _PendingPubdateTask? task;
    for (final item in _queue) {
      if (item.bvid == bvid) {
        task = item;
        break;
      }
    }
    if (task != null && _queue.remove(task)) {
      _queue.addFirst(task);
    }
  }

  static int get generation => _generation;

  static void clear() {
    _pumpTimer?.cancel();
    _pumpTimer = null;
    _queue.clear();
    _cache.clear();
    _inflight.clear();
    _activeCount = 0;
    _lastStartedAt = null;
    _generation++;
  }

  static void _schedulePump([Duration delay = Duration.zero]) {
    _pumpTimer?.cancel();
    _pumpTimer = Timer(delay, _pump);
  }

  static void _pump() {
    _pumpTimer = null;
    while (_activeCount < _maxConcurrent && _queue.isNotEmpty) {
      final now = DateTime.now();
      final elapsed = _lastStartedAt == null
          ? _requestInterval
          : now.difference(_lastStartedAt!);
      if (elapsed < _requestInterval) {
        _schedulePump(_requestInterval - elapsed);
        return;
      }
      final task = _queue.removeFirst();
      _activeCount++;
      _lastStartedAt = now;
      _run(task);
    }
  }

  static Future<void> _run(_PendingPubdateTask task) async {
    int? pubdate;
    try {
      if (await VideoHttp.videoIntro(bvid: task.bvid)
          case Success(:final response)) {
        pubdate = response.pubdate ?? response.ctime;
      }
    } catch (_) {}
    _cache[task.bvid] = pubdate;
    _inflight.remove(task.bvid);
    if (!task.completer.isCompleted) {
      task.completer.complete(pubdate);
    }
    _activeCount--;
    _schedulePump();
  }
}

void clearRcmdPubdatePrefetcher() {
  _RcmdPubdatePrefetcher.clear();
}

int get rcmdPubdatePrefetchGeneration => _RcmdPubdatePrefetcher.generation;

// 视频卡片 - 垂直布局
class VideoCardV extends StatelessWidget {
  final BaseRcmdVideoItemModel videoItem;
  final VoidCallback? onRemove;

  const VideoCardV({
    super.key,
    required this.videoItem,
    this.onRemove,
  });

  Future<void> onPushDetail() async {
    switch (videoItem.goto) {
      case 'bangumi':
        PageUtils.viewPgc(epId: videoItem.param!);
        break;
      case 'av':
        var bvid = videoItem.bvid ?? IdUtils.av2bv(videoItem.aid!);
        var cid = videoItem.cid;
        bool isVertical = false;
        Dimension? dimension;
        if (videoItem is RcmdVideoItemAppModel) {
          if (videoItem.uri case final uri?) {
            isVertical = uri.isVerticalFromUri;
          }
        }
        if (cid == null) {
          if (await SearchHttp.ab2cWithDimension(aid: videoItem.aid, bvid: bvid)
              case final res?) {
            cid = res.cid;
            dimension = res.dimension;
          }
        }
        if (cid != null) {
          PageUtils.toVideoPage(
            aid: videoItem.aid,
            bvid: bvid,
            cid: cid,
            cover: videoItem.cover,
            title: videoItem.title,
            isVertical: isVertical,
            dimension: dimension,
          );
        }
        break;
      // 动态
      case 'picture':
        try {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        } catch (err) {
          SmartDialog.showToast(err.toString());
        }
        break;
      default:
        if (videoItem.uri?.isNotEmpty == true) {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        }
    }
  }

  String get publishTimeText {
    if (videoItem.pubdate case final pubdate?) {
      return DateFormatUtils.dateFormat(pubdate);
    }
    if (videoItem.desc case final desc? when desc.contains(' · ')) {
      return desc.split(' · ').last.trim();
    }
    return '';
  }

  Widget publishTimeBadge(Future<int?>? future) {
    final publishTimeText = this.publishTimeText;
    if (publishTimeText.isNotEmpty) {
      return _buildPublishTimeBadge(publishTimeText);
    }
    if (future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<int?>(
      key: ValueKey('${videoItem.bvid}-$rcmdPubdatePrefetchGeneration'),
      future: future,
      builder: (context, snapshot) {
        final asyncText = DateFormatUtils.dateFormat(snapshot.data);
        if (asyncText.isEmpty) {
          return const SizedBox.shrink();
        }
        return _buildPublishTimeBadge(asyncText);
      },
    );
  }

  PBadge _buildPublishTimeBadge(String text) => PBadge(
    bottom: videoItem.duration > 0 ? 28 : 6,
    right: 7,
    size: .small,
    type: .gray,
    fontSize: 10,
    isBold: false,
    textScaleFactor: 1,
    text: text,
  );

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
      videoItem: videoItem,
      onRemove: onRemove,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Card(
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: onPushDetail,
            onLongPress: onLongPress,
            onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: Style.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, boxConstraints) {
                      double maxWidth = boxConstraints.maxWidth;
                      double maxHeight = boxConstraints.maxHeight;
                      final Future<int?>? publishTimeFuture =
                          publishTimeText.isEmpty &&
                              videoItem.goto == 'av' &&
                              videoItem.bvid?.isNotEmpty == true
                          ? _RcmdPubdatePrefetcher.fetchPubdate(
                              videoItem.bvid!,
                              prioritize: true,
                            )
                          : null;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          NetworkImgLayer(
                            src: videoItem.cover,
                            width: maxWidth,
                            height: maxHeight,
                            type: .emote,
                          ),
                          publishTimeBadge(publishTimeFuture),
                          if (videoItem.duration > 0)
                            PBadge(
                              bottom: 6,
                              right: 7,
                              size: .small,
                              type: .gray,
                              text: DurationUtils.formatDuration(
                                videoItem.duration,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                content(context),
              ],
            ),
          ),
        ),
        if (videoItem.goto == 'av')
          Positioned(
            right: -5,
            bottom: -2,
            width: 29,
            height: 29,
            child: VideoPopupMenu(
              iconSize: 17,
              videoItem: videoItem,
              onRemove: onRemove,
            ),
          ),
      ],
    );
  }

  Widget content(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                "${videoItem.title}\n",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  height: 1.38,
                ),
              ),
            ),
            videoStat(context, theme),
            Row(
              spacing: 2,
              children: [
                if (videoItem.goto == 'bangumi')
                  PBadge(
                    text: videoItem.pgcBadge,
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (videoItem.rcmdReason != null)
                  PBadge(
                    text: videoItem.rcmdReason,
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                if (videoItem.goto == 'picture')
                  const PBadge(
                    text: '动态',
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (videoItem.isFollowed)
                  const PBadge(
                    text: '已关注',
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                Expanded(
                  flex: 1,
                  child: Text(
                    videoItem.owner.name.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    semanticsLabel: 'UP：${videoItem.owner.name}',
                    style: TextStyle(
                      height: 1.5,
                      fontSize: theme.textTheme.labelMedium!.fontSize,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (videoItem.goto == 'av') const SizedBox(width: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static final shortFormat = DateFormatUtils.shortFormat;
  static final longFormat = DateFormat('yy-M-d');

  Widget videoStat(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        StatWidget(
          type: StatType.play,
          value: videoItem.stat.view,
        ),
        if (videoItem.goto != 'picture') ...[
          const SizedBox(width: 4),
          StatWidget(
            type: StatType.danmaku,
            value: videoItem.stat.danmu,
          ),
        ],
        // deprecated
        //  else if (videoItem is RcmdVideoItemAppModel &&
        //     videoItem.desc != null &&
        //     videoItem.desc!.contains(' · ')) ...[
        //   const Spacer(),
        //   Text.rich(
        //     maxLines: 1,
        //     TextSpan(
        //         style: TextStyle(
        //           fontSize: theme.textTheme.labelSmall!.fontSize,
        //           color: theme.colorScheme.outline.withValues(alpha: 0.8),
        //         ),
        //         text: Utils.shortenChineseDateString(
        //             videoItem.desc!.split(' · ').last)),
        //   ),
        //   const SizedBox(width: 2),
        // ]
      ],
    );
  }
}
