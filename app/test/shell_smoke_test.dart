import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:welearn_app/app_state.dart';
import 'package:welearn_app/core/changelog.dart';
import 'package:welearn_app/core/models.dart';
import 'package:welearn_app/core/updater.dart';
import 'package:welearn_app/theme.dart';
import 'package:welearn_app/ui/app_scope.dart';
import 'package:welearn_app/ui/components.dart';
import 'package:welearn_app/ui/dialogs.dart';
import 'package:welearn_app/ui/widgets.dart';
import 'package:welearn_app/ui/workbench.dart';

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
    // 冒烟测试的状态是手工构造的，跳过冷启动占位，直接测真实页面
    state.restoring = false;
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
    await tester.pump(const Duration(milliseconds: 100));
    return state;
  }

  AppState seeded({bool selected = true}) {
    final state = AppState()
      ..loggedIn = true
      ..courses = const [Course(cid: '1001', name: '大学英语综合教程 1', percent: 42)]
      ..currentCid = '1001'
      ..meta = const CourseMeta(cid: '1001', uid: '10000001', classid: '100001')
      ..units = const [
        CourseUnit(index: 0, unitName: 'Unit 01', name: '', visible: true),
        CourseUnit(index: 2, unitName: 'Unit 03', name: '', visible: true),
      ]
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
        Lesson(
          unitIndex: 0,
          scoid: 'm-1-1-1',
          location: 'Unit 1 > Text A: Reading Comprehension',
          visible: true,
          complete: true,
          learnTime: '00:06:12',
          crateLabel: '100',
        ),
      ];
    if (selected) {
      state.selectedScoids.addAll(['m-1-3-1', 'm-1-3-2']);
    }
    return state;
  }

  testWidgets('桌面 1440x900：三段导航与面板空态，无溢出', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(1440, 900));

      expect(find.byKey(const Key('nav-dashboard')), findsOneWidget);
      expect(find.byKey(const Key('nav-tasks')), findsOneWidget);
      expect(find.byKey(const Key('nav-settings')), findsOneWidget);
      expect(find.text('还没有登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('紧凑 1100x800 无溢出', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(1100, 800), seed: seeded());
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('移动 390x844：底部导航与面板，无溢出', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(390, 844), seed: seeded());

      expect(find.byKey(const Key('bottom-nav-dashboard')), findsOneWidget);
      expect(find.byKey(const Key('bottom-nav-tasks')), findsOneWidget);
      expect(find.byKey(const Key('bottom-nav-settings')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('桌面点导航切到任务页，参数在页面内而不是弹窗', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(1440, 900), seed: seeded());

      await tester.tap(find.byKey(const Key('nav-tasks')));
      await tester.pumpAndSettle();

      expect(find.text('运行参数'), findsOneWidget);
      expect(find.text('每节等待'), findsOneWidget);
      expect(find.text('目标正确率'), findsOneWidget);
      expect(find.text('跳过口语小节'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('移动端底部导航切到设置页', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(390, 844), seed: seeded());

      await tester.tap(find.byKey(const Key('bottom-nav-settings')));
      await tester.pumpAndSettle();

      expect(find.text('关闭窗口时'), findsOneWidget);
      expect(find.text('更换账号'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('任务页：点行切换勾选，摘要随之变化', (tester) async {
    await desktop(() async {
      final state = await pumpAt(tester, const Size(1440, 900), seed: seeded());
      await tester.tap(find.byKey(const Key('nav-tasks')));
      await tester.pumpAndSettle();

      expect(state.selectedScoids.length, 2);
      expect(find.text('已选 2 节'), findsWidgets);

      await tester.tap(find.text('Warm-up Activities: Matching'));
      await tester.pumpAndSettle();

      expect(state.selectedScoids.length, 1);
      expect(state.selectedScoids.contains('m-1-3-1'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('任务页：单元组头三态，一次勾选整单元', (tester) async {
    await desktop(() async {
      final state = await pumpAt(
        tester,
        const Size(1440, 900),
        seed: seeded(selected: false),
      );
      await tester.tap(find.byKey(const Key('nav-tasks')));
      await tester.pumpAndSettle();

      expect(state.unitSelection(2), isFalse);

      // 点 Unit 3 组头里的复选框：整单元一次勾选。
      // 单元条 chip 现在也叫 "Unit 3"，所以按语义标签精确定位组头那个。
      final groupCheckbox = find.byWidgetPredicate(
        (w) => w is AppCheckbox && w.label == '全选 Unit 3',
      );
      expect(groupCheckbox, findsOneWidget);
      await tester.tap(groupCheckbox);
      await tester.pumpAndSettle();

      expect(state.unitSelection(2), isTrue);
      expect(state.selectedScoids.length, 2);

      // 取消其中一行后，组头应变成"部分选中"
      await tester.tap(find.text('Warm-up Activities: Matching'));
      await tester.pumpAndSettle();
      expect(state.unitSelection(2), isNull);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('任务页全部标签下可折叠单元', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(1440, 900), seed: seeded());
      await tester.tap(find.byKey(const Key('nav-tasks')));
      await tester.pumpAndSettle();

      expect(find.text('Warm-up Activities: Matching'), findsOneWidget);

      await tester.tap(find.byTooltip('收起 Unit 3'));
      await tester.pumpAndSettle();
      expect(find.text('Warm-up Activities: Matching'), findsNothing);
      // 折叠后组头仍在，统计数字不受影响
      expect(
        find.byWidgetPredicate(
          (w) => w is AppCheckbox && w.label == '全选 Unit 3',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('展开 Unit 3'));
      await tester.pumpAndSettle();
      expect(find.text('Warm-up Activities: Matching'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('设置页：关闭行为可切换并写回状态', (tester) async {
    await desktop(() async {
      final state = await pumpAt(tester, const Size(1440, 900), seed: seeded());
      await tester.tap(find.byKey(const Key('nav-settings')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('最小化到托盘'));
      await tester.pumpAndSettle();

      expect(state.closeAction, 'tray');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('桌面点应用图标收起侧边栏，再点展开', (tester) async {
    await desktop(() async {
      final state = await pumpAt(tester, const Size(1440, 900), seed: seeded());

      expect(find.text('WeLearn 助手 $appVersion'), findsOneWidget);
      await tester.tap(find.byTooltip('点击收起侧边栏'));
      await tester.pumpAndSettle();

      expect(state.railCollapsed, isTrue);
      expect(find.text('WeLearn 助手 $appVersion'), findsNothing);

      await tester.tap(find.byTooltip('点击展开侧边栏'));
      await tester.pumpAndSettle();

      expect(state.railCollapsed, isFalse);
      expect(find.text('WeLearn 助手 $appVersion'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('侧边栏宽度被限制在 176–320', () {
    final state = AppState();
    state.setRailWidth(100);
    expect(state.railWidth, AppState.minRailWidth);
    state.setRailWidth(400);
    expect(state.railWidth, AppState.maxRailWidth);
  });

  testWidgets('设置页展示检查更新入口与仓库链接', (tester) async {
    await desktop(() async {
      final state = await pumpAt(tester, const Size(1440, 900), seed: seeded());
      state.latestRelease = const ReleaseInfo(
        version: '9.9.9',
        tagName: 'v9.9.9',
        notes: '',
        htmlUrl: 'https://github.com/SubmergeDQ/Auto-WeLearn/releases',
        assets: [],
      );
      state.notifyListeners();
      await tester.tap(find.byKey(const Key('nav-settings')));
      await tester.pumpAndSettle();

      expect(find.text('检查更新'), findsWidgets);
      expect(find.text('发现新版本 9.9.9，可一键更新'), findsOneWidget);
      expect(find.text('下载并自动安装'), findsOneWidget);
      expect(
        find.text('https://github.com/SubmergeDQ/Auto-WeLearn'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  test('预计耗时按已选节数计算', () {
    final state = seeded(selected: false);
    // 默认 300–480 等待、3–8 间隔：平均 390 + 5
    expect(state.estimateSeconds(2), 2 * (390 + 5));

    state.selectedScoids.addAll(['m-1-3-1']);
    expect(state.remainingEstimate, 395);
  });

  test('单节运行只把目标小节放进队列', () {
    final state = seeded();
    expect(state.runQueue().length, 2);
    expect(state.runQueue(only: state.lessons.first).length, 1);
    expect(state.runQueue(only: state.lessons.first).single.scoid, 'm-1-3-1');
  });

  testWidgets('扫描中：标题行与列表都有进度文字，扫描按钮禁用', (tester) async {
    await desktop(() async {
      final state = await pumpAt(tester, const Size(1440, 900), seed: seeded());
      state
        ..scanning = true
        ..scanStage = '第 3 单元：18 小节';
      state.notifyListeners();
      // 进度条是无限动画，这里只能用单帧 pump，不能用 pumpAndSettle
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('正在扫描课程结构…'), findsWidgets);
      expect(find.text('第 3 单元：18 小节'), findsWidgets);
      expect(find.text('请勿重复扫描'), findsWidgets);
      final button = find.widgetWithText(OutlinedButton, '扫描中…');
      expect(button, findsWidgets);
      expect(tester.widget<OutlinedButton>(button.first).onPressed, isNull);

      await tester.tap(find.byKey(const Key('nav-tasks')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('正在扫描课程结构…'), findsWidgets);
      // 任务页的扫描横幅在标题下方，列表区只留空态说明，
      // 不会再出现一条进度卡吊在整片空白中间
      expect(find.text('正在扫描课程结构'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('手机扫描横幅在 390 宽下不溢出', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final state = await pumpAt(tester, const Size(390, 844), seed: seeded());
      state
        ..scanning = true
        ..scanStage = '第 3 单元：18 小节';
      state.notifyListeners();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('正在扫描课程结构…'), findsWidgets);
      expect(find.text('已用时 00:00'), findsWidgets);
      // 窄屏只留计时，避免右侧两行小字把阶段文字挤掉
      expect(find.text('请勿重复扫描'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('安卓设置页显示后台运行，不显示托盘选项', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpAt(tester, const Size(390, 844), seed: seeded());
      await tester.tap(find.byKey(const Key('bottom-nav-settings')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('保持后台运行'), findsOneWidget);
      expect(find.text('任务栏常驻'), findsOneWidget);
      expect(find.text('权限申请'), findsOneWidget);
      expect(find.text('关闭窗口时'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('设置页：开启保存登录状态时询问是否记录账号密码', (tester) async {
    await desktop(() async {
      final state = await pumpAt(tester, const Size(1440, 900), seed: seeded());
      await tester.tap(find.byKey(const Key('nav-settings')));
      await tester.pumpAndSettle();

      // 默认关闭，点击后先弹选择框，不立即开启
      expect(state.rememberLogin, isFalse);
      await tester.tap(find.byTooltip('保存登录状态'));
      await tester.pumpAndSettle();

      expect(find.text('仅保存登录状态'), findsOneWidget);

      await tester.tap(find.text('保存账号密码'));
      await tester.pumpAndSettle();

      expect(state.rememberLogin, isTrue);
      expect(state.savePassword, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('发现新版本时自动弹出更新询问', (tester) async {
    await desktop(() async {
      final state = await pumpAt(tester, const Size(1440, 900), seed: seeded());
      state.latestRelease = const ReleaseInfo(
        version: '9.9.9',
        tagName: 'v9.9.9',
        notes: '## WeLearn 助手 9.9.9\n\n### 本次更新\n\n- 修复若干问题\n- 新增功能',
        htmlUrl: 'https://github.com/SubmergeDQ/Auto-WeLearn/releases',
        assets: [],
      );
      state.updatePromptPending = true;
      state.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 9.9.9'), findsOneWidget);
      expect(find.text('拒绝更新'), findsOneWidget);
      expect(find.text('更新'), findsOneWidget);
      // Markdown 已渲染成标题与列表，不再露出 ## / - 等原始标记
      expect(find.text('WeLearn 助手 9.9.9'), findsOneWidget);
      expect(find.text('本次更新'), findsOneWidget);
      expect(find.text('修复若干问题'), findsOneWidget);
      expect(find.textContaining('##'), findsNothing);
      expect(find.textContaining('- 修复'), findsNothing);

      await tester.tap(find.text('拒绝更新'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 9.9.9'), findsNothing);
      expect(state.updatePromptPending, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('登录成功后询问是否保存登录状态', (tester) async {
    bool? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  choice = await askSaveLoginAfterLogin(
                    context,
                    hasCredentials: true,
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('登录成功'), findsOneWidget);
    expect(find.text('保存账号密码'), findsOneWidget);
    expect(find.text('仅保存登录状态'), findsOneWidget);

    await tester.tap(find.text('保存账号密码'));
    await tester.pumpAndSettle();
    expect(choice, isTrue);
  });

  testWidgets('粘贴 Cookie 登录只提供保存登录状态', (tester) async {
    bool? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  choice = await askSaveLoginAfterLogin(
                    context,
                    hasCredentials: false,
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('保存账号密码'), findsNothing);
    expect(find.text('保存登录状态'), findsOneWidget);

    await tester.tap(find.text('保存登录状态'));
    await tester.pumpAndSettle();
    expect(choice, isFalse);
  });

  testWidgets('滑条两端可以拖到完全重合', (tester) async {
    int started = 300;
    int ended = 600;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setLocal) => Center(
              child: SizedBox(
                width: 300,
                child: RangeField(
                  label: '每节等待',
                  min: 30,
                  max: 900,
                  start: started,
                  end: ended,
                  suffix: ' 秒',
                  step: 10,
                  onChanged: (a, b) => setLocal(() {
                    started = a;
                    ended = b;
                  }),
                  onChangeEnd: (a, b) => setLocal(() {
                    started = a;
                    ended = b;
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(RangeSlider));
    const inset = 14.0;
    final usable = rect.width - inset * 2;
    // 右端点（600 秒）对应位置，往左拖动让两个端点重合到 300 秒
    final endX = rect.left + inset + (600 - 30) / (900 - 30) * usable;
    final gesture = await tester.startGesture(Offset(endX, rect.center.dy));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.moveBy(Offset(-(usable * 0.5), 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(started, 300);
    expect(ended, 300, reason: '两个端点应该能完全重合');
    expect(find.text('300 – 300 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('滑条两端重合后还能再分开', (tester) async {
    int started = 900;
    int ended = 900;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setLocal) => Center(
              child: SizedBox(
                width: 300,
                child: RangeField(
                  label: '每节等待',
                  min: 0,
                  max: 1200,
                  start: started,
                  end: ended,
                  suffix: ' 秒',
                  step: 10,
                  onChanged: (a, b) => setLocal(() {
                    started = a;
                    ended = b;
                  }),
                  onChangeEnd: (a, b) => setLocal(() {
                    started = a;
                    ended = b;
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(RangeSlider));
    const inset = 14.0;
    final usable = rect.width - inset * 2;
    // 两个端点重合在 900 秒：向左拖应该把起点拉开，而不是整体平移
    final x = rect.left + inset + 900 / 1200 * usable;
    final gesture = await tester.startGesture(Offset(x, rect.center.dy));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(started, lessThan(900), reason: '起点应该被拉开');
    expect(ended, 900, reason: '止点保持不动');
    expect(find.text('$started – 900 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('滑条数值可精确输入，两端允许相等', (tester) async {
    int started = 90;
    int ended = 100;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setLocal) => Center(
              child: SizedBox(
                width: 300,
                child: RangeField(
                  label: '目标正确率',
                  min: 0,
                  max: 100,
                  start: started,
                  end: ended,
                  suffix: '%',
                  onChanged: (a, b) => setLocal(() {
                    started = a;
                    ended = b;
                  }),
                  onChangeEnd: (a, b) => setLocal(() {
                    started = a;
                    ended = b;
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 两个 thumb 重叠后无法再用滑块分别选中，点数值走精确输入
    await tester.tap(find.text('90 – 100%'));
    await tester.pumpAndSettle();
    expect(find.text('目标正确率精确设置'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(started, 100);
    expect(ended, 100);
    expect(find.text('100 – 100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动端任务页：单元组头吸顶', (tester) async {
    await desktop(() async {
      // 只造一个单元、多条小节，保证组头一开始就在列表顶端，
      // 向下滚动后仍钉在原位（非吸顶实现会被滚出可视区）。
      final state = AppState()
        ..loggedIn = true
        ..courses = const [
          Course(cid: '1001', name: '大学英语综合教程 1', percent: 42),
        ]
        ..currentCid = '1001'
        ..meta = const CourseMeta(cid: '1001', uid: '10000001', classid: '100001')
        ..units = const [
          CourseUnit(index: 2, unitName: 'Unit 03', name: '', visible: true),
        ]
        ..lessons = [
          for (var i = 0; i < 12; i++)
            Lesson(
              unitIndex: 2,
              scoid: 'm-3-$i',
              location: 'Unit 3 > Topic $i',
              visible: true,
              complete: false,
              learnTime: '',
              crateLabel: '-',
            ),
        ];

      await pumpAt(tester, const Size(390, 844), seed: state);
      await tester.tap(find.byKey(const Key('bottom-nav-tasks')));
      await tester.pumpAndSettle();

      final header = find.byWidgetPredicate(
        (w) => w is AppCheckbox && w.label == '全选 Unit 3',
      );
      final before = tester.getTopLeft(header).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await tester.pumpAndSettle();

      // 吸顶：组头停在列表顶端，不随内容一起滚走
      expect(tester.getTopLeft(header).dy, closeTo(before, 1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('设置页可查看版本更新历史', (tester) async {
    await desktop(() async {
      await pumpAt(tester, const Size(1440, 900), seed: seeded());
      await tester.tap(find.byKey(const Key('nav-settings')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('版本更新历史'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();

      // 版本条目来自内置清单，无需联网
      expect(
        find.text('当前版本 $appVersion · 从新到旧共 ${releaseHistory.length} 个版本'),
        findsOneWidget,
      );
      expect(find.text('1.1.9'), findsWidgets);
      expect(find.text('当前版本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
