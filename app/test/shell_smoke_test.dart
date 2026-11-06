import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:welearn_app/app_state.dart';
import 'package:welearn_app/theme.dart';
import 'package:welearn_app/ui/shell.dart';

/// 冒烟测试：在真实视口下构建整个工作区。
/// 布局溢出（RenderFlex overflow）会以异常形式抛出并让测试失败，
/// 这是在无法截图的沙箱里验证版式是否成立的最直接手段。
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState();
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
  }

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
}
