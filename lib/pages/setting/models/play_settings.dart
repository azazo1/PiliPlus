import 'dart:io' show Platform;

import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/models/common/super_chat_type.dart';
import 'package:PiliPlus/models/common/video/subtitle_pref_type.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/pages/fullscreen_sc_size.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/slider_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/models/bottom_progress_behavior.dart';
import 'package:PiliPlus/plugin/pl_player/models/fullscreen_mode.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

List<SettingsModel> get playSettings => [
  const SwitchModel(
    title: '弹幕开关',
    subtitle: '是否展示弹幕',
    leading: Icon(CustomIcons.dm_settings),
    setKey: SettingBoxKey.enableShowDanmaku,
    defaultVal: true,
  ),
  if (PlatformUtils.isMobile)
    const SwitchModel(
      title: '启用点击弹幕',
      subtitle: '点击弹幕悬停，支持点赞、复制、举报操作',
      leading: Icon(Icons.touch_app_outlined),
      setKey: SettingBoxKey.enableTapDm,
      defaultVal: true,
    ),
  NormalModel(
    onTap: (context, setState) => Get.toNamed('/playSpeedSet'),
    leading: const Icon(Icons.speed_outlined),
    title: '倍速设置',
    subtitle: '设置视频播放速度',
  ),
  if (Platform.isAndroid)
    NormalModel(
      onTap: _showAngleDegreesDialog,
      leading: const Icon(MdiIcons.angleAcute),
      title: '倾斜角度阈值',
      getSubtitle: () => '当前:「${Pref.angleDegrees}°」',
    ),
  const SwitchModel(
    title: '自动播放',
    subtitle: '进入详情页自动播放',
    leading: Icon(Icons.motion_photos_auto_outlined),
    setKey: SettingBoxKey.autoPlayEnable,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '全屏显示锁定按钮',
    leading: Icon(Icons.lock_outline),
    setKey: SettingBoxKey.showFsLockBtn,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '全屏显示截图按钮',
    leading: Icon(Icons.photo_camera_outlined),
    setKey: SettingBoxKey.showFsScreenshotBtn,
    defaultVal: true,
  ),
  SwitchModel(
    title: '全屏显示电池电量',
    leading: const Icon(Icons.battery_3_bar),
    setKey: SettingBoxKey.showBatteryLevel,
    defaultVal: PlatformUtils.isMobile,
  ),
  const SwitchModel(
    title: '双击快退/快进',
    subtitle: '左侧双击快退/右侧双击快进，关闭则双击均为暂停/播放',
    leading: Icon(Icons.touch_app_outlined),
    setKey: SettingBoxKey.enableQuickDouble,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '左右侧滑动调节亮度/应用内音量',
    subtitle: '右侧上下滑动调节播放器内音量，不影响系统音量',
    leading: Icon(MdiIcons.tuneVerticalVariant),
    setKey: SettingBoxKey.enableSlideVolumeBrightness,
    defaultVal: true,
  ),
  if (Platform.isAndroid)
    const SwitchModel(
      title: '调节系统亮度',
      leading: Icon(Icons.brightness_6_outlined),
      setKey: SettingBoxKey.setSystemBrightness,
      defaultVal: false,
    ),
  const SwitchModel(
    title: '中间滑动进入/退出全屏',
    leading: Icon(MdiIcons.panVertical),
    setKey: SettingBoxKey.enableSlideFS,
    defaultVal: true,
  ),
  if (PlatformUtils.isMobile)
    NormalModel(
      title: '播放器音量',
      leading: const Icon(Icons.volume_up),
      getSubtitle: () => '当前:「${Pref.playerVolume.toStringAsFixed(0)}%」',
      onTap: showPlayerVolumeDialog,
    )
  else
    NormalModel(
      title: '最高音量',
      leading: const Icon(Icons.volume_up),
      getSubtitle: () => '当前:「${(Pref.maxVolume * 100).toStringAsFixed(0)}%」',
      onTap: _showMaxVolumeDialog,
    ),
  getVideoFilterSelectModel(
    title: '双击快进/快退时长',
    suffix: 's',
    key: SettingBoxKey.fastForBackwardDuration,
    values: [5, 10, 15],
    defaultValue: 10,
    isFilter: false,
  ),
  const WidgetModel(
    title: '滑动快进/快退设置',
    subtitle:
        '滑动快进/快退使用相对时长, 滑动快进/快退时长, 短视频拖动按相对时长, 短视频拖动阈值',
    child: _RelativeSlideSettings(),
  ),
  NormalModel(
    title: '自动启用字幕',
    leading: const Icon(Icons.closed_caption_outlined),
    getSubtitle: () => '当前选择偏好：${Pref.subtitlePreferenceV2.desc}',
    onTap: _showSubtitleDialog,
  ),
  if (PlatformUtils.isDesktop)
    SwitchModel(
      title: '最小化时暂停/还原时播放',
      leading: const Icon(Icons.pause_circle_outline),
      setKey: SettingBoxKey.pauseOnMinimize,
      defaultVal: false,
      onChanged: (value) {
        try {
          Get.find<MainController>().pauseOnMinimize = value;
        } catch (_) {}
      },
    ),
  const SwitchModel(
    title: '启用键盘控制',
    leading: Icon(Icons.keyboard_alt_outlined),
    setKey: SettingBoxKey.keyboardControl,
    defaultVal: true,
  ),
  NormalModel(
    title: 'SuperChat (醒目留言) 显示类型',
    leading: const Icon(Icons.live_tv),
    getSubtitle: () => '当前:「${Pref.superChatType.title}」',
    onTap: _showSuperChatDialog,
  ),
  NormalModel(
    title: '全屏 SC 大小',
    subtitle: 'SuperChat (醒目留言) 大小设置',
    leading: const Icon(Icons.open_in_full),
    onTap: (_, _) => Get.to(const FullScreenScSize()),
  ),
  const SwitchModel(
    title: '竖屏扩大展示',
    subtitle: '小屏竖屏视频宽高比由16:9扩大至1:1（不支持收起）；横屏适配时，扩大至9:16',
    leading: Icon(Icons.expand_outlined),
    setKey: SettingBoxKey.enableVerticalExpand,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '自动全屏',
    subtitle: '视频开始播放时进入全屏',
    leading: Icon(Icons.fullscreen_outlined),
    setKey: SettingBoxKey.enableAutoEnter,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '自动退出全屏',
    subtitle: '视频结束播放时退出全屏',
    leading: Icon(Icons.fullscreen_exit_outlined),
    setKey: SettingBoxKey.enableAutoExit,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '延长播放控件显示时间',
    subtitle: '开启后延长至30秒，便于屏幕阅读器滑动切换控件焦点',
    leading: Icon(Icons.timer_outlined),
    setKey: SettingBoxKey.enableLongShowControl,
    defaultVal: false,
  ),
  if (PlatformUtils.isMobile)
    const SwitchModel(
      title: '后台播放',
      subtitle: '进入后台时继续播放',
      leading: Icon(Icons.motion_photos_pause_outlined),
      setKey: SettingBoxKey.continuePlayInBackground,
      defaultVal: false,
    ),
  if (Platform.isAndroid) ...[
    SwitchModel(
      title: '后台画中画',
      subtitle: '进入后台时以小窗形式（PiP）播放',
      leading: const Icon(Icons.picture_in_picture_outlined),
      setKey: SettingBoxKey.autoPiP,
      defaultVal: false,
      onChanged: (val) {
        if (val && !videoPlayerServiceHandler!.enableBackgroundPlay) {
          SmartDialog.showToast('建议开启后台音频服务');
        }
      },
    ),
    const SwitchModel(
      title: '画中画不加载弹幕',
      subtitle: '当弹幕开关开启时，小窗屏蔽弹幕以获得较好的体验',
      leading: Icon(CustomIcons.dm_off),
      setKey: SettingBoxKey.pipNoDanmaku,
      defaultVal: false,
    ),
  ],
  const SwitchModel(
    title: '全屏手势反向',
    subtitle: '默认播放器中部向上滑动进入全屏，向下退出\n开启后向下全屏，向上退出',
    leading: Icon(Icons.swap_vert),
    setKey: SettingBoxKey.fullScreenGestureReverse,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '全屏展示点赞/投币/收藏等操作按钮',
    leading: Icon(MdiIcons.dotsHorizontalCircleOutline),
    setKey: SettingBoxKey.showFSActionItem,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '观看人数',
    subtitle: '展示同时在看人数',
    leading: Icon(Icons.people_outlined),
    setKey: SettingBoxKey.enableOnlineTotal,
    defaultVal: false,
  ),
  NormalModel(
    title: '默认全屏方向',
    leading: const Icon(Icons.open_with_outlined),
    getSubtitle: () => '当前全屏方向：${Pref.fullScreenMode.desc}',
    onTap: _showFullScreenModeDialog,
  ),
  NormalModel(
    title: '底部进度条展示',
    leading: const Icon(Icons.border_bottom_outlined),
    getSubtitle: () => '当前展示方式：${Pref.btmProgressBehavior.desc}',
    onTap: _showProgressBehaviorDialog,
  ),
  if (PlatformUtils.isMobile)
    SwitchModel(
      title: '后台音频服务',
      subtitle: '避免画中画没有播放暂停功能',
      leading: const Icon(Icons.volume_up_outlined),
      setKey: SettingBoxKey.enableBackgroundPlay,
      defaultVal: true,
      onChanged: (value) =>
          videoPlayerServiceHandler!.enableBackgroundPlay = value,
    ),
  PopupModel(
    title: '播放顺序',
    leading: const Icon(Icons.repeat),
    value: () => Pref.playRepeat,
    items: PlayRepeat.values,
    onSelected: (value, setState) => GStorage.video
        .put(VideoBoxKey.playRepeat, value.index)
        .whenComplete(setState),
  ),
  const SwitchModel(
    title: '播放器设置仅对当前生效',
    subtitle: '弹幕、字幕及部分设置中没有的设置除外',
    leading: Icon(Icons.video_settings_outlined),
    setKey: SettingBoxKey.tempPlayerConf,
    defaultVal: false,
  ),
];

