import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:welearn_app/app_state.dart';
import 'package:welearn_app/core/models.dart';
import 'package:welearn_app/theme.dart';
import 'package:welearn_app/ui/shell.dart';

/// 冒烟测试：在真实视口下构建整个工作区。
/// 布局溢出（RenderFlex overflow）会以异常形式抛出并让测试失败，
/// 这是在无法截图的沙箱里验证版式是否成立的最直接手段。
void main() {
  Future<AppState> pumpAt(WidgetTester tester, Size size, {AppState? seed}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = seed ?? AppState();
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const WorkbenchShell(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return state;
  }

  AppState loggedIn() => AppState()
    ..loggedIn = true
    ..courses = const [Course(cid: '566', name: '新起点大学英语综合教程1', percent: 24)]
    ..currentCid = '566';

  testWidgets('桌面 1440x900 不溢出', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(find.text('WeLearn 助手'), findsOneWidget);
    // 未登录时顶栏是「登录」，登录后才是「开始运行 · N 节」
    expect(find.text('登录'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧凑 1100x800 不溢出', (tester) async {
    await pumpAt(tester, const Size(1100, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动 390x844 不溢出', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
  });

  testWidgets('已登录：顶栏三个控件同高且中心线一致', (tester) async {
    await pumpAt(tester, const Size(1440, 900), seed: loggedIn());

    final chip = tester.getRect(find.byKey(const Key('account-chip')));
    final gear = tester.getRect(find.byKey(const Key('toolbar-settings')));
    final run = tester.getRect(find.byKey(const Key('toolbar-run')));

    expect(chip.height, Tokens.controlHeight);
    expect(gear.height, Tokens.controlHeight);
    expect(run.height, Tokens.controlHeight);

    expect(chip.center.dy, closeTo(gear.center.dy, 0.5));
    expect(run.center.dy, closeTo(gear.center.dy, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('已登录：可从账号菜单退出登录并清空会话', (tester) async {
    final state = await pumpAt(tester, const Size(1440, 900), seed: loggedIn());

    await tester.tap(find.byKey(const Key('account-chip')));
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsOneWidget);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    // 二次确认，避免误点就把 Cookie 丢掉
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();

    expect(state.loggedIn, isFalse);
    expect(state.courses, isEmpty);
    expect(state.currentCid, isNull);
    expect(find.text('登录'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动端账号菜单里也有退出登录', (tester) async {
    final state = await pumpAt(tester, const Size(390, 844), seed: loggedIn());

    await tester.tap(find.byKey(const Key('mobile-account')));
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsOneWidget);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();

    expect(state.loggedIn, isFalse);
    expect(tester.takeException(), isNull);
  });
}
