import 'package:flutter/material.dart';

import '../app_state.dart';
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

/// 桌面左侧导航：品牌、三段入口、底部账号卡。
///
/// 账号卡常驻而不是塞进设置页：当前是哪个账号、跑的是哪门课，
/// 是这个工具最常被确认的状态，不该每次点进设置才看得到。
class AppNavRail extends StatelessWidget {
  const AppNavRail({super.key, required this.section, required this.onSelect});

  final AppSection section;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pending = state.candidates.length;

    return Container(
      width: Tokens.railWidth,
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(right: BorderSide(color: Tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Brand(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                for (final s in AppSection.values)
                  _NavItem(
                    key: Key('nav-${s.name}'),
                    section: s,
                    selected: s == section,
                    badge: s == AppSection.tasks && pending > 0
                        ? pending
                        : null,
                    onTap: () => onSelect(s),
                  ),
              ],
            ),
          ),
          const Spacer(),
          _AccountCard(
            state: state,
            onTap: () => onSelect(AppSection.settings),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Text(
              'WeLearn 助手 1.0.2',
              style: monoStyle(size: 10, color: Tokens.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Tokens.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Tokens.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.school_outlined,
              size: 17,
              color: Tokens.accent,
            ),
          ),
          const SizedBox(width: 10),
          const Column(
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
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.section,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final AppSection section;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? Tokens.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
          child: SizedBox(
            height: Tokens.navItemHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
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
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
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
              ),
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
                        Icon(
                          s.icon,
                          size: 20,
                          color: s == section
                              ? Tokens.accent
                              : Tokens.textTertiary,
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
