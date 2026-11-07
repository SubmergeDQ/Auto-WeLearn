import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'desktop_shell.dart';
import 'mobile_background.dart';
import 'theme.dart';
import 'ui/app_scope.dart';
import 'ui/workbench.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final state = AppState();
  final navigatorKey = GlobalKey<NavigatorState>();

  // 通知栏「开始 / 停止」按钮回到 Dart 后直接驱动同一套运行状态
  MobileBackground.init(
    onTaskAction: (action) {
      switch (action) {
        case 'stop':
          state.stopRun();
          break;
        case 'start':
          state.startRun();
          break;
      }
    },
  );

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 840),
      minimumSize: Size(1024, 640),
      center: true,
      title: 'WeLearn 助手',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      // 拦下关闭按钮，改成「退出 / 最小化到托盘」的询问
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(WeLearnApp(state: state, navigatorKey: navigatorKey));

  if (Platform.isWindows) {
    await DesktopShell.init(state: state, navigatorKey: navigatorKey);
  }

  // 每天最多自动检查一次 GitHub Releases；失败不打扰离线使用，设置页仍可手动重试。
  // 每 6 小时触发一次判断，长时间挂机跨天时也能发现新版本。
  unawaited(state.autoCheckForUpdate());
  Timer.periodic(
    const Duration(hours: 6),
    (_) => state.autoCheckForUpdate(),
  );
}

class WeLearnApp extends StatelessWidget {
  const WeLearnApp({
    super.key,
    required this.state,
    required this.navigatorKey,
  });

  final AppState state;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'WeLearn 助手',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Workbench(),
      ),
    );
  }
}
