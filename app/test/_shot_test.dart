import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:welearn_app/app_state.dart';
import 'package:welearn_app/core/models.dart';
import 'package:welearn_app/theme.dart';
import 'package:welearn_app/ui/app_scope.dart';
import 'package:welearn_app/ui/workbench.dart';

Future<void> _load(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

AppState _seeded({bool running = true}) {
  const units = [
    CourseUnit(index: 0, unitName: 'Unit 01', name: '', visible: true),
    CourseUnit(index: 1, unitName: 'Unit 02', name: '', visible: true),
    CourseUnit(index: 2, unitName: 'Unit 03', name: '', visible: true),
  ];
  Lesson lesson(
    int unit,
    String scoid,
    String loc, {
    bool done = false,
    String time = '',
  }) => Lesson(
    unitIndex: unit,
    scoid: scoid,
    location: loc,
    visible: true,
    complete: done,
    learnTime: time,
    crateLabel: '-',
  );

  final lessons = [
    lesson(
      0,
      'm-1-1-1',
      'Unit 1 > Text A: Reading Comprehension',
      done: true,
      time: '00:06:12',
    ),
    lesson(
      0,
      'm-1-1-2',
      'Unit 1 > Text A: Language Focus',
      done: true,
      time: '00:05:40',
    ),
    lesson(
      0,
      'm-1-1-3',
      'Unit 1 > Listening & Speaking',
      done: true,
      time: '00:07:03',
    ),
    lesson(1, 'm-1-2-1', 'Unit 2 > Warm-up Activities: Matching'),
    lesson(1, 'm-1-2-2', 'Unit 2 > Warm-up Activities: Conversation'),
    lesson(1, 'm-1-2-3', 'Unit 2 > Text Exploration: Reading'),
    lesson(1, 'm-1-2-4', 'Unit 2 > Text Exploration: Vocabulary'),
    lesson(2, 'm-1-3-1', 'Unit 3 > Warm-up Activities: Matching'),
    lesson(2, 'm-1-3-2', 'Unit 3 > Warm-up Activities: Conversation'),
    lesson(2, 'm-1-3-3', 'Unit 3 > Text Exploration: Reading'),
  ];

  final state = AppState()
    ..loggedIn = true
    ..courses = const [Course(cid: '1001', name: '大学英语综合教程 1', percent: 51)]
    ..currentCid = '1001'
    ..meta = const CourseMeta(cid: '1001', uid: '10000001', classid: '100001')
    ..units = units
    ..lessons = lessons
    ..lastLoginAt = DateTime(2026, 11, 7, 12, 30);

  state.selectedScoids.addAll(
    lessons.where((l) => !l.complete).map((l) => l.scoid),
  );
  state.statuses['m-1-1-1'] = LessonStatus.done;
  state.statuses['m-1-1-2'] = LessonStatus.done;
  state.statuses['m-1-1-3'] = LessonStatus.done;

  if (running) {
    state
      ..running = true
      ..currentScoid = 'm-1-2-3'
      ..currentElapsed = 148
      ..currentWait = 372
      ..currentHeartbeats = 3
      ..runTotal = 7
      ..runDone = 2
      ..runStartedAt = DateTime(2026, 11, 7, 12, 31);
    state.statuses['m-1-2-1'] = LessonStatus.done;
    state.statuses['m-1-2-2'] = LessonStatus.skipped;
    state.recentResults.addAll(const [
      LessonResult(
        scoid: 'm-1-2-2',
        status: LessonStatus.skipped,
        crate: 96,
        waitSec: 361,
        heartbeats: 10,
        stat: LessonStat(questions: 0, oral: 1, answered: 0),
      ),
      LessonResult(
        scoid: 'm-1-2-1',
        status: LessonStatus.done,
        crate: 94,
        waitSec: 374,
        heartbeats: 11,
        stat: LessonStat(questions: 6, oral: 0, answered: 6),
      ),
    ]);
    state.addLog('info', '[3/7] Text Exploration: Reading  rate=93%');
    // 日志时间戳必须固定，否则基准图每次都在秒位抖动
    state.logs
      ..clear()
      ..addAll([
        LogEntry(
          'info',
          '[3/7] Text Exploration: Reading  rate=93%',
          time: DateTime(2026, 11, 7, 12, 33, 41),
        ),
        LogEntry(
          'beat',
          '心跳 +32s / 372s  total=452s  ok',
          time: DateTime(2026, 11, 7, 12, 34, 12),
        ),
        LogEntry(
          'info',
          '解析 8 题（跳过 1 道口语题）  等待 06:12',
          time: DateTime(2026, 11, 7, 12, 34, 13),
        ),
      ]);
  }

  return state;
}

Future<void> _pump(WidgetTester tester, Size size, AppState state) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Workbench(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

/// flutter test 默认平台是 android；不显式切到 windows，桌面截图里的
/// 「设置」会渲染成手机端的 Wake Lock / 常驻通知分组。
/// override 必须在测试体内部复位（addTearDown 晚于 framework 的 invariant 检查）。
void _shot(
  String name,
  Size size,
  String golden, {
  bool running = true,
  String? navKey,
}) {
  testWidgets(name, (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = size.width >= 900
        ? TargetPlatform.windows
        : TargetPlatform.android;
    try {
      await _pump(tester, size, _seeded(running: running));
      if (navKey != null) {
        await tester.tap(find.byKey(Key(navKey)));
        await tester.pumpAndSettle();
      }
      await expectLater(find.byType(Workbench), matchesGoldenFile(golden));
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

void main() {
  setUpAll(() async {
    await _load('Segoe UI', r'C:\Windows\Fonts\segoeui.ttf');
    await _load('Microsoft YaHei UI', r'C:\Windows\Fonts\msyh.ttc');
    await _load('Consolas', r'C:\Windows\Fonts\consola.ttf');
    await _load(
      'MaterialIcons',
      r'D:\dev\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    );
  });

  _shot('desktop dashboard', const Size(1440, 900), 'goldens/dash.png');
  _shot(
    'desktop dashboard 1280',
    const Size(1280, 840),
    'goldens/dash-1280.png',
  );
  _shot(
    'desktop dashboard 1280x800',
    const Size(1280, 800),
    'goldens/dash-1280x800.png',
  );
  _shot(
    'desktop tasks',
    const Size(1440, 900),
    'goldens/tasks.png',
    running: false,
    navKey: 'nav-tasks',
  );
  _shot(
    'desktop settings',
    const Size(1440, 900),
    'goldens/settings.png',
    running: false,
    navKey: 'nav-settings',
  );
  _shot('mobile dashboard', const Size(390, 844), 'goldens/mobile-dash.png');
  _shot(
    'mobile tasks',
    const Size(390, 844),
    'goldens/mobile-tasks.png',
    running: false,
    navKey: 'bottom-nav-tasks',
  );
  _shot(
    'mobile settings',
    const Size(390, 844),
    'goldens/mobile-settings.png',
    running: false,
    navKey: 'bottom-nav-settings',
  );

  testWidgets('desktop logged out', (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pump(tester, const Size(1440, 900), AppState());
      await expectLater(
        find.byType(Workbench),
        matchesGoldenFile('goldens/logged-out.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('desktop settings bottom', (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pump(tester, const Size(1440, 900), _seeded(running: false));
      await tester.tap(find.byKey(const Key('nav-settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('GitHub 仓库'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Workbench),
        matchesGoldenFile('goldens/settings-bottom.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('desktop settings auth expired', (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final state = AppState()
        ..accounts = [
          SavedAccount(
            id: 'test',
            cookie: 'dummy=1',
            savedAt: DateTime(2026, 11, 7),
          ),
        ]
        ..lastError = '登录态已失效，请重新登录';
      await _pump(tester, const Size(1440, 900), state);
      await tester.tap(find.byKey(const Key('nav-settings')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Workbench),
        matchesGoldenFile('goldens/settings-expired.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('desktop scanning', (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final state = _seeded(running: false)
        ..scanning = true
        ..scanStage = '第 3 单元：18 小节'
        // 真实扫描时 loadCourse 会先清空列表，界面进入「正在扫描」空态；
        // 不能保留旧列表做截图，否则会得到实际不存在的卡片布局。
        ..units = const []
        ..lessons = const [];
      state.selectedScoids.clear();
      await _pump(tester, const Size(1440, 900), state);
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byType(Workbench),
        matchesGoldenFile('goldens/scan.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('mobile scanning', (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final state = _seeded(running: false)
        ..scanning = true
        ..scanStage = '第 3 单元：18 小节'
        ..units = const []
        ..lessons = const [];
      state.selectedScoids.clear();
      await _pump(tester, const Size(390, 844), state);
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byType(Workbench),
        matchesGoldenFile('goldens/mobile-scan.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}
