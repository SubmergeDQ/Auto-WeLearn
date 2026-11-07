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

  /// 通知栏「开始 / 停止」按钮的回调。原生侧通过同一个 Channel 反向调用。
  static void init({void Function(String action)? onTaskAction}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'taskAction') {
        final action = '${call.arguments}';
        onTaskAction?.call(action);
      }
      return null;
    });
  }

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

  /// 把当前任务进度推送到常驻通知。
  /// [current] 是「第几节」，[total] 是队列总数；[text] 为通知正文，
  /// [detail] 为次要说明（例如本节剩余时间与心跳次数）。
  static Future<void> updateTask({
    required bool running,
    required int current,
    required int total,
    required String text,
    String detail = '',
  }) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('updateTask', <String, Object>{
        'running': running,
        'current': current,
        'total': total,
        'text': text,
        'detail': detail,
      });
    } on PlatformException catch (_) {
      // 原生服务不可用时静默降级
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
        batteryUnrestricted: raw['batteryOptimized'] as bool? ?? false,
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

  /// 打开系统的「电池优化」授权弹窗，把应用加入无限制白名单。
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } on PlatformException catch (_) {
      // 系统没有该页面时原生侧会回退到电池优化列表
    } on MissingPluginException catch (_) {
      // 同上
    }
  }

  /// 打开厂商的「自启动 / 后台活动」管理页；识别不到时回退到应用详情。
  static Future<void> openAutoStartSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openAutoStartSettings');
    } on PlatformException catch (_) {
      // 忽略：用户可手动在系统设置中找到
    } on MissingPluginException catch (_) {
      // 同上
    }
  }

  /// 应用详情页，用于手动管理后台锁定、自启动等厂商设置。
  static Future<void> openAppSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on PlatformException catch (_) {
      // 同上
    } on MissingPluginException catch (_) {
      // 同上
    }
  }

  /// 调起系统安装器安装已下载的 APK。
  static Future<ApkInstallOutcome> installApk(String path) async {
    if (!supported) return ApkInstallOutcome.failed;
    try {
      final outcome = await _channel.invokeMethod<String>('installApk', {
        'path': path,
      });
      return switch (outcome) {
        'started' => ApkInstallOutcome.started,
        'permission' => ApkInstallOutcome.permissionRequired,
        _ => ApkInstallOutcome.failed,
      };
    } on PlatformException catch (_) {
      return ApkInstallOutcome.failed;
    } on MissingPluginException catch (_) {
      return ApkInstallOutcome.failed;
    }
  }
}

class BackgroundPermission {
  const BackgroundPermission({
    required this.wakeLock,
    required this.notification,
    required this.batteryUnrestricted,
  });
  final bool wakeLock;
  final bool notification;

  /// true 表示已加入电池优化白名单（无限制）。
  final bool batteryUnrestricted;
}

enum ApkInstallOutcome { started, permissionRequired, failed }
