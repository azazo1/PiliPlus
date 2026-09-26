import 'package:PiliPlus/models/common/enum_with_label.dart';

enum AudioOutput implements EnumWithLabel {
  opensles('OpenSL ES'),
  aaudio('AAudio'),
  audiotrack('AudioTrack'),
  ;

  /// AudioTrack 优先: 命中 OpenSL ES 时本应用会落到独立的 deep buffer 输出,
  /// 与其它应用互抢全局音效链 (例如第三方降音量应用), 音量会被带偏.
  static final defaultValue = '${audiotrack.name},${aaudio.name},${opensles.name}';

  @override
  final String label;
  const AudioOutput(this.label);
}
