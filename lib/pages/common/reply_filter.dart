import 'dart:math';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/utils/accounts.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ReplyFilterState {
  const ReplyFilterState({
    this.keyword = '',
    this.authorQuery = '',
    this.onlyUp = false,
    this.onlyWithPicture = false,
    this.onlyWithReply = false,
    this.onlyFriend = false,
    this.onlySelf = false,
  });

  final String keyword;
  final String authorQuery;
  final bool onlyUp;
  final bool onlyWithPicture;
  final bool onlyWithReply;
  final bool onlyFriend;
  final bool onlySelf;

  bool get isActive =>
      keyword.trim().isNotEmpty ||
      authorTokens.isNotEmpty ||
      onlyUp ||
      onlyWithPicture ||
      onlyWithReply ||
      onlyFriend ||
      onlySelf;

  List<String> get authorTokens => parseReplyAuthorTokens(authorQuery);
}

class ReplyFilterUser {
  const ReplyFilterUser({
    required this.mid,
    required this.name,
    required this.isUp,
    required this.isSelf,
    required this.isFriend,
  });

  final int mid;
  final String name;
  final bool isUp;
  final bool isSelf;
  final bool isFriend;
}

List<String> parseReplyAuthorTokens(String input) {
  return input
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String normalizeReplyAuthorToken(String token) {
  return token.trim().replaceFirst(RegExp(r'^@+'), '').trim();
}

bool isReplyAuthorMidToken(String token) {
  return RegExp(r'^\d+$').hasMatch(token);
}

bool matchesReplyAuthorToken({
  required int mid,
  required String name,
  required String rawToken,
}) {
  final token = normalizeReplyAuthorToken(rawToken).toLowerCase();
  if (token.isEmpty) {
    return false;
  }
  final midText = mid.toString();
  if (isReplyAuthorMidToken(token)) {
    return midText == token;
  }
  return name.toLowerCase().contains(token);
}

List<ReplyFilterUser> buildReplyFilterUsers(
  List<ReplyInfo> replies, {
  Int64? upMid,
}) {
  final upMidValue = upMid?.toInt();
  final selfMid = Accounts.main.mid;
  final users = <int, ReplyFilterUser>{};

  void collect(List<ReplyInfo> items) {
    for (final item in items) {
      final mid = item.mid.toInt();
      final current = users[mid];
      final next = ReplyFilterUser(
        mid: mid,
        name: item.member.name,
        isUp: upMidValue != null && mid == upMidValue,
        isSelf: selfMid != 0 && mid == selfMid,
        isFriend: item.replyControl.following && item.replyControl.followed,
      );
      users[mid] = current == null
          ? next
          : ReplyFilterUser(
              mid: mid,
              name: current.name.length >= next.name.length
                  ? current.name
                  : next.name,
              isUp: current.isUp || next.isUp,
              isSelf: current.isSelf || next.isSelf,
              isFriend: current.isFriend || next.isFriend,
            );
      if (item.replies.isNotEmpty) {
        collect(item.replies);
      }
    }
  }

  collect(replies);
  return users.values.toList(growable: false);
}

({int start, int end, String token}) activeReplyAuthorToken(
  TextEditingController controller,
) {
  final text = controller.text;
  final selection = controller.selection;
  final offset = selection.isValid
      ? selection.baseOffset.clamp(0, text.length).toInt()
      : text.length;
  final previousComma = text.lastIndexOf(',', max(0, offset - 1));
  final nextComma = text.indexOf(',', offset);
  final start = previousComma == -1 ? 0 : previousComma + 1;
  final end = nextComma == -1 ? text.length : nextComma;
  return (start: start, end: end, token: text.substring(start, end).trim());
}

void fillReplyAuthorToken(
  TextEditingController controller,
  ReplyFilterUser user,
) {
  final activeToken = activeReplyAuthorToken(controller);
  final prefix = controller.text.substring(0, activeToken.start);
  final suffix = controller.text.substring(activeToken.end);
  final fillText = '@${user.name}';
  final hasContentBefore = prefix.trimRight().isNotEmpty;
  final hasCommaBefore = prefix.trimRight().endsWith(',');
  final replacementPrefix = hasContentBefore && hasCommaBefore ? ' ' : '';
  final fillSuffix = suffix.trimLeft().isEmpty ? ', ' : '';
  final nextText = prefix + replacementPrefix + fillText + fillSuffix + suffix;
  final nextOffset = (prefix + replacementPrefix + fillText + fillSuffix)
      .length;
  controller.value = TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
  );
}

