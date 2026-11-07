import 'dart:io';

import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'ui/dialogs.dart';

/// 桌面端窗口与托盘：拦截关闭按钮、提供托盘菜单。
/// 只在 Windows 上启用，Android 完全不会走到这里。
class DesktopShell {
  static SystemTray? _tray;
  static bool _quitting = false;
  static bool _initialized = false;

  static Future<void> init({
    required AppState state,
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (_initialized || !Platform.isWindows) return;
    _initialized = true;

    windowManager.addListener(
      _CloseHandler(state: state, navigatorKey: navigatorKey),
    );

    try {
      final tray = SystemTray();
      await tray.initSystemTray(
        title: 'WeLearn 助手',
        iconPath: 'assets/tray.ico',
        toolTip: 'WeLearn 助手',
      );
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: '打开主界面', onClicked: (_) => showWindow()),
        MenuItemLabel(
          label: '重新扫描',
          onClicked: (_) async {
            await showWindow();
            final cid = state.currentCid;
            if (cid != null && !state.running) await state.loadCourse(cid);
          },
        ),
        MenuSeparator(),
        MenuItemLabel(label: '退出', onClicked: (_) => quit()),
      ]);
      await tray.setContextMenu(menu);
      tray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) showWindow();
      });
      _tray = tray;
      traceClose('tray ready');
    } catch (e) {
      // 托盘起不来不影响主窗口使用
      traceClose('tray failed: $e');
      debugPrint('托盘初始化失败：$e');
    }
  }

  static Future<void> showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  static Future<void> hideToTray() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  static Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await _tray?.destroy();
    } catch (_) {
      // 托盘销毁失败也要能退出
    }
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}

class _CloseHandler extends WindowListener {
  _CloseHandler({required this.state, required this.navigatorKey});

  final AppState state;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  void onWindowClose() async {
    traceClose('onWindowClose action=${state.closeAction}');
    final action = state.closeAction;
    if (action == 'tray') {
      await DesktopShell.hideToTray();
      return;
    }
    if (action == 'quit') {
      await DesktopShell.quit();
      return;
    }

    // 先让窗口到前台，否则对话框会挂在不可见的窗口上
    await DesktopShell.showWindow();
    final context = navigatorKey.currentContext;
    if (context == null) {
      await DesktopShell.hideToTray();
      return;
    }

    // navigatorKey 指向根导航器，窗口被隐藏时这个 context 依然有效
    // ignore: use_build_context_synchronously
    final decision = await showCloseDialog(context);
    if (decision == null) return; // 取消：保持打开

    if (decision.remember) {
      await state.setCloseAction(decision.toTray ? 'tray' : 'quit');
    }
    if (decision.toTray) {
      await DesktopShell.hideToTray();
    } else {
      await DesktopShell.quit();
    }
  }
}

/// 排查用：把关键步骤写到临时文件，方便在没有控制台的情况下确认
void traceClose(String message) {
  if (!Platform.isWindows) return;
  try {
    final file = File('${Directory.systemTemp.path}/welearn_close.log');
    file.writeAsStringSync(
      '${DateTime.now().toIso8601String()} $message\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // 排查日志失败不影响功能
  }
}
