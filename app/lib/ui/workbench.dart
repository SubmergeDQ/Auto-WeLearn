import 'package:flutter/material.dart';

import '../theme.dart';
import 'nav.dart';
import 'pages/dashboard_page.dart';
import 'pages/settings_page.dart';
import 'pages/tasks_page.dart';

/// 三段式外壳：桌面左侧导航，移动端底部 Tab。
///
/// 页面用 IndexedStack 保活，切回来时滚动位置、搜索词都还在——
/// 这是"跑着任务去设置里改点东西再回来"最常见的路径。
class Workbench extends StatefulWidget {
  const Workbench({super.key});

  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  AppSection _section = AppSection.dashboard;

  void _go(AppSection section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  void _openUnit(int unitIndex) {
    setState(() => _section = AppSection.tasks);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    final pages = IndexedStack(
      index: _section.index,
      children: [
        DashboardPage(onNavigate: _go, onOpenUnit: _openUnit),
        TasksPage(onNavigate: _go),
        const SettingsPage(),
      ],
    );

    if (!wide) {
      return Scaffold(
        backgroundColor: Tokens.canvas,
        body: Column(
          children: [
            Expanded(child: SafeArea(bottom: false, child: pages)),
            AppBottomNav(section: _section, onSelect: _go),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Tokens.canvas,
      body: Row(
        children: [
          AppNavRail(section: _section, onSelect: _go),
          Expanded(child: pages),
        ],
      ),
    );
  }
}
