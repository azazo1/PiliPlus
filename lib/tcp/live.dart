import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/services/logger.dart';
import 'package:brotli/brotli.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class PackageHeader {
  final int protocolVer;
  final int operationCode;
  final int seq;

  @override
  String toString() {
    return 'PackageHeader{protocolVer: $protocolVer, operationCode: $operationCode, seq: $seq}';
  }

  const PackageHeader({
    required this.protocolVer,
    required this.operationCode,
    required this.seq,
  });

  Uint8List toBytes(int contentSize) {
    final bytes = ByteData(0x10)
      ..setInt32(0, 0x10 + contentSize, Endian.big)
      ..setInt16(4, 0x10, Endian.big)
      ..setInt16(6, protocolVer, Endian.big)
      ..setInt32(8, operationCode, Endian.big)
      ..setInt32(12, seq, Endian.big);
    return bytes.buffer.asUint8List();
  }
}

class PackageHeaderRes extends PackageHeader {
  PackageHeaderRes({
    required this.totalSize,
    required this.headerSize,
    required super.protocolVer,
    required super.operationCode,
    required super.seq,
  });
  final int totalSize;
  final int headerSize;

  static PackageHeaderRes? fromBytesData(Uint8List data) {
    if (data.length < 10) {
      logger.w('数据不足以解析PackageHeader');
      return null;
    }
    final byteData = ByteData.sublistView(data);

    final totalSize = byteData.getUint32(0, Endian.big);
    final headerSize = byteData.getUint16(4, Endian.big);
    final protocolVer = byteData.getUint16(6, Endian.big);
    final operationCode = byteData.getUint32(8, Endian.big);
    final seq = byteData.getUint32(12, Endian.big);

    return PackageHeaderRes(
      totalSize: totalSize,
      headerSize: headerSize,
      protocolVer: protocolVer,
      operationCode: operationCode,
      seq: seq,
    );
  }

  @override
  String toString() {
    return 'PackageHeaderRes{totalSize: $totalSize, headerSize: $headerSize, protocolVer: $protocolVer, operationCode: $operationCode, seq: $seq}';
  }
}

abstract class Message {
  String toJsonStr();
}

class AuthMessage implements Message {
  int roomid;
  int uid;
  int protover;
  String platform;
  int type;
  String key;

  AuthMessage({
    required this.roomid,
    required this.uid,
    required this.protover,
    required this.platform,
    required this.type,
    required this.key,
  });

  @override
  String toJsonStr() {
    final message = {
      'roomid': roomid,
      'uid': uid,
      'protover': protover,
      'platform': platform,
      'type': type,
      'key': key,
    };
    return jsonEncode(message);
  }
}

abstract class AbstractPackage<T> {
  PackageHeader header;
  T body;
  Uint8List marshal();
  AbstractPackage({required this.header, required this.body});
}

//认证包
class AuthPackage extends AbstractPackage<Message> {
  AuthPackage({required super.header, required super.body});

  @override
  Uint8List marshal() {
    final json = utf8.encode(body.toJsonStr());
    final buffer = BytesBuilder()
      ..add(header.toBytes(json.length))
      ..add(json);
    return buffer.toBytes();
  }
}

//心跳包
class HeartbeatPackage extends AbstractPackage<dynamic> {
  HeartbeatPackage({required super.header, super.body});

  @override
  Uint8List marshal() {
    return header.toBytes(0);
  }
}

class LiveMessageStream {
  String streamToken;
  int roomId, uid;
  List<String> servers;
  final List<void Function(dynamic obj)> _eventListeners = [];
  LiveMessageStream({
    required this.streamToken,
    required this.roomId,
    required this.uid,
    required this.servers,
  });

  bool _active = true;
  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;
  Timer? _timer;
  final String logTag = "LiveStreamService";

  Future<void> init() async {
    final authPackage = AuthPackage(
      header: const PackageHeader(
        protocolVer: 1,
        operationCode: 7,
        seq: 1,
      ),
      body: AuthMessage(
        roomid: roomId,
        uid: uid,
        protover: 3,
        platform: 'web',
        type: 2,
        key: streamToken,
      ),
    );

    // final marshaledData = authPackage.marshal();
    // logger.d(marshaledData);
    try {
      Future<WebSocketChannel> getSocket() async {
        for (final server in servers) {
          try {
            final channel = WebSocketChannel.connect(Uri.parse(server));
            await channel.ready;
            return channel;
          } catch (_) {}
        }
        throw Exception("all servers connect failed");
      }

      _channel = await getSocket();
      if (!_active) {
        if (kDebugMode) logger.i("$logTag init inactive $hashCode");
        close();
        return;
      }
      // logger
      //   ..d('$logTag ===> TCP连接建立')
      //   ..d('$logTag ===> 发送认证包');
      _socketSubscription = _channel?.stream.listen(
        onData,
        onDone: close,
        onError: (_) => close(),
      );
      _channel?.sink.add(authPackage.marshal());
    } catch (e) {
      SmartDialog.showToast("弹幕地址链接失败: $e");
    }
  }

