import 'dart:convert';

import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:collection/collection.dart' show IterableExtension;

enum SubtitleFormat implements EnumWithLabel {
  json('JSON'),
  vtt('WEBVTT'),
  srt('SRT');

  @override
  final String label;
  const SubtitleFormat(this.label);
}

class SubtitleCue {
  const SubtitleCue({
    required this.from,
    required this.to,
    required this.content,
  });

  final double from;
  final double to;
  final String content;

  bool contains(double seconds) => seconds >= from && seconds < to;
}

abstract final class SubtitleUtils {
  static final _vttTime = RegExp(
    r'(?:(\d+):)?(\d{2}):(\d{2})[.,](\d{1,3})',
  );
  static final _vttArrow = RegExp(r'\s*-->\s*');
  static final _srtIndex = RegExp(r'^\d+$');
  static final _assDialogue = RegExp(
    r'^Dialogue:\s*(?:Marked=)?\d+,'
    r'(\d+:\d{2}:\d{2}(?:\.\d+)?),'
    r'(\d+:\d{2}:\d{2}(?:\.\d+)?),'
    r'(?:[^,]*,){6}(.*)$',
  );
  static final _assOverride = RegExp(r'\{.*?\}');

  static String _vttTimecode(num seconds) {
    final int h = seconds ~/ 3600;
    seconds %= 3600;
    final int m = seconds ~/ 60;
    seconds %= 60;
    final String sms = seconds.toStringAsFixed(3).padLeft(6, '0');
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:$sms";
  }

  static String json2Vtt(List list) {
    final sb = StringBuffer('WEBVTT\n\n')
      ..writeAll(
        list.map(
          (item) =>
              '${_vttTimecode(item['from'])} --> ${_vttTimecode(item['to'])}\n${item['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }

  static String _srtTimecode(num seconds) {
    final int h = seconds ~/ 3600;
    seconds %= 3600;
    final int m = seconds ~/ 60;
    seconds %= 60;
    final int s = seconds.toInt();
    final int ms = ((seconds - s) * 1000).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')},${ms.toString().padLeft(3, '0')}';
  }

  static String json2Srt(List list) {
    final sb = StringBuffer()
      ..writeAll(
        list.mapIndexed(
          (i, e) =>
              '${i + 1}\n${_srtTimecode(e['from'])} --> ${_srtTimecode(e['to'])}\n${e['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }

  static List<SubtitleCue> json2Cues(List list) {
    final cues = <SubtitleCue>[];
    for (final item in list) {
      if (item is! Map<String, dynamic> && item is! Map) continue;
      final content = item['content']?.toString().trim() ?? '';
      if (content.isEmpty) continue;
      final from = _toSeconds(item['from']);
      final to = _toSeconds(item['to']);
      if (from == null) continue;
      cues.add(
        SubtitleCue(
          from: from,
          to: to ?? from,
          content: content,
        ),
      );
    }
    return cues;
  }

  static List<SubtitleCue> text2Cues(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return const [];
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['body'] is List) {
          return json2Cues(decoded['body'] as List);
        }
        if (decoded is List) {
          return json2Cues(decoded);
        }
      } catch (_) {}
    }
    if (text.startsWith('WEBVTT')) {
      return _vtt2Cues(text);
    }
    if (text.contains('[Events]') || text.contains('Dialogue:')) {
      return _ass2Cues(text);
    }
    return _srt2Cues(text);
  }

  static List<SubtitleCue> _vtt2Cues(String text) {
    final cues = <SubtitleCue>[];
    final blocks = text.split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final lines = block
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final cue = _cueFromTimedLines(lines);
      if (cue != null) cues.add(cue);
    }
    return cues;
  }

  static List<SubtitleCue> _srt2Cues(String text) {
    final cues = <SubtitleCue>[];
    final blocks = text.split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      var lines = block
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isNotEmpty && _srtIndex.hasMatch(lines.first)) {
        lines = lines.sublist(1);
      }
      final cue = _cueFromTimedLines(lines);
      if (cue != null) cues.add(cue);
    }
    return cues;
  }

  static List<SubtitleCue> _ass2Cues(String text) {
    final cues = <SubtitleCue>[];
    for (final rawLine in text.split('\n')) {
      final match = _assDialogue.firstMatch(rawLine.trim());
      if (match == null) continue;
      final from = _parseAssTime(match.group(1)!);
      final to = _parseAssTime(match.group(2)!);
      final content = match
          .group(3)!
          .replaceAll(_assOverride, '')
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .trim();
      if (from == null || content.isEmpty) continue;
      cues.add(SubtitleCue(from: from, to: to ?? from, content: content));
    }
    return cues;
  }

  static SubtitleCue? _cueFromTimedLines(List<String> lines) {
    final timeIndex = lines.indexWhere((line) => line.contains('-->'));
    if (timeIndex < 0 || timeIndex + 1 >= lines.length) return null;
    final times = lines[timeIndex].split(_vttArrow);
    if (times.length < 2) return null;
    final from = _parseVttTime(times[0]);
    final to = _parseVttTime(times[1].split(' ').first);
    final content = lines.sublist(timeIndex + 1).join('\n').trim();
    if (from == null || content.isEmpty) return null;
    return SubtitleCue(from: from, to: to ?? from, content: content);
  }

  static double? _parseVttTime(String raw) {
    final match = _vttTime.firstMatch(raw.trim());
    if (match == null) return null;
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    final fraction = match.group(4) ?? '0';
    final millis = int.tryParse(fraction.padRight(3, '0')) ?? 0;
    return hours * 3600 + minutes * 60 + seconds + millis / 1000;
  }

  static double? _parseAssTime(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 3) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = double.tryParse(parts[2]);
    if (hours == null || minutes == null || seconds == null) return null;
    return hours * 3600 + minutes * 60 + seconds;
  }

  static double? _toSeconds(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