class _RelativeSlideSettings extends StatefulWidget {
  const _RelativeSlideSettings();

  @override
  State<_RelativeSlideSettings> createState() => _RelativeSlideSettingsState();
}

class _RelativeSlideSettingsState extends State<_RelativeSlideSettings> {
  late bool _useRelativeSlide;
  late bool _enableRelativeSlideForShortVideo;
  late int _relativeSlideShortVideoThreshold;

  @override
  void initState() {
    super.initState();
    _useRelativeSlide = Pref.useRelativeSlide;
    _enableRelativeSlideForShortVideo = Pref.enableRelativeSlideForShortVideo;
    _relativeSlideShortVideoThreshold = Pref.relativeSlideShortVideoThreshold;
  }

  String _sliderDurationSubtitle() {
    const baseSubtitle = '从播放器一端滑到另一端的快进/快退时长';
    if (_useRelativeSlide || !_enableRelativeSlideForShortVideo) {
      return baseSubtitle;
    }
    return '$baseSubtitle, 长视频按秒数, 短于$_relativeSlideShortVideoThreshold s的视频按百分比调整';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SetSwitchItem(
          title: '滑动快进/快退使用相对时长',
          leading: const Icon(Icons.swap_horiz_outlined),
          setKey: SettingBoxKey.useRelativeSlide,
          defaultVal: false,
          onChanged: (value) => setState(() => _useRelativeSlide = value),
        ),
        getVideoFilterSelectModel(
          title: '滑动快进/快退时长',
          subtitle: _sliderDurationSubtitle(),
          suffix: _useRelativeSlide ? '%' : 's',
          key: SettingBoxKey.sliderDuration,
          values: [25, 50, 90, 100],
          defaultValue: 90,
          isFilter: false,
        ).widget,
        if (!_useRelativeSlide) ...[
          SetSwitchItem(
            title: '短视频拖动按相对时长',
            subtitle: '关闭全局相对时长后, 短于阈值的视频拖动时改按相对时长调整',
            leading: const Icon(Icons.smart_display_outlined),
            setKey: SettingBoxKey.enableRelativeSlideForShortVideo,
            defaultVal: false,
            onChanged: (value) => setState(
              () => _enableRelativeSlideForShortVideo = value,
            ),
          ),
          NormalItem(
            title: '短视频拖动阈值',
            subtitle:
                '当前阈值: ${_relativeSlideShortVideoThreshold}s, 仅在上方开关开启时生效',
            leading: const Icon(Icons.timelapse_outlined),
            onTap: (context, _) async {
              final result = await showDialog<int>(
                context: context,
                builder: (context) => _RelativeSlideThresholdDialog(
                  value: _relativeSlideShortVideoThreshold,
                ),
              );
              if (result == null) {
                return;
              }
              await GStorage.setting.put(
                SettingBoxKey.relativeSlideShortVideoThreshold,
                result,
              );
              if (!mounted) {
                return;
              }
              setState(() => _relativeSlideShortVideoThreshold = result);
            },
          ),
        ],
      ],
    );
  }
}

