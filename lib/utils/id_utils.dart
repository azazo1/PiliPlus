// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/http/member.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter/foundation.dart' show compute;
import 'package:uuid/v4.dart';

abstract final class IdUtils {
  static const XOR_CODE = 23442827791579;
  static const MASK_CODE = 2251799813685247;
  static const MAX_AID = 1 << 51;
  static const BASE = 58;

  static const data =
      'FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf';
  static final invData = {for (final (i, c) in data.codeUnits.indexed) c: i};

  static final bvRegex = RegExp(r'bv1[0-9a-zA-Z]{9}', caseSensitive: false);
  static final bvRegexExact = RegExp(
    r'^bv1[0-9a-zA-Z]{9}$',
    caseSensitive: false,
  );
  static final avRegex = RegExp(r'av(\d+)', caseSensitive: false);
  static final avRegexExact = RegExp(r'^av(\d+)$', caseSensitive: false);
  static final digitOnlyRegExp = RegExp(r'^\d+$');
  static final Map<String, List<int>> _danmakuUidCandidatesCache =
      <String, List<int>>{};
  static final Map<String, Future<List<int>>> _danmakuUidCandidatesTasks =
      <String, Future<List<int>>>{};
  static final Map<String, int?> _danmakuUidCache = <String, int?>{};

  static String _danmakuUidCacheKey(String midHash) =>
      '${LocalCacheKey.danmakuSenderUid}:$midHash';

  static int? _getPersistedDanmakuUid(String midHash) {
    final value = GStorage.localCache.get(_danmakuUidCacheKey(midHash));
    return Utils.safeToInt(value);
  }

  static void _persistDanmakuUid(String midHash, int uid) {
    _danmakuUidCache[midHash] = uid;
    GStorage.localCache.put(_danmakuUidCacheKey(midHash), uid);
  }

  static void swap<T>(List<T> list, int idx1, int idx2) {
    final idx1Value = list[idx1];
    list[idx1] = list[idx2];
    list[idx2] = idx1Value;
  }

  /// av转bv
  static String av2bv(int aid) {
    final bytes = ['B', 'V', '1', '0', '0', '0', '0', '0', '0', '0', '0', '0'];
    int bvIndex = bytes.length - 1;
    int tmp = (MAX_AID | aid) ^ XOR_CODE;
    while (tmp > 0) {
      bytes[bvIndex--] = data[tmp % BASE];
      tmp ~/= BASE;
    }

    swap(bytes, 3, 9);
    swap(bytes, 4, 7);

    return bytes.join();
  }

  /// bv转av
  static int bv2av(String bvid) {
    final bvidArr = bvid.codeUnits.sublist(3);

    swap(bvidArr, 0, 6);
    swap(bvidArr, 1, 4);

    final tmp = bvidArr.fold(0, (pre, char) => pre * BASE + invData[char]!);
    return (tmp & MASK_CODE) ^ XOR_CODE;
  }

  // 匹配
  static AvBvRes matchAvorBv({String? input}) {
    if (input == null || input.isEmpty) {
      return const (av: null, bv: null);
    }
    String? bvid = bvRegex.firstMatch(input)?.group(0);

    late String? aid = avRegex.firstMatch(input)?.group(1);

    if (bvid != null) {
      return (av: null, bv: bvid);
    } else if (aid != null) {
      return (av: int.parse(aid), bv: null);
    }
    return const (av: null, bv: null);
  }

  static String genBuvid3() {
    return '${const UuidV4().generate().toUpperCase()}${Utils.random.nextInt(100000).toString().padLeft(5, "0")}infoc';
  }

  static String genAuroraEid(int uid) {
    if (uid == 0) {
      return '';
    }

    final midByte = ascii.encode(uid.toString());

    const key = 'ad1va46a7lza';
    for (int i = 0; i < midByte.length; i++) {
      midByte[i] ^= key.codeUnitAt(i % key.length);
    }

    String base64Encoded = base64.encode(midByte).replaceAll('=', '');

    return base64Encoded;
  }

  // https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/grpc_api/readme.md#x-bili-trace-id-生成算法
  static String genTraceId() {
    final randomTraceId = StringBuffer(Utils.generateRandomString(24));

    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000) >> 8;

    randomTraceId
      ..write((ts & 0xFFFFFF).toRadixString(16).padLeft(6, '0'))
      ..write(Utils.generateRandomString(2));

    return '${randomTraceId.toString()}:${randomTraceId.toString().substring(16, 32)}:0:0';
  }

  static Future<List<int>> getDanmakuUidCandidates(String midHash) {
    final normalizedMidHash = midHash.toLowerCase();
    if (_danmakuUidCandidatesCache[normalizedMidHash] case final candidates?) {
      return Future<List<int>>.value(candidates);
    }
    return _danmakuUidCandidatesTasks.putIfAbsent(normalizedMidHash, () async {
      try {
        final candidates = await compute(
          _getDanmakuUidCandidatesTask,
          normalizedMidHash,
        );
        _danmakuUidCandidatesCache[normalizedMidHash] = candidates;
        return candidates;
      } finally {
        _danmakuUidCandidatesTasks.remove(normalizedMidHash);
      }
    });
  }

  static Future<int?> resolveDanmakuUid(String midHash) async {
    final normalizedMidHash = midHash.toLowerCase();
    if (_danmakuUidCache.containsKey(normalizedMidHash)) {
      return _danmakuUidCache[normalizedMidHash];
    }
    if (_getPersistedDanmakuUid(normalizedMidHash) case final persistedUid?) {
      return _danmakuUidCache[normalizedMidHash] = persistedUid;
    }

    final candidates = await getDanmakuUidCandidates(normalizedMidHash);
    if (candidates.isEmpty) {
      return _danmakuUidCache[normalizedMidHash] = null;
    }
    if (candidates.length == 1) {
      _persistDanmakuUid(normalizedMidHash, candidates.first);
      return candidates.first;
    }

    for (final uid in candidates) {
      if ((await MemberHttp.memberInfo(mid: uid)).isSuccess) {
        _persistDanmakuUid(normalizedMidHash, uid);
        return uid;
      }
    }

    _persistDanmakuUid(normalizedMidHash, candidates.first);
    return candidates.first;
  }
}

