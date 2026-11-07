import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 手机端「后台运行」能力的 Flutter 侧入口。
///
/// 桌面的托盘在安卓上不存在，等价物是 **Wake Lock + 前台服务常驻通知**：
/// Wake Lock 保证息屏后 CPU 不被冻结，常驻通知让进程不被系统回收、也让用户
/// 随时能从通知栏回到应用。这里不引入新插件，直接和 `MainActivity` 通信。
class MobileBackground {
  const MobileBackground._();

  static const MethodChannel _channel = MethodChannel(
    'cn.autowelearn.welearn/background',
  );

  /// 只有安卓有这套能力；在桌面/测试里所有调用都是空操作。
  static bool get supported => defaultTargetPlatform == TargetPlatform.android;

  /// 把两个开关同步给原生服务。两个都关时会停掉服务并释放锁。
  static Future<void> apply({
    required bool keepAwake,
    required bool persistent,
  }) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setMode', <String, Object>{
        'keepAwake': keepAwake,
        'persistent': persistent,
      });
    } on PlatformException catch (_) {
      // 旧版 APK 没有原生实现：静默降级，界面上的开关仍能被用户看到
    } on MissingPluginException catch (_) {
      // 同上
    }
  }

  /// 当前权限状态。`null` 表示读不到（非安卓或旧版 APK）。
  static Future<BackgroundPermission?> status() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      if (raw == null) return null;
      return BackgroundPermission(
        wakeLock: raw['wakeLock'] as bool? ?? false,
        notification: raw['notification'] as bool? ?? false,
      );
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  /// 申请 Android 13+ 的通知权限。会等用户在系统弹窗里做完选择再返回。
  static Future<bool> requestNotificationPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }
}

class BackgroundPermission {
  const BackgroundPermission({
    required this.wakeLock,
    required this.notification,
  });
  final bool wakeLock;
  final bool notification;
}