class _RelativeSlideThresholdDialog extends StatefulWidget {
  const _RelativeSlideThresholdDialog({required this.value});

  final int value;

  @override
  State<_RelativeSlideThresholdDialog> createState() =>
      _RelativeSlideThresholdDialogState();
}

class _RelativeSlideThresholdDialogState
    extends State<_RelativeSlideThresholdDialog> {
  static const int _minValue = 10;
  static const int _sliderMaxValue = 600;

  late int _value;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _value = widget.value < _minValue ? _minValue : widget.value;
    _controller = TextEditingController(text: _value.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _sliderValue => _value.clamp(_minValue, _sliderMaxValue) as int;

  void _syncText() {
    final text = _value.toString();
    if (_controller.text == text) {
      return;
    }
    _controller.value = _controller.value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }

  int? _parseInput() {
    final value = int.tryParse(_controller.text);
    if (value == null || value < _minValue) {
      return null;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('短视频拖动阈值'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      content: Column(
        spacing: 16,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('短于该时长的视频, 拖动进度条时改按相对时长调整'),
          Slider(
            padding: EdgeInsets.zero,
            value: _sliderValue.toDouble(),
            min: _minValue.toDouble(),
            max: _sliderMaxValue.toDouble(),
            divisions: _sliderMaxValue - _minValue,
            label: '${_value}s',
            onChanged: (value) => setState(() {
              _value = value.round();
              _syncText();
            }),
          ),
          TextFormField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '阈值',
              hintText: '>= 10',
              suffixText: 's',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null && parsed >= _minValue && parsed != _value) {
                setState(() => _value = parsed);
              }
            },
          ),
          const Text('滑动条仅用于快速选择 10 - 600s, 输入框可填写更大的值'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            final parsed = _parseInput();
            if (parsed == null) {
              SmartDialog.showToast('请输入大于等于 10 的整数');
              return;
            }
            Navigator.pop(context, parsed);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

Future<void> _showSubtitleDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<SubtitlePrefType>(
    context: context,
    builder: (context) => SelectDialog<SubtitlePrefType>(
      title: '字幕选择偏好',
      value: Pref.subtitlePreferenceV2,
      values: SubtitlePrefType.values.map((e) => (e, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(
      SettingBoxKey.subtitlePreferenceV2,
      res.index,
    );
    setState();
  }
}

Future<void> _showSuperChatDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<SuperChatType>(
    context: context,
    builder: (context) => SelectDialog<SuperChatType>(
      title: 'SuperChat (醒目留言) 显示类型',
      value: Pref.superChatType,
      values: SuperChatType.values.map((e) => (e, e.title)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.superChatType, res.index);
    setState();
  }
}

Future<void> _showFullScreenModeDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<FullScreenMode>(
    context: context,
    builder: (context) => SelectDialog<FullScreenMode>(
      title: '默认全屏方向',
      value: Pref.fullScreenMode,
      values: FullScreenMode.values.map((e) => (e, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.fullScreenMode, res.index);
    setState();
  }
}

Future<void> _showProgressBehaviorDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<BtmProgressBehavior>(
    context: context,
    builder: (context) => SelectDialog<BtmProgressBehavior>(
      title: '底部进度条展示',
      value: Pref.btmProgressBehavior,
      values: BtmProgressBehavior.values.map((e) => (e, e.desc)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(
      SettingBoxKey.btmProgressBehavior,
      res.index,
    );
    setState();
  }
}

Future<void> _showAngleDegreesDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: const Text('倾斜角度阈值'),
      min: 10.0,
      max: 90.0,
      divisions: 90,
      precise: 0,
      value: Pref.angleDegrees.toDouble(),
      suffix: '°',
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.angleDegrees, res.toInt());
    setState();
  }
}

Future<void> showPlayerVolumeDialog(
  BuildContext context,
  VoidCallback setState, {
  ValueChanged<double>? onChanged,
}) {
  return showVolumeDialog(
    context,
    title: const Text('播放器音量'),
    value: Pref.playerVolume,
    onChanged: (value) => GStorage.setting
        .put(SettingBoxKey.playerVolume, value)
        .whenComplete(() {
          setState();
          onChanged?.call(value);
        }),
  );
}

Future<void> _showMaxVolumeDialog(
  BuildContext context,
  VoidCallback setState,
) {
  return showVolumeDialog(
    context,
    title: const Text('最高音量'),
    value: Pref.maxVolume * 100,
    onChanged: (rawValue) {
      final maxVolume = (rawValue / 100).toPrecision(2);
      if (Pref.desktopVolume > maxVolume) {
        GStorage.setting.put(SettingBoxKey.desktopVolume, maxVolume);
      }
      GStorage.setting
          .put(SettingBoxKey.maxVolume, maxVolume)
          .whenComplete(setState);
    },
  );
}

const kMinVolume = 100.0;
const kMaxVolume = 300.0;

Future<void> showVolumeDialog(
  BuildContext context, {
  required Widget title,
  required double value,
  required ValueChanged<double> onChanged,
}) async {
  final res = await showDialog<double>(
    context: context,
    builder: (context) => SliderDialog(
      title: title,
      min: kMinVolume,
      max: kMaxVolume,
      divisions: 40,
      precise: 0,
      value: value,
      suffix: '%',
    ),
  );
  if (res != null) {
    onChanged(res);
  }
}
