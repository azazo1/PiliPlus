import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/subtitle_utils.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SubtitleBrowserPage extends CommonSlidePage {
  const SubtitleBrowserPage({
    super.key,
    super.enableSlide,
    required this.videoDetailController,
    required this.plPlayerController,
  });

  final VideoDetailController videoDetailController;
  final PlPlayerController plPlayerController;

  @override
  State<SubtitleBrowserPage> createState() => _SubtitleBrowserPageState();
}

class _SubtitleBrowserPageState extends State<SubtitleBrowserPage>
    with SingleTickerProviderStateMixin, CommonSlideMixin {
  VideoDetailController get videoDetailController =>
      widget.videoDetailController;
  PlPlayerController get plPlayerController => widget.plPlayerController;

  final _searchController = TextEditingController();
  late final RxString _keyword = ''.obs;
  late final Rx<LoadingState<List<SubtitleCue>>> _loadingState =
      LoadingState<List<SubtitleCue>>.loading().obs;
  late final RxList<int> _filteredIndexes = <int>[].obs;

  late int _trackIndex;
  List<SubtitleCue> _cues = const [];
  int _currentCueIndex = -1;

  @override
  void initState() {
    super.initState();
    _trackIndex = _resolveTrackIndex();
    _loadCues();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _resolveTrackIndex() {
    final index = videoDetailController.vttSubtitlesIndex.value;
    if (index > 0) return index - 1;
    return 0;
  }

  Future<void> _loadCues() async {
    _loadingState.value = LoadingState<List<SubtitleCue>>.loading();
    final cues = await videoDetailController.loadSubtitleCues(_trackIndex);
    if (!mounted) return;
    if (cues == null) {
      _cues = const [];
      _filteredIndexes.clear();
      _currentCueIndex = -1;
      _loadingState.value = const Error('字幕加载失败');
      return;
    }
    _cues = cues;
    _applyFilter(_keyword.value);
    _loadingState.value = Success(_cues);
  }

  void _applyFilter(String rawKeyword) {
    _keyword.value = rawKeyword;
    final keyword = rawKeyword.trim().toLowerCase();
    if (_cues.isEmpty) {
      _filteredIndexes.clear();
      _currentCueIndex = -1;
      return;
    }
    if (keyword.isEmpty) {
      _filteredIndexes.assignAll(List<int>.generate(_cues.length, (i) => i));
    } else {
      _filteredIndexes.assignAll([
        for (var i = 0; i < _cues.length; i++)
          if (_cues[i].content.toLowerCase().contains(keyword)) i,
      ]);
    }
    _currentCueIndex = _findCurrentCueIndex();
  }

  int _findCurrentCueIndex() {
    if (_filteredIndexes.isEmpty) return -1;
    final seconds = plPlayerController.position.value.toDouble();
    for (var i = 0; i < _filteredIndexes.length; i++) {
      if (_cues[_filteredIndexes[i]].contains(seconds)) {
        return i;
      }
    }
    for (var i = _filteredIndexes.length - 1; i >= 0; i--) {
      if (_cues[_filteredIndexes[i]].from <= seconds) {
        return i;
      }
    }
    return 0;
  }

  void _seekTo(SubtitleCue cue) {
    Get.back();
    plPlayerController.seekTo(
      Duration(milliseconds: (cue.from * 1000).round()),
      isSeek: false,
    );
  }

  @override
  Widget buildPage(ThemeData theme) {
    final subtitles = videoDetailController.subtitles;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        primary: false,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text('字幕浏览'),
        toolbarHeight: 45,
        actions: [
          if (subtitles.length > 1)
            Builder(
              builder: (context) {
                final current =
                    subtitles[_trackIndex.clamp(0, subtitles.length - 1)];
                return PopupMenuButton<int>(
                  tooltip: '选择字幕',
                  initialValue: _trackIndex,
                  onSelected: (index) {
                    if (index == _trackIndex) return;
                    setState(() => _trackIndex = index);
                    _loadCues();
                  },
                  itemBuilder: (context) => [
                    for (var i = 0; i < subtitles.length; i++)
                      PopupMenuItem<int>(
                        value: i,
                        child: Text(subtitles[i].lanDoc ?? subtitles[i].lan),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 96),
                          child: Text(
                            current.lanDoc ?? current.lan,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.unfold_more,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          iconButton(
            context: context,
            size: 30,
            icon: const Icon(Icons.clear),
            tooltip: '关闭',
            onPressed: Get.back,
          ),
          const SizedBox(width: 16),
        ],
        shape: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: _applyFilter,
              decoration: InputDecoration(
                isDense: true,
                hintText: '过滤字幕',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: Obx(() {
                  if (_keyword.value.trim().isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _applyFilter('');
                    },
                  );
                }),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: enableSlide ? slideList(theme) : buildList(theme)),
        ],
      ),
    );
  }

  late bool _isNested;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isNested = PrimaryScrollController.of(context)
        is ExtendedNestedScrollController;
  }

  @override
  Widget buildList(ThemeData theme) {
    final child = Obx(() {
      final state = _loadingState.value;
      final indexes = _filteredIndexes.toList(growable: false);
      return switch (state) {
        Loading() => m3eLoading,
        Error(:final errMsg) => HttpError(
          isSliver: false,
          errMsg: errMsg,
          onReload: _loadCues,
        ),
        Success() => _buildCueList(theme, indexes),
      };
    });
    if (_isNested) {
      return ExtendedVisibilityDetector(
        uniqueKey: const ValueKey(SubtitleBrowserPage),
        child: child,
      );
    }
    return child;
  }

  Widget _buildCueList(ThemeData theme, List<int> indexes) {
    if (indexes.isEmpty) {
      return HttpError(
        isSliver: false,
        errMsg: _keyword.value.trim().isEmpty ? '没有字幕' : '没有匹配的字幕',
      );
    }
    return ListView.builder(
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: 4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
      ),
      itemCount: indexes.length,
      itemBuilder: (context, index) {
        final cue = _cues[indexes[index]];
        final isCurr = index == _currentCueIndex;
        return Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _seekTo(cue),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DurationUtils.formatDuration(cue.from),
                    style: TextStyle(
                      fontSize: 12,
                      color: isCurr
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cue.content,
                    style: isCurr
                        ? TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
