import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../theme.dart';
import 'app_scope.dart';
import 'dialogs.dart';
import 'mobile/mobile_shell.dart';
import 'widgets.dart';

export 'app_scope.dart';

class WorkbenchShell extends StatelessWidget {
  const WorkbenchShell({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final state = AppScope.of(context);
        if (constraints.maxWidth < 760) return const MobileShell();
        return _DesktopShell(
          compact: constraints.maxWidth < 1180,
          state: state,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 桌面：三栏
// ═══════════════════════════════════════════════════════════
class _DesktopShell extends StatelessWidget {
  const _DesktopShell({required this.compact, required this.state});
  final bool compact;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(compact: compact),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 264, child: _Sidebar()),
                  const VerticalDivider(width: 1),
                  const Expanded(child: _QueuePane()),
                  if (!compact) ...[
                    const VerticalDivider(width: 1),
                    const SizedBox(width: 372, child: _RunPane()),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            const _StatusBar(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 顶栏
// ═══════════════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  const _TopBar({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final course = state.currentCourse;

    return Container(
      height: 64,
      color: Tokens.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: Tokens.controlHeight,
            height: Tokens.controlHeight,
            decoration: BoxDecoration(
              color: Tokens.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.school_outlined,
              size: 18,
              color: Tokens.accent,
            ),
          ),
          const SizedBox(width: 10),
          // Expanded 而不是 Spacer：课程名过长时省略，避免把右侧按钮挤出屏幕
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WeLearn 助手',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  course == null
                      ? '尚未选择课程'
                      : '${course.name} · ${course.percent}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Tokens.textTertiary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (!state.loggedIn)
            FilledButton(
              key: const Key('toolbar-run'),
              style: toolbarFilled(),
              onPressed: state.busy ? null : () => showLoginDialog(context),
              child: Text(state.busy ? '连接中…' : '登录'),
            )
          else ...[
            _AccountChip(state: state),
            const SizedBox(width: 8),
            _IconAction(
              key: const Key('toolbar-settings'),
              icon: Icons.tune,
              tooltip: '运行设置',
              onTap: () => showRunSettings(context),
            ),
            const SizedBox(width: 8),
            if (state.running)
              OutlinedButton.icon(
                key: const Key('toolbar-run'),
                style: toolbarOutlined(),
                onPressed: state.stopRun,
                icon: const Icon(
                  Icons.stop_rounded,
                  size: 16,
                  color: Tokens.danger,
                ),
                label: const Text('停止', style: TextStyle(color: Tokens.danger)),
              )
            else
              FilledButton.icon(
                key: const Key('toolbar-run'),
                style: toolbarFilled(),
                onPressed: state.candidates.isEmpty ? null : state.startRun,
                icon: const Icon(Icons.play_arrow_rounded, size: 17),
                label: Text(
                  '开始运行${state.candidates.isEmpty ? '' : ' · ${state.candidates.length} 节'}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 账号入口：点开可以切换课程、重新扫描、退出登录。
/// 顶栏其余控件都是 32 高，这里也钉死 32，避免胶囊比按钮矮一截。
class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('account-chip'),
      tooltip: '账号',
      offset: const Offset(0, Tokens.controlHeight + 6),
      color: Tokens.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: const BorderSide(color: Tokens.border),
      ),
      onSelected: (value) async {
        if (value == '__logout__') {
          if (await confirmLogout(context)) await state.logout();
          return;
        }
        if (value == '__rescan__') {
          final cid = state.currentCid;
          if (cid != null) await state.loadCourse(cid);
          return;
        }
        if (value.startsWith('course:')) {
          await state.loadCourse(value.substring('course:'.length));
        }
      },
      itemBuilder: (context) => [
        if (state.courses.length > 1) ...[
          const PopupMenuItem<String>(
            enabled: false,
            height: 30,
            child: Text(
              '切换课程',
              style: TextStyle(fontSize: 11, color: Tokens.textTertiary),
            ),
          ),
          for (final c in state.courses)
            PopupMenuItem<String>(
              value: 'course:${c.cid}',
              height: 36,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: c.cid == state.currentCid
                        ? const Icon(
                            Icons.check,
                            size: 14,
                            color: Tokens.accent,
                          )
                        : null,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 230),
                    child: Text(
                      '${c.name} · ${c.percent}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: c.cid == state.currentCid
                            ? Tokens.textPrimary
                            : Tokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem<String>(
          value: '__rescan__',
          height: 36,
          enabled: state.currentCid != null,
          child: const Row(
            children: [
              Icon(Icons.refresh, size: 15, color: Tokens.textSecondary),
              SizedBox(width: 8),
              Text('重新扫描', style: TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__logout__',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 15, color: Tokens.danger),
              SizedBox(width: 8),
              Text(
                '退出登录',
                style: TextStyle(fontSize: 12.5, color: Tokens.danger),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        height: Tokens.controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Tokens.success.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Tokens.success.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 13,
              color: Tokens.success,
            ),
            const SizedBox(width: 5),
            const Text(
              '已登录',
              style: TextStyle(
                fontSize: 11.5,
                color: Tokens.success,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 3),
            // 视觉上抬 1.5px：文字行盒含下沉部分，纯居中会让三角看起来偏低
            Transform.translate(
              offset: const Offset(0, -1.5),
              child: Caret(color: Tokens.success.withValues(alpha: 0.75), width: 7),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: Container(
          width: Tokens.controlHeight,
          height: Tokens.controlHeight,
          decoration: BoxDecoration(
            border: Border.all(color: Tokens.border),
            borderRadius: BorderRadius.circular(Tokens.radiusControl),
          ),
          child: Icon(icon, size: 16, color: Tokens.textSecondary),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 左栏：课程与单元
// ═══════════════════════════════════════════════════════════
class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final course = state.currentCourse;

    return Container(
      color: Tokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('课程'),
                Container(
                  key: const Key('course-card'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Tokens.surfaceAlt,
                    borderRadius: BorderRadius.circular(Tokens.radiusCard),
                    border: Border.all(color: Tokens.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course?.name ?? '未登录',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${course?.percent ?? 0}',
                            style: monoStyle(
                              size: 22,
                              weight: FontWeight.w600,
                              color: Tokens.accent,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3, left: 2),
                            child: Text(
                              '%',
                              style: monoStyle(size: 12, color: Tokens.accent),
                            ),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '平台进度',
                              style: TextStyle(
                                fontSize: 11,
                                color: Tokens.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ThinBar(value: (course?.percent ?? 0) / 100),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: SectionLabel(
              '单元',
              trailing: Text(
                '${state.lessons.length} 节',
                style: monoStyle(size: 10.5, color: Tokens.textTertiary),
              ),
            ),
          ),
          Expanded(
            child: state.units.isEmpty
                ? _EmptyHint(
                    icon: Icons.layers_outlined,
                    text: state.loggedIn ? '扫描后显示单元' : '登录后显示单元',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: state.units.length,
                    itemBuilder: (context, i) {
                      final unit = state.units[i];
                      final inUnit = state.lessons
                          .where((l) => l.unitIndex == unit.index)
                          .toList();
                      final done = inUnit
                          .where(
                            (l) => state.statusOf(l.scoid) == LessonStatus.done,
                          )
                          .length;
                      return _UnitRow(
                        unit: unit,
                        done: done,
                        total: inUnit.length,
                        selected: state.selectedUnit == unit.index,
                        onTap: () => state.setUnit(
                          state.selectedUnit == unit.index ? null : unit.index,
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            // 与上方课程卡片的 16px 左右边距保持一致，否则按钮会比卡片宽出一圈
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: OutlinedButton.icon(
              key: const Key('sidebar-rescan'),
              style: toolbarOutlined(),
              onPressed: state.currentCid == null
                  ? null
                  : () => state.loadCourse(state.currentCid!),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新扫描'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.unit,
    required this.done,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  final CourseUnit unit;
  final int done;
  final int total;
  final bool selected;
  final VoidCallback onTap;

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    unit.unitName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? Tokens.accent : Tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$done/$total',
                  style: monoStyle(
                    size: 10.5,
                    color: done == total && total > 0
                        ? Tokens.success
                        : Tokens.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 中栏：队列
// ═══════════════════════════════════════════════════════════
class _QueuePane extends StatelessWidget {
  const _QueuePane();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final list = state.visibleLessons;

    return Container(
      color: Tokens.surface,
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: '全部',
                  count: state.lessons.length,
                  active: state.filter == 'all',
                  onTap: () => state.setFilter('all'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '待处理',
                  count: state.candidates.length,
                  active: state.filter == 'pending',
                  onTap: () => state.setFilter('pending'),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '失败',
                  count: state.failedCount,
                  active: state.filter == 'failed',
                  onTap: () => state.setFilter('failed'),
                ),
                const Spacer(),
                SizedBox(
                  width: 200,
                  height: Tokens.controlHeight,
                  child: TextField(
                    key: const Key('queue-search'),
                    onChanged: state.setQuery,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      hintText: '搜索小节',
                      prefixIcon: Icon(
                        Icons.search,
                        size: 15,
                        color: Tokens.textTertiary,
                      ),
                      prefixIconConstraints: BoxConstraints(minWidth: 32),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (state.selectedUnit != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              color: Tokens.accentSoft.withValues(alpha: 0.5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '仅显示 ${state.units.firstWhere((u) => u.index == state.selectedUnit, orElse: () => state.units.first).unitName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Tokens.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => state.setUnit(null),
                    child: const Text(
                      '清除',
                      style: TextStyle(
                        fontSize: 11.5,
                        decoration: TextDecoration.underline,
                        color: Tokens.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? _EmptyHint(
                    icon: state.loggedIn
                        ? Icons.inbox_outlined
                        : Icons.lock_outline,
                    text: state.loggedIn ? '没有符合条件的小节' : '先登录，再选择课程',
                    action: state.loggedIn
                        ? null
                        : TextButton(
                            onPressed: () => showLoginDialog(context),
                            child: const Text('去登录'),
                          ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final lesson = list[i];
                      return LessonTile(
                        index: i + 1,
                        lesson: lesson,
                        status: state.statusOf(lesson.scoid),
                        selected: state.selectedScoid == lesson.scoid,
                        onTap: () => state.select(lesson.scoid),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.radiusControl),
      child: Container(
        // 与右侧搜索框同高，filter 行才不会一边高一边矮
        height: Tokens.controlHeight,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? Tokens.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
          border: Border.all(
            color: active ? Tokens.textPrimary : Tokens.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : Tokens.textSecondary,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: monoStyle(
                size: 10.5,
                color: active ? Colors.white70 : Tokens.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 右栏：运行与日志
// ═══════════════════════════════════════════════════════════
class _RunPane extends StatefulWidget {
  const _RunPane();
  @override
  State<_RunPane> createState() => _RunPaneState();
}

class _RunPaneState extends State<_RunPane> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _scrollToBottom();

    final lesson = state.selectedLesson;
    final current = state.currentScoid == null
        ? null
        : state.lessons.where((l) => l.scoid == state.currentScoid).firstOrNull;
    final focus = current ?? lesson;

    return Container(
      color: Tokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '运行',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Tokens.textPrimary,
                  ),
                ),
                const Spacer(),
                if (state.running)
                  Row(
                    children: [
                      const SizedBox(
                        width: 6,
                        height: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Tokens.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '运行中',
                        style: TextStyle(fontSize: 11, color: Tokens.accent),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 卡片与日志的左边缘统一到 16，和「运行」「日志」两个标题对齐
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _CurrentCard(state: state, lesson: focus),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  '日志',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Tokens.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${state.logs.length} 条',
                  style: monoStyle(size: 10.5, color: Tokens.textTertiary),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.logs.isEmpty
                ? _EmptyHint(icon: Icons.terminal, text: '运行后在这里看到每节进度')
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: state.logs.length,
                    itemBuilder: (context, i) {
                      final log = state.logs[i];
                      return LogLine(
                        time: log.clock,
                        level: log.level,
                        message: log.message,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.state, required this.lesson});
  final AppState state;
  final Lesson? lesson;

  @override
  Widget build(BuildContext context) {
    final l = lesson;
    if (l == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tokens.surfaceAlt,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          border: Border.all(color: Tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '未选择小节',
              style: TextStyle(fontSize: 12.5, color: Tokens.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              '点击队列中的任意一行查看详情',
              style: TextStyle(fontSize: 11.5, color: Tokens.textTertiary),
            ),
          ],
        ),
      );
    }

    final running = state.currentScoid == l.scoid;
    final total = state.currentWait == 0 ? 1 : state.currentWait;
    final progress = running
        ? (state.currentElapsed / total).clamp(0.0, 1.0)
        : 0.0;
    final remain = (total - state.currentElapsed).clamp(0, total);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.all(color: Tokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.location,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.scoid,
            style: monoStyle(size: 10.5, color: Tokens.textTertiary),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _clock(running ? remain : total),
                style: monoStyle(
                  size: 34,
                  weight: FontWeight.w600,
                  color: running ? Tokens.accent : Tokens.textTertiary,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 6),
                child: Text(
                  running ? '剩余' : '预计等待',
                  style: TextStyle(fontSize: 11, color: Tokens.textTertiary),
                ),
              ),
              const Spacer(),
              if (running)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '心跳 ${state.currentHeartbeats}',
                      style: monoStyle(size: 11, color: Tokens.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${state.currentElapsed}s / ${total}s',
                      style: monoStyle(size: 10.5, color: Tokens.textTertiary),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          ThinBar(value: progress, height: 3),
          const SizedBox(height: 14),
          Row(
            children: [
              _Meta(
                label: '题目',
                value: '${state.results[l.scoid]?.stat.questions ?? '—'}',
              ),
              const SizedBox(width: 18),
              _Meta(label: '状态', value: state.statusOf(l.scoid).label),
              const Spacer(),
              StatusPill(state.statusOf(l.scoid)),
            ],
          ),
        ],
      ),
    );
  }

  static String _clock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: Tokens.textTertiary),
        ),
        const SizedBox(width: 5),
        Text(value, style: monoStyle(size: 11.5, color: Tokens.textPrimary)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 底栏
// ═══════════════════════════════════════════════════════════
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final remain = state.remainingEstimate;

    return Container(
      height: 44,
      color: Tokens.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: ThinBar(value: state.progress, height: 4),
          ),
          const SizedBox(width: 12),
          Text(
            '${(state.progress * 100).round()}%',
            style: monoStyle(size: 11, color: Tokens.textSecondary),
          ),
          const SizedBox(width: 20),
          _Count(label: '已完成', value: state.doneCount, color: Tokens.success),
          const SizedBox(width: 14),
          _Count(label: '失败', value: state.failedCount, color: Tokens.danger),
          const SizedBox(width: 14),
          _Count(
            label: '待处理',
            value: state.candidates.length,
            color: Tokens.textSecondary,
          ),
          const Spacer(),
          if (state.running || remain > 0)
            Text(
              state.running ? '剩余约 ${_human(remain)}' : '预计 ${_human(remain)}',
              style: const TextStyle(fontSize: 11, color: Tokens.textTertiary),
            ),
        ],
      ),
    );
  }

  static String _human(int seconds) {
    if (seconds <= 0) return '0 分钟';
    final m = (seconds / 60).round();
    if (m < 60) return '$m 分钟';
    final h = m ~/ 60;
    return '$h 小时 ${m % 60} 分';
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Tokens.textTertiary),
        ),
        const SizedBox(width: 5),
        Text('$value', style: monoStyle(size: 11.5, color: Tokens.textPrimary)),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: const Color(0xFFC4CAD3)),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: Tokens.textTertiary),
          ),
          ?action,
        ],
      ),
    );
  }
}
