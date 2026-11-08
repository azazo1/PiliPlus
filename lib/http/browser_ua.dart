import 'package:PiliPlus/utils/platform_utils.dart';

abstract final class BrowserUa {
  static String get platform => PlatformUtils.isMobile ? mob : pc;

  static const pc =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.2 Safari/605.1.15';

  static const mob =
      'Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.101 Mobile Safari/537.36';

  /// 账号中心的 H5 页面用 UA 里是否包含 BiliApp 来判断当前是否在官方
  /// App 内, 不在 App 内时扫码确认页不会初始化确认按钮.
  static const app =
      'Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.101 Mobile Safari/537.36 BiliApp/8440300';
}
