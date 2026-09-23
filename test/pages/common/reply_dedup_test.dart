import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/pages/common/reply_dedup.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReplyInfo reply(int id) => ReplyInfo(id: Int64(id));

  test('keeps one copy of each reply in the first page', () {
    final replies = [reply(1), reply(2), reply(1), reply(3)];

    removeDuplicateReplies(replies);

    expect(replies.map((item) => item.id.toInt()), [1, 2, 3]);
  });

  test('removes overlap with loaded replies while preserving new ones', () {
    final loaded = [reply(1), reply(2)];
    final nextPage = [reply(2), reply(3), reply(3), reply(4)];

    removeDuplicateReplies(nextPage, loaded);

    expect(nextPage.map((item) => item.id.toInt()), [3, 4]);
  });

  test('deduplicates child replies as well', () {
    final root = reply(1)
      ..replies.addAll([reply(2), reply(2), reply(3)]);

    removeDuplicateReplies([root]);

    expect(root.replies.map((item) => item.id.toInt()), [2, 3]);
  });

  test('drops a repeated page without discarding replies with no id', () {
    final loaded = [reply(1), reply(2)];
    final repeatedPage = [reply(1), reply(2), reply(0), reply(0)];

    removeDuplicateReplies(repeatedPage, loaded);

    expect(repeatedPage.map((item) => item.id.toInt()), [0, 0]);
  });
}
