import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/updater.dart';
import '../theme.dart';
import 'app_scope.dart';
import 'widgets.dart' show AccountAvatar, Caret;

enum AppSection {
  dashboard('面板'),
  tasks('任务'),
  settings('设置');

  const AppSection(this.label);
  final String label;

  IconData get icon => switch (this) {
    AppSection.dashboard => Icons.grid_view_rounded,
    AppSection.tasks => Icons.list_alt_rounded,
    AppSection.settings => Icons.settings_outlined,
  };
}

/// 桌面左侧导航：应用图标、三段入口、底部账号卡。
///
/// 账号卡常驻而不是塞进设置页：当前是哪个账号、跑的是哪门课，
/// 是这个工具最常被确认的状态，不该每次点进设置才看得到。
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.section,
    required this.onSelect,
    required this.width,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onResize,
    required this.onResizeEnd,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSelect;
  final double width;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  /// 拖拽右边缘时传水平位移（像素）
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pending = state.candidates.length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: width,
          decoration: const BoxDecoration(
            color: Tokens.surface,
            border: Border(right: BorderSide(color: Tokens.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Brand(collapsed: collapsed, onTap: onToggleCollapsed),
              Padding(
                // 三个模块的间距比旧版更大：8px 间隔 + 40 高条目，扫读更清楚
                padding: EdgeInsets.fromLTRB(
                  collapsed ? 8 : 12,
                  14,
                  collapsed ? 8 : 12,
                  10,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < AppSection.values.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _NavItem(
                        key: Key('nav-${AppSection.values[i].name}'),
                        section: AppSection.values[i],
                        selected: AppSection.values[i] == section,
                        collapsed: collapsed,
                        badge:
                            AppSection.values[i] == AppSection.tasks &&
                                pending > 0
                            ? pending
                            : null,
                        showUpdateDot:
                            AppSection.values[i] == AppSection.settings &&
                            state.hasUpdate,
                        onTap: () => onSelect(AppSection.values[i]),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              if (collapsed)
                _CollapsedAccountCard(
                  state: state,
                  onTap: () => onSelect(AppSection.settings),
                )
              else
                _AccountCard(
                  state: state,
                  onTap: () => onSelect(AppSection.settings),
                ),
              if (!collapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Text(
                    'WeLearn 助手 $appVersion',
                    style: monoStyle(size: 10, color: Tokens.textTertiary),
                  ),
                ),
            ],
          ),
        ),
        if (!collapsed)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _ResizeHandle(onResize: onResize, onResizeEnd: onResizeEnd),
          ),
      ],
    );
  }
}

/// 应用图标：点击在展开 / 收起之间切换。
class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logo = _AppLogo(size: collapsed ? 34 : 30);

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Tokens.border)),
      ),
      child: Tooltip(
        message: collapsed ? '点击展开侧边栏' : '点击收起侧边栏',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Tokens.radiusControl),
            child: collapsed
                ? Center(child: logo)
                : Row(
                    children: [
                      logo,
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WeLearn',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: 1),
                            Text(
                              '学习助手',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Tokens.textTertiary,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.keyboard_double_arrow_left_rounded,
                        size: 14,
                        color: Tokens.textTertiary.withValues(alpha: 0.65),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 侧边栏里的应用图标：白色圆角底板 + 应用图标，和桌面 exe 图标同一套视觉。
class _AppLogo extends StatelessWidget {
  const _AppLogo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: Tokens.border, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        'assets/logo.png',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(
          Icons.school_outlined,
          size: size * 0.55,
          color: Tokens.accent,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.badge,
    this.showUpdateDot = false,
  });

  final AppSection section;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final int? badge;
  final bool showUpdateDot;

  @override
  Widget build(BuildContext context) {
    final content = collapsed
        ? Stack(
            children: [
              Center(
                child: Icon(
                  section.icon,
                  size: 18,
                  color: selected ? Tokens.accent : Tokens.textSecondary,
                ),
              ),
              if (showUpdateDot)
                const Positioned(right: 8, top: 8, child: _UpdateDot()),
            ],
          )
        : Row(
            children: [
              Icon(
                section.icon,
                size: 17,
                color: selected ? Tokens.accent : Tokens.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.label,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: selected ? Tokens.accent : Tokens.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (showUpdateDot) ...[
                const _UpdateDot(),
                const SizedBox(width: 6),
              ],
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Tokens.surface : Tokens.mutedSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$badge',
                    style: monoStyle(
                      size: 10,
                      color: selected ? Tokens.accent : Tokens.textTertiary,
                    ),
                  ),
                ),
            ],
          );

    final item = Material(
      color: selected ? Tokens.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(Tokens.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: SizedBox(
          height: Tokens.navItemHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
            child: content,
          ),
        ),
      ),
    );

    return collapsed ? Tooltip(message: section.label, child: item) : item;
  }
}

class _UpdateDot extends StatelessWidget {
  const _UpdateDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: Tokens.accent,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 拖拽右边缘调整侧边栏宽度。
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onResize, required this.onResizeEnd});

  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => widget.onResize(details.delta.dx),
        onHorizontalDragEnd: (_) => widget.onResizeEnd(),
        child: SizedBox(
          width: 7,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _hovering ? 3 : 1,
              color: _hovering
                  ? Tokens.accent.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsedAccountCard extends StatelessWidget {
  const _CollapsedAccountCard({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final course = state.currentCourse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tooltip(
        message: '账号与设置',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
          child: Center(
            child: AccountAvatar(
              bytes: state.avatarBytes,
              initials: (course?.name ?? 'W').characters.first,
              size: 32,
              loggedIn: state.loggedIn,
              loading: state.avatarLoading,
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final course = state.currentCourse;
    final loggedIn = state.loggedIn;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.radiusControl),
              border: Border.all(color: Tokens.border),
            ),
            child: Row(
              children: [
                AccountAvatar(
                  bytes: state.avatarBytes,
                  initials: (course?.name ?? 'W').characters.first,
                  size: 28,
                  loggedIn: loggedIn,
                  loading: state.avatarLoading,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loggedIn ? (course?.name ?? '已登录') : '未登录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        loggedIn
                            ? (state.activeAccount?.uid != null
                                  ? 'uid ${state.activeAccount!.uid}'
                                  : '账号已连接')
                            : '点这里登录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Tokens.textTertiary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Caret(color: Tokens.textTertiary, width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 移动端底部导航。
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.section,
    required this.onSelect,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(top: BorderSide(color: Tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: Tokens.bottomNavHeight,
          child: Row(
            children: [
              for (final s in AppSection.values)
                Expanded(
                  child: InkWell(
                    key: Key('bottom-nav-${s.name}'),
                    onTap: () => onSelect(s),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              s.icon,
                              size: 20,
                              color: s == section
                                  ? Tokens.accent
                                  : Tokens.textTertiary,
                            ),
                            if (s == AppSection.settings && state.hasUpdate)
                              const Positioned(
                                right: -7,
                                top: -3,
                                child: _UpdateDot(),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.2,
                            color: s == section
                                ? Tokens.accent
                                : Tokens.textTertiary,
                            fontWeight: s == section
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
