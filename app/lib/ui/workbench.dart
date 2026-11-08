import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'app_scope.dart';
import 'dialogs.dart';
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
  bool _updatePromptScheduled = false;

  void _go(AppSection section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  void _openUnit(int unitIndex) {
    setState(() => _section = AppSection.tasks);
  }

  /// 检查更新发现新版本后弹一次询问。
  ///
  /// 用 post-frame 回调避开 build 期间弹路由；标记清除后同一次检查不会再触发。
  void _scheduleUpdatePrompt(AppState state) {
    if (!state.updatePromptPending || _updatePromptScheduled) return;
    _updatePromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePromptScheduled = false;
      if (!mounted || !state.updatePromptPending) return;
      state.markUpdatePromptShown();
      showUpdateDialog(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    // 冷启动时磁盘读取与会话校验都是异步的，先显示占位，
    // 避免一帧「未登录」空态闪过去再跳到已登录。
    if (state.restoring) {
      return const _BootPlaceholder();
    }

    _scheduleUpdatePrompt(state);

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
          AppNavRail(
            section: _section,
            onSelect: _go,
            width: state.railCollapsed ? 64 : state.railWidth,
            collapsed: state.railCollapsed,
            onToggleCollapsed: state.toggleRailCollapsed,
            onResize: (delta) => state.setRailWidth(state.railWidth + delta),
            onResizeEnd: state.commitRailWidth,
          ),
          Expanded(child: pages),
        ],
      ),
    );
  }
}

/// 启动占位：与应用图标同款视觉，只说明「正在恢复」，不显示任何未登录文案。
class _BootPlaceholder extends StatelessWidget {
  const _BootPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Tokens.border),
              ),
              child: Image.asset(
                'assets/logo.png',
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Tokens.accent,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '正在恢复上次的登录状态…',
              style: TextStyle(fontSize: 12, color: Tokens.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