typedef AvBvRes = ({int? av, String? bv});

extension AvBvExt on AvBvRes {
  bool get isNotEmpty => this != const (av: null, bv: null);
}

List<int> _getDanmakuUidCandidatesTask(String midHash) {
  final crc = int.tryParse(midHash, radix: 16);
  if (crc == null) {
    return const <int>[];
  }
  final resolver = _DanmakuUidResolver();
  return resolver
      .crack(crc)
      .where((uid) => getCrc32(ascii.encode(uid.toString()), 0) == crc)
      .toList(growable: false);
}

class _DanmakuUidResolver {
  static const int _poly = 0xEDB88320;
  static const int _uint32Mask = 0xFFFFFFFF;
  static const int _suffixLength = 100000;

  late final Uint32List _crc32Table = _buildCrc32Table();
  late final Uint32List _rainbow0 = _buildRainbow0();
  late final Uint32List _rainbow1 = _buildRainbow1();
  late final Uint32List _rainbowPos = _buildRainbowPos();
  late final Uint32List _rainbowHash = _buildRainbowHash();

  List<int> crack(int mainCrc, {int maxDigits = 10}) {
    final results = <int>[];
    mainCrc = (~mainCrc) & _uint32Mask;
    var baseCrc = _uint32Mask;
    for (var ndigits = 1; ndigits <= maxDigits; ndigits++) {
      baseCrc = _updateCrc(0x30, baseCrc);
      if (ndigits < 6) {
        final firstUid = _pow10(ndigits - 1);
        final lastUid = _pow10(ndigits);
        for (var uid = firstUid; uid < lastUid; uid++) {
          if (mainCrc == ((baseCrc ^ _rainbow0[uid]) & _uint32Mask)) {
            results.add(uid);
          }
        }
        continue;
      }

      final firstPrefix = _pow10(ndigits - 6);
      final lastPrefix = _pow10(ndigits - 5);
      for (var prefix = firstPrefix; prefix < lastPrefix; prefix++) {
        final rem = (mainCrc ^ baseCrc ^ _rainbow1[prefix]) & _uint32Mask;
        for (final suffix in _lookup(rem)) {
          results.add(prefix * _suffixLength + suffix);
        }
      }
    }
    return results;
  }

  Iterable<int> _lookup(int crc) sync* {
    final bucket = crc >>> 16;
    final first = _rainbowPos[bucket];
    final last = _rainbowPos[bucket + 1];
    for (var i = first; i < last; i++) {
      if (_rainbowHash[i << 1] == crc) {
        yield _rainbowHash[(i << 1) | 1];
      }
    }
  }

  Uint32List _buildCrc32Table() {
    final table = Uint32List(256);
    for (var i = 0; i < table.length; i++) {
      var crc = i;
      for (var j = 0; j < 8; j++) {
        crc = (crc & 1) != 0 ? ((crc >>> 1) ^ _poly) : (crc >>> 1);
      }
      table[i] = crc & _uint32Mask;
    }
    return table;
  }

  Uint32List _buildRainbow0() {
    final rainbow = Uint32List(_suffixLength);
    for (var i = 0; i < rainbow.length; i++) {
      rainbow[i] = _computeDigits(i);
    }
    return rainbow;
  }

  Uint32List _buildRainbow1() {
    final rainbow = Uint32List(_suffixLength);
    for (var i = 0; i < rainbow.length; i++) {
      rainbow[i] = _appendZeros(_rainbow0[i], 5);
    }
    return rainbow;
  }

  Uint32List _buildRainbowPos() {
    final positions = Uint32List(65537);
    for (final crc in _rainbow0) {
      positions[crc >>> 16]++;
    }
    for (var i = 1; i < positions.length; i++) {
      positions[i] += positions[i - 1];
    }
    return positions;
  }

  Uint32List _buildRainbowHash() {
    final positions = Uint32List.fromList(_rainbowPos);
    final hash = Uint32List(_suffixLength * 2);
    for (var i = 0; i < _rainbow0.length; i++) {
      final bucket = _rainbow0[i] >>> 16;
      positions[bucket] = positions[bucket] - 1;
      final slot = positions[bucket];
      hash[slot << 1] = _rainbow0[i];
      hash[(slot << 1) | 1] = i;
    }
    return hash;
  }

  int _computeDigits(int value, [int init = 0]) {
    var crc = init;
    for (final code in '$value'.codeUnits) {
      crc = _updateCrc(code - 0x30, crc);
    }
    return crc;
  }

  int _appendZeros(int crc, int count) {
    for (var i = 0; i < count; i++) {
      crc = _updateCrc(0, crc);
    }
    return crc;
  }

  int _updateCrc(int byte, int crc) {
    return ((crc >>> 8) ^ _crc32Table[(crc & 0xFF) ^ byte]) & _uint32Mask;
  }

  int _pow10(int exponent) {
    var value = 1;
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
    return value;
  }
}