bool matchesReplyFilterUserSelection({
  required ReplyFilterUser user,
  required String rawToken,
}) {
  final token = normalizeReplyAuthorToken(rawToken).toLowerCase();
  if (token.isEmpty) {
    return false;
  }
  return token == user.mid.toString() || token == user.name.toLowerCase();
}

bool isReplyFilterUserSelected(
  TextEditingController controller,
  ReplyFilterUser user,
) {
  return parseReplyAuthorTokens(controller.text).any(
    (token) => matchesReplyFilterUserSelection(user: user, rawToken: token),
  );
}

void removeReplyFilterUser(
  TextEditingController controller,
  ReplyFilterUser user,
) {
  final nextTokens = parseReplyAuthorTokens(controller.text)
      .where(
        (token) => !matchesReplyFilterUserSelection(user: user, rawToken: token),
      )
      .toList(growable: false);
  final nextText = nextTokens.join(', ');
  controller.value = TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextText.length),
  );
}

void toggleReplyFilterUser(
  TextEditingController controller,
  ReplyFilterUser user,
) {
  if (isReplyFilterUserSelected(controller, user)) {
    removeReplyFilterUser(controller, user);
    return;
  }
  fillReplyAuthorToken(controller, user);
}

Future<void> showReplyFilterSheet({
  required BuildContext context,
  required ReplyFilterState value,
  required ValueChanged<ReplyFilterState> onApply,
  required List<ReplyInfo> replies,
  Int64? upMid,
  bool showOnlyUp = false,
  bool showOnlyWithReply = true,
}) async {
  final authorController = TextEditingController(text: value.authorQuery);
  final keywordController = TextEditingController(text: value.keyword);
  var onlyUp = value.onlyUp;
  var onlyWithPicture = value.onlyWithPicture;
  var onlyWithReply = value.onlyWithReply;
  var onlyFriend = value.onlyFriend;
  var onlySelf = value.onlySelf;
  var authorFocused = false;
  final users = buildReplyFilterUsers(replies, upMid: upMid);

  try {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: min(640, MediaQuery.sizeOf(context).width),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final outline = theme.colorScheme.outline;

        InputDecoration decoration({
          required String labelText,
          String? hintText,
        }) => InputDecoration(
          labelText: labelText,
          hintText: hintText,
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            color: outline.withValues(alpha: 0.65),
          ),
          border: const OutlineInputBorder(),
          isDense: true,
        );

        List<ReplyFilterUser> filteredUsers({
          required String token,
        }) {
          final normalizedToken = normalizeReplyAuthorToken(token).toLowerCase();
          final isMidToken = isReplyAuthorMidToken(normalizedToken);
          return users.where((user) {
            if (showOnlyUp && onlyUp && !user.isUp) {
              return false;
            }
            if (onlyFriend && !user.isFriend) {
              return false;
            }
            if (onlySelf && !user.isSelf) {
              return false;
            }
            if (normalizedToken.isEmpty) {
              return true;
            }
            return isMidToken
                ? user.mid.toString().contains(normalizedToken)
                : user.name.toLowerCase().contains(normalizedToken);
          }).toList(growable: false);
        }

        return StatefulBuilder(
          builder: (context, setState) {
            final activeToken = activeReplyAuthorToken(authorController).token;
            final shouldShowSuggestions =
                authorFocused &&
                (activeToken.isEmpty ||
                    activeToken.startsWith('@') ||
                    activeToken.trim().isNotEmpty);
            final suggestionUsers = filteredUsers(token: activeToken);

            void onSubmit() {
              final next = ReplyFilterState(
                authorQuery: authorController.text.trim(),
                keyword: keywordController.text.trim(),
                onlyUp: showOnlyUp ? onlyUp : false,
                onlyWithPicture: onlyWithPicture,
                onlyWithReply: showOnlyWithReply ? onlyWithReply : false,
                onlyFriend: onlyFriend,
                onlySelf: onlySelf,
              );
              onApply(next.isActive ? next : const ReplyFilterState());
              Get.back();
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom:
                    MediaQuery.viewInsetsOf(context).bottom +
                    MediaQuery.viewPaddingOf(context).bottom +
                    16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Center(
                      child: Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: outline.withValues(alpha: 0.7),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '查找评论',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '筛选范围仅包含当前已加载的评论',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: outline,
                      ),
                    ),
                    Focus(
                      onFocusChange: (focused) {
                        setState(() {
                          authorFocused = focused;
                        });
                      },
                      child: TextField(
                        controller: authorController,
                        textInputAction: TextInputAction.next,
                        decoration: decoration(
                          labelText: '用户昵称或 UID',
                          hintText: '输入 UID 或者 @用户名, 逗号分隔',
                        ).copyWith(
                          suffixIcon: IconButton(
                            tooltip: '插入@',
                            onPressed: () {
                              final value = authorController.value;
                              final text = value.text;
                              final selection = value.selection;
                              final offset = selection.isValid
                                  ? selection.baseOffset
                                      .clamp(0, text.length)
                                      .toInt()
                                  : text.length;
                              final tokenInfo = activeReplyAuthorToken(
                                authorController,
                              );
                              final hasAtBeforeCursor = text
                                  .substring(tokenInfo.start, offset)
                                  .contains('@');
                              if (hasAtBeforeCursor) {
                                setState(() {
                                  authorFocused = true;
                                });
                                return;
                              }
                              authorController.value = TextEditingValue(
                                text: text.replaceRange(offset, offset, '@'),
                                selection: TextSelection.collapsed(
                                  offset: offset + 1,
                                ),
                              );
                              setState(() {
                                authorFocused = true;
                              });
                            },
                            icon: const Icon(Icons.alternate_email),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    Text(
                      '可用 , 分隔多个用户, 输入 @ 可快速选择下方用户',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: outline,
                      ),
                    ),
                    if (shouldShowSuggestions)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 240),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.3),
                          ),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(12),
                          ),
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                        ),
                        child: suggestionUsers.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                                child: Text(
                                  '当前没有匹配用户',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: outline,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: suggestionUsers.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                                itemBuilder: (context, index) {
                                  final user = suggestionUsers[index];
                                  final isSelected = isReplyFilterUserSelected(
                                    authorController,
                                    user,
                                  );
                                  final tags = <String>[
                                    if (user.isUp) 'UP',
                                    if (user.isSelf) '自己',
                                    if (user.isFriend) '好友',
                                  ];
                                  return ListTile(
                                    dense: true,
                                    minTileHeight: 42,
                                    selected: isSelected,
                                    onTap: () {
                                      toggleReplyFilterUser(
                                        authorController,
                                        user,
                                      );
                                      setState(() {
                                        authorFocused = true;
                                      });
                                    },
                                    trailing: isSelected
                                        ? const Icon(Icons.check, size: 18)
                                        : null,
                                    title: Text(
                                      user.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      [
                                        'UID ${user.mid}',
                                        if (tags.isNotEmpty) tags.join(' | '),
                                      ].join(' | '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                },
                              ),
                      ),
                    TextField(
                      controller: keywordController,
                      textInputAction: TextInputAction.search,
                      decoration: decoration(
                        labelText: '关键词',
                        hintText: '输入后按评论内容查找',
                      ),
                      onSubmitted: (_) => onSubmit(),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (showOnlyUp)
                          FilterChip(
                            selected: onlyUp,
                            label: const Text('只看UP主'),
                            onSelected: (selected) {
                              setState(() {
                                onlyUp = selected;
                              });
                            },
                          ),
                        FilterChip(
                          selected: onlyFriend,
                          label: const Text('只显示好友'),
                          onSelected: (selected) {
                            setState(() {
                              onlyFriend = selected;
                            });
                          },
                        ),
                        FilterChip(
                          selected: onlySelf,
                          label: const Text('只显示自己'),
                          onSelected: (selected) {
                            setState(() {
                              onlySelf = selected;
                            });
                          },
                        ),
                        FilterChip(
                          selected: onlyWithPicture,
                          label: const Text('只看含图片'),
                          onSelected: (selected) {
                            setState(() {
                              onlyWithPicture = selected;
                            });
                          },
                        ),
                        if (showOnlyWithReply)
                          FilterChip(
                            selected: onlyWithReply,
                            label: const Text('只看有回复'),
                            onSelected: (selected) {
                              setState(() {
                                onlyWithReply = selected;
                              });
                            },
                          ),
                      ],
                    ),
                    Row(
                      spacing: 12,
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () {
                              onApply(const ReplyFilterState());
                              Get.back();
                            },
                            child: const Text('清空筛选'),
                          ),
                        ),
                        Expanded(
                          child: FilledButton(
                            onPressed: onSubmit,
                            child: const Text('应用筛选'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    authorController.dispose();
    keywordController.dispose();
  }
}
