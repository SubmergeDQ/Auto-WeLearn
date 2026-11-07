import 'package:flutter/foundation.dart';
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
  /// 按 Windows 平台跑：桌面端 VisualDensity 与移动端不同（compact 会把按钮压矮 8px），
  /// 不切换平台就测不出"控件等高"这类问题。注意必须在本测试体内复位。
  Future<void> desktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<AppState> pumpAt(
    WidgetTester tester,
    Size size, {
    AppState? seed,
  }) async {
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
    await desktop(() async {
      await pumpAt(tester, const Size(1440, 900));
      expect(find.text('WeLearn 助手'), findsOneWidget);
      // 未登录时顶栏是「登录」，登录后才是「开始运行 · N 节」
      expect(find.text('登录'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('紧凑 1100x800 不溢出', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(1100, 800));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('移动 390x844 不溢出', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(390, 844));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('已登录：顶栏三个控件同高且中心线一致', (tester) async {
    await desktop(() async {
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
  });

  testWidgets('工具栏与侧栏控件同高（桌面密度下不被压矮）', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(1440, 900), seed: loggedIn());

      final search = tester.getRect(find.byKey(const Key('queue-search')));
      final rescan = tester.getRect(find.byKey(const Key('sidebar-rescan')));
      final card = tester.getRect(find.byKey(const Key('course-card')));

      expect(search.height, Tokens.controlHeight);
      expect(rescan.height, Tokens.controlHeight);

      // 左右边距必须一致，否则按钮会比卡片宽出一圈
      expect(rescan.left, card.left);
      expect(rescan.right, card.right);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('已登录：可从账号菜单退出登录并清空会话', (tester) async {
    await desktop(() async {
      final state = await pumpAt(
        tester,
        const Size(1440, 900),
        seed: loggedIn(),
      );

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
  });

  testWidgets('移动端账号菜单里也有退出登录', (tester) async {
    await desktop(() async {
      final state = await pumpAt(
        tester,
        const Size(390, 844),
        seed: loggedIn(),
      );

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
  });

  // ── 移动端信息架构（MOBILE_UX 批次 A） ──────────────────
  AppState mobileState({bool running = false}) {
    final state = AppState()
      ..loggedIn = true
      ..courses = const [Course(cid: '566', name: '新起点大学英语综合教程1', percent: 42)]
      ..currentCid = '566'
      ..units = const [CourseUnit(index: 2, unitName: 'Unit 3', name: '', visible: true)]
      ..lessons = const [
        Lesson(
          unitIndex: 2,
          scoid: 'm-1-3-1',
          location: 'Unit 3 > Warm-up Activities: Matching',
          visible: true,
          complete: false,
          learnTime: '',
          crateLabel: '-',
        ),
        Lesson(
          unitIndex: 2,
          scoid: 'm-1-3-2',
          location: 'Unit 3 > Warm-up Activities: Conversation',
          visible: true,
          complete: false,
          learnTime: '',
          crateLabel: '-',
        ),
      ];
    if (running) {
      state
        ..running = true
        ..currentScoid = 'm-1-3-1'
        ..currentElapsed = 72
        ..currentWait = 360
        ..currentHeartbeats = 2
        ..runTotal = 2
        ..runDone = 0;
    }
    return state;
  }

  testWidgets('移动端运行中：运行卡有倒计时与队列位置', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(390, 844), seed: mobileState(running: true));

      expect(find.byKey(const Key('mobile-run-card')), findsOneWidget);
      expect(find.text('剩余'), findsOneWidget);
      expect(find.textContaining('第 1/2 节'), findsOneWidget);
      expect(find.text('心跳 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('移动端空闲：折叠为下一节预览', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(390, 844), seed: mobileState());
      expect(find.byKey(const Key('mobile-idle-card')), findsOneWidget);
      expect(find.textContaining('下一节'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('移动端点行弹出小节详情', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(390, 844), seed: mobileState());

      await tester.tap(find.text('Unit 3 > Warm-up Activities: Matching').first);
      await tester.pumpAndSettle();

      expect(find.text('m-1-3-1'), findsOneWidget);
      expect(find.text('尚未解析，运行到本节时会解析题目'), findsOneWidget);
      expect(find.text('只跑这一节（暂未支持）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('移动端 0 待处理：底栏说明原因且空态可重新扫描', (tester) async {
    await desktop(() async {
      final state = AppState()
        ..loggedIn = true
        ..courses = const [Course(cid: '566', name: '新起点大学英语综合教程1', percent: 100)]
        ..currentCid = '566';

      await pumpAt(tester, const Size(390, 844), seed: state);

      expect(find.text('队列为空，先重新扫描'), findsWidgets);
      expect(find.text('重新扫描'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('移动端单元条可分单元筛选', (tester) async {
    await desktop(() async {
      final state = mobileState()
        ..units = const [
          CourseUnit(index: 0, unitName: 'Unit 1', name: '', visible: true),
          CourseUnit(index: 2, unitName: 'Unit 3', name: '', visible: true),
        ];

      await pumpAt(tester, const Size(390, 844), seed: state);
      expect(find.text('U3 · 2'), findsOneWidget);

      await tester.tap(find.text('U3 · 2'));
      await tester.pumpAndSettle();
      expect(state.selectedUnit, 2);
      expect(tester.takeException(), isNull);
    });
  });
}