  /// 一个数据包内连续解析多少条消息就让出一次事件循环
  ///
  /// 直播弹幕洪峰时一个包可能包含上千条消息, 若一次性同步处理完, 会长时间
  /// 占满当前 isolate (Android 上同时是 UI 线程与平台线程), 期间输入事件
  /// 无法被分发, 表现为系统弹出 "应用未响应"
  static const int _yieldEvery = 16;

  /// 最多积压多少个待处理的数据包
  ///
  /// 弹幕是实时数据, 处理不过来时丢弃新包比无限积压更合理
  static const int _maxPendingPackets = 8;

  int _pendingPackets = 0;
  Future<void> _processingChain = Future<void>.value();

  /// 串行处理数据包, 保持消息顺序
  void _enqueueMessage(Uint8List data, PackageHeaderRes header) {
    if (_pendingPackets >= _maxPendingPackets) {
      if (kDebugMode) {
        logger.w('$logTag 数据包处理不过来, 丢弃 ${data.length} 字节');
      }
      return;
    }
    _pendingPackets++;
    _processingChain = _processingChain.then((_) async {
      try {
        await _handleMessage(data, header);
      } catch (_) {
      } finally {
        _pendingPackets--;
      }
    });
  }

  Future<void> _handleMessage(Uint8List data, PackageHeaderRes header) async {
    switch (header.protocolVer) {
      case 0:
      case 1:
        await _processingData(data);
        return;
      case 2:
        await _processingData(
          ZLibDecoder().convert(Uint8List.sublistView(data, 0x10)),
        );
        return;
      case 3:
        await _processingData(
          const BrotliDecoder().convert(Uint8List.sublistView(data, 0x10)),
        );
        return;
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  Future<void> _processingData(List<int> value) async {
    // zlib/brotli 解压出来的是普通 List<int>, 统一成 Uint8List 后才能零拷贝切分视图
    final data = value is Uint8List ? value : Uint8List.fromList(value);
    var offset = 0;
    var count = 0;
    while (offset < data.length) {
      // 只取视图, 避免每个子包都复制一次剩余数据 (原实现是 O(n^2) 拷贝)
      final subHeader = PackageHeaderRes.fromBytesData(
        Uint8List.sublistView(data, offset),
      );
      // 防御非法包头, 避免空转或越界
      if (subHeader == null ||
          subHeader.totalSize <= subHeader.headerSize ||
          offset + subHeader.totalSize > data.length) {
        break;
      }
      try {
        final msgBody = utf8.decode(
          Uint8List.sublistView(
            data,
            offset + subHeader.headerSize,
            offset + subHeader.totalSize,
          ),
        );
        for (final f in _eventListeners) {
          f(jsonDecode(msgBody));
        }
      } catch (_) {}
      offset += subHeader.totalSize;
      if (++count % _yieldEvery == 0) {
        if (!_active) {
          return;
        }
        // 让出事件循环, 使输入等平台消息有机会被处理
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<void> _heartBeat() async {
    if (!_active) {
      if (kDebugMode) logger.i("$logTag init heartBeat inactive $hashCode");
      close();
      return;
    }
    if (kDebugMode) logger.i("$logTag 直播间信息流认证成功 $hashCode");
    int heartBeatCount = 1;
    _timer ??= Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_active) {
        if (kDebugMode) logger.i("$logTag heartBeat inactive $hashCode");
        timer.cancel();
        close();
        return;
      }
      if (kDebugMode) logger.i("$logTag heartBeat $hashCode");
      final package = HeartbeatPackage(
        header: PackageHeader(
          protocolVer: 1,
          operationCode: 2,
          seq: heartBeatCount,
        ),
      );
      try {
        _channel?.sink.add(package.marshal());
      } catch (_) {
        timer.cancel();
      }
      heartBeatCount++;
    });
  }

  void addEventListener(void Function(dynamic) func) {
    _eventListeners.add(func);
  }

  @pragma('vm:notify-debugger-on-exception')
  void onData(dynamic data) {
    final header = PackageHeaderRes.fromBytesData(data as Uint8List);
    if (header == null) {
      return;
    }
    //心跳包回复不用处理
    if (header.operationCode == 3) return;
    if (header.operationCode == 8) {
      _heartBeat();
    }
    _enqueueMessage(data as Uint8List, header);
  }

  void close() {
    _active = false;
    if (kDebugMode) logger.i("$logTag close $hashCode");
    _timer?.cancel();
    _timer = null;
    _eventListeners.clear();
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _channel?.sink.close();
    _channel = null;
  }
}
