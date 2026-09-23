import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:fixnum/fixnum.dart';

void removeDuplicateReplies(
  List<ReplyInfo> replies, [
  Iterable<ReplyInfo> existing = const [],
]) {
  final ids = existing.map((reply) => reply.id).toSet();
  replies.removeWhere(
    (reply) => reply.id != Int64.ZERO && !ids.add(reply.id),
  );
  for (final reply in replies) {
    if (reply.replies.isNotEmpty) {
      removeDuplicateReplies(reply.replies);
    }
  }
}
