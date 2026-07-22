part of 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';

void showReplyCopyDialog(
  BuildContext context,
  String message,
  Map<String, Emote> emotes,
) {
  bool showEmote = false;
  showDialog(
    context: context,
    builder: (context) => Dialog(
      constraints: const BoxConstraints.tightFor(width: 380),
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 16),
        child: SingleChildScrollView(
          child: SelectionText.rich(
            showEmote
                ? TextSpan(
                    children: emotes.entries.mapIndexed(
                      (i, e) {
                        final emote = e.value;
                        final size = emote.size.toInt() * 25.0;
                        return TextSpan(
                          children: [
                            if (i != 0) const TextSpan(text: '\n\n'),
                            WidgetSpan(
                              child: NetworkImgLayer(
                                src: emote.url,
                                type: .emote,
                                width: size,
                                height: size,
                              ),
                            ),
                            TextSpan(text: '\n${e.key}\n${emote.url}'),
                          ],
                        );
                      },
                    ).toList(),
                  )
                : TextSpan(text: message),
            contextMenuBuilder: (_, state) {
              final buttonItems = state.contextMenuButtonItems;
              if (emotes.isNotEmpty) {
                buttonItems.insertOrAdd(
                  3,
                  ContextMenuButtonItem(
                    label: showEmote ? '文本' : '表情',
                    onPressed: () {
                      state.hideAndClear();
                      showEmote = !showEmote;
                      (context as Element).markNeedsBuild();
                    },
                  ),
                );
                if (showEmote) {
                  state.addLaunchMenuIfNeeded(buttonItems, index: 4);
                }
              }
              if (state.isUncollapsed) {
                buttonItems.add(
                  ContextMenuButtonItem(
                    onPressed: () {
                      final text = state.selectedText!.trim();
                      if (text.isEmpty) {
                        return;
                      }

                      showConfirmDialog(
                        context: context,
                        title: const Text('是否确认将选中文本加入评论过滤?'),
                        content: Text.rich(
                          TextSpan(
                            text: '新增规则: ',
                            children: [
                              TextSpan(
                                text: text,
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: .bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onConfirm: () {
                          final filterRules = [
                            ...ReplyGrpc.replyFilterRules,
                            FilterRule(value: text),
                          ];
                          ReplyGrpc.replyFilterRules = filterRules;
                          GStorage.setting.put(
                            SettingBoxKey.banWordForReply,
                            encodeFilterRules(filterRules),
                          );
                          SmartDialog.showToast('已保存');
                        },
                      );
                    },
                    label: '加入过滤',
                  ),
                );
              }
              return AdaptiveTextSelectionToolbar.buttonItems(
                buttonItems: buttonItems,
                anchors: state.contextMenuAnchors,
              );
            },
            style: const TextStyle(fontSize: 15, height: 1.7),
          ),
        ),
      ),
    ),
  );
}
