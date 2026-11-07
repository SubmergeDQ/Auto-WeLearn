import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'desktop_shell.dart';
import 'theme.dart';
import 'ui/app_scope.dart';
import 'ui/workbench.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final state = AppState();
  final navigatorKey = GlobalKey<NavigatorState>();

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
