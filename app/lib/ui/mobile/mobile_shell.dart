import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../dialogs.dart';
import '../widgets.dart';

/// 移动端：运行卡 + 单元条 + 分组队列 + 三段式底栏。
/// 桌面三栏在 ui/shell.dart，两边只共享 AppState 与 widgets。
class MobileShell extends StatelessWidget {
  const MobileShell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final course = state.currentCourse;

    return Scaffold(
      backgroundColor: Tokens.surface,
      appBar: AppBar(
        backgroundColor: Tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              course?.name ?? 'WeLearn 助手',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.2),
            ),
            const SizedBox(height: 2),
            Text(
              _subtitle(state),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Tokens.textTertiary, height: 1.2),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('mobile-logs'),
            onPressed: () => showLogSheet(context),
            icon: const Icon(Icons.receipt_long_outlined, size: 22),
            tooltip: '日志',
          ),
          _AccountMenu(state: state),
          const SizedBox(width: 4),
        ],
      ),
      body: state.loggedIn ? _Body(state: state) : _EmptyLogin(state: state),
      bottomNavigationBar: _BottomBar(state: state),
    );
  }

  static String _subtitle(AppState state) {
    if (!state.loggedIn) return '未连接账号';
    final failed = state.failedCount;
    return '${state.candidates.length} 节待处理${failed > 0 ? ' · $failed 失败' : ''}';
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RunPanel(state: state),
        if (state.units.length > 1) _UnitStrip(state: state),
        const Divider(height: 1),
        Expanded(child: _LessonList(state: state)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 运行卡
// ═══════════════════════════════════════════════════════════
class _RunPanel extends StatelessWidget {
  const _RunPanel({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scoid = state.currentScoid;
    final running = state.running && scoid != null;
    final current = running ? state.lessons.where((l) => l.scoid == scoid).firstOrNull : null;

    if (!running) return _IdlePanel(state: state);

    final total = state.currentWait <= 0 ? 1 : state.currentWait;
    final remain = (total - state.currentElapsed).clamp(0, total);
    final progress = (state.currentElapsed / total).clamp(0.0, 1.0);

    return Container(
      key: const Key('mobile-run-card'),
      constraints: const BoxConstraints(minHeight: Tokens.runCardHeight),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(bottom: BorderSide(color: Tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StatusDot(LessonStatus.running),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  current == null ? '正在运行' : shortLocation(current),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                ),
              ),
              TextButton(
                onPressed: () => _confirmStop(context, state),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 26),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: Tokens.danger,
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
                child: const Text('停止'),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _clock(remain),
                style: monoStyle(size: 30, weight: FontWeight.w600, color: Tokens.accent),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5, left: 6),
                child: Text('剩余', style: TextStyle(fontSize: 11, color: Tokens.textTertiary)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('心跳 ${state.currentHeartbeats}',
                        style: monoStyle(size: 11, color: Tokens.textSecondary)),
                    const SizedBox(height: 1),
                    Text('${state.currentElapsed}s / ${state.currentWait}s',
                        style: monoStyle(size: 10.5, color: Tokens.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ThinBar(value: progress, height: 3),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '第 ${(state.runDone + 1).clamp(1, state.runTotal <= 0 ? 1 : state.runTotal)}/${state.runTotal} 节',
                style: monoStyle(size: 10.5, color: Tokens.textTertiary),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('${state.doneCount} 已完成',
                    style: monoStyle(size: 10.5, color: Tokens.textTertiary)),
              ),
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

/// 空闲态：一行「下一节 · xx · 预计 6 分」，点了滚动定位（此处仅显示）
class _IdlePanel extends StatelessWidget {
  const _IdlePanel({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final next = state.candidates.firstOrNull;
    final avg = ((state.settings.waitMin + state.settings.waitMax) ~/ 2) ~/ 60;

    return Container(
      key: const Key('mobile-idle-card'),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(bottom: BorderSide(color: Tokens.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_outline, size: 15, color: Tokens.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              next == null ? '队列为空，先重新扫描' : '下一节 · ${shortLocation(next)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Tokens.textSecondary),
            ),
          ),
          if (next != null)
            Text('预计 $avg 分', style: monoStyle(size: 10.5, color: Tokens.textTertiary)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 单元条
// ═══════════════════════════════════════════════════════════
class _UnitStrip extends StatelessWidget {
  const _UnitStrip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(bottom: BorderSide(color: Tokens.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: state.units.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _UnitChip(
              label: '全部',
              active: state.selectedUnit == null,
              onTap: () => state.setUnit(null),
            );
          }
          final unit = state.units[i - 1];
          final count = state.lessons.where((l) => l.unitIndex == unit.index).length;
          return _UnitChip(
            label: '${_shortUnit(unit.unitName)} · $count',
            active: state.selectedUnit == unit.index,
            onTap: () => state.setUnit(state.selectedUnit == unit.index ? null : unit.index),
          );
        },
      ),
    );
  }

  static String _shortUnit(String name) {
    final m = RegExp(r'(\d+)').firstMatch(name);
    return m == null ? name : 'U${m.group(1)}';
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 28,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: active ? Tokens.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? Tokens.accent.withValues(alpha: 0.35) : Tokens.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: active ? Tokens.accent : Tokens.textSecondary,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 分组队列
// ═══════════════════════════════════════════════════════════
class _LessonList extends StatelessWidget {
  const _LessonList({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final list = state.visibleLessons;
    if (list.isEmpty) return _EmptyQueue(state: state);

    final groups = <int, List<Lesson>>{};
    for (final lesson in list) {
      groups.putIfAbsent(lesson.unitIndex, () => <Lesson>[]).add(lesson);
    }
    final keys = groups.keys.toList()..sort();

    final slivers = <Widget>[];
    var ordinal = 0;
    for (final key in keys) {
      final lessons = groups[key]!;
      final pending = lessons.where((l) => state.statusOf(l.scoid) == LessonStatus.pending).length;
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _UnitHeaderDelegate(
            title: '第 ${key + 1} 单元',
            detail: '${lessons.length} 节 · $pending 待处理',
          ),
        ),
      );
      slivers.add(
        SliverList.builder(
          itemCount: lessons.length,
          itemBuilder: (context, i) {
            final lesson = lessons[i];
            ordinal++;
            final status = state.statusOf(lesson.scoid);
            return LessonTile(
              index: ordinal,
              lesson: lesson,
              status: status,
              selected: state.selectedScoid == lesson.scoid,
              height: Tokens.mobileRowHeight,
              maxLines: 2,
              showChevron: true,
              onTap: () {
                state.select(lesson.scoid);
                showLessonSheet(context, lesson);
              },
            );
          },
        ),
      );
    }

    return CustomScrollView(
      slivers: [...slivers, const SliverToBoxAdapter(child: SizedBox(height: 12))],
    );
  }
}

class _UnitHeaderDelegate extends SliverPersistentHeaderDelegate {
  _UnitHeaderDelegate({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  double get minExtent => 30;

  @override
  double get maxExtent => 30;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Tokens.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: Tokens.textSecondary)),
          const SizedBox(width: 8),
          Text(detail, style: monoStyle(size: 10.5, color: Tokens.textTertiary)),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_UnitHeaderDelegate oldDelegate) =>
      oldDelegate.title != title || oldDelegate.detail != detail;
}

// ═══════════════════════════════════════════════════════════
// 底栏
// ═══════════════════════════════════════════════════════════
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final disabled = !state.running && state.candidates.isEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(top: BorderSide(color: Tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: ThinBar(value: state.progress, height: 3)),
                const SizedBox(width: 10),
                Text('${(state.progress * 100).round()}%',
                    style: monoStyle(size: 10.5, color: Tokens.textTertiary)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _StatsLine(state: state)),
                const SizedBox(width: 12),
                SizedBox(
                  height: Tokens.tapMin,
                  child: state.running
                      ? OutlinedButton(
                          onPressed: () => _confirmStop(context, state),
                          child: const Text('停止'),
                        )
                      : FilledButton(
                          key: const Key('mobile-start'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(96, Tokens.tapMin),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          onPressed: disabled ? null : state.startRun,
                          child: const Text('开始运行'),
                        ),
                ),
              ],
            ),
            if (disabled && state.loggedIn) ...[
              const SizedBox(height: 3),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('队列为空，先重新扫描',
                    style: TextStyle(fontSize: 11, color: Tokens.textTertiary)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final remain = state.remainingEstimate;
    final parts = <String>['${state.doneCount} 已完成'];
    if (state.failedCount > 0) parts.add('${state.failedCount} 失败');
    if (!state.running && remain > 0) parts.add('剩余约 ${_human(remain)}');

    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: state.failedCount > 0 ? Tokens.danger : Tokens.textTertiary,
      ),
    );
  }

  static String _human(int seconds) {
    if (seconds <= 0) return '0 分钟';
    final m = (seconds / 60).round();
    if (m < 60) return '$m 分钟';
    return '${m ~/ 60} 小时 ${m % 60} 分';
  }
}

// ═══════════════════════════════════════════════════════════
// 账号菜单
// ═══════════════════════════════════════════════════════════
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('mobile-account'),
      tooltip: '更多',
      icon: const Icon(Icons.more_vert, size: 22),
      offset: const Offset(0, 44),
      color: Tokens.surface,
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
          if (cid != null && !state.running) await state.loadCourse(cid);
          return;
        }
        if (value == '__settings__') {
          if (context.mounted) await showRunSettings(context);
          return;
        }
        if (value.startsWith('course:')) {
          await state.loadCourse(value.substring('course:'.length));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: '__rescan__',
          enabled: state.currentCid != null && !state.running,
          height: 44,
          child: const Row(children: [
            Icon(Icons.refresh, size: 18, color: Tokens.textSecondary),
            SizedBox(width: 10),
            Text('重新扫描', style: TextStyle(fontSize: 13)),
          ]),
        ),
        if (state.courses.length > 1) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            enabled: false,
            height: 30,
            child: Text('切换课程', style: TextStyle(fontSize: 11, color: Tokens.textTertiary)),
          ),
          for (final c in state.courses)
            PopupMenuItem<String>(
              value: 'course:${c.cid}',
              enabled: !state.running,
              height: 44,
              child: Row(children: [
                SizedBox(
                  width: 20,
                  child: c.cid == state.currentCid
                      ? const Icon(Icons.check, size: 15, color: Tokens.accent)
                      : null,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    '${c.name} · ${c.percent}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ]),
            ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__settings__',
          height: 44,
          child: Row(children: [
            Icon(Icons.tune, size: 18, color: Tokens.textSecondary),
            SizedBox(width: 10),
            Text('运行设置', style: TextStyle(fontSize: 13)),
          ]),
        ),
        const PopupMenuDivider(),
        if (state.loggedIn)
          const PopupMenuItem<String>(
            value: '__logout__',
            height: 44,
            child: Row(children: [
              Icon(Icons.logout_rounded, size: 18, color: Tokens.danger),
              SizedBox(width: 10),
              Text('退出登录', style: TextStyle(fontSize: 13, color: Tokens.danger)),
            ]),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 空态
// ═══════════════════════════════════════════════════════════
class _EmptyLogin extends StatelessWidget {
  const _EmptyLogin({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Tokens.accentSoft, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.school_outlined, size: 24, color: Tokens.accent),
            ),
            const SizedBox(height: 14),
            const Text('还没有登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              '用浏览器登录后的 Cookie 连接账号',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Tokens.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: Tokens.tapMin,
              child: FilledButton(
                onPressed: () => showLoginDialog(context),
                child: const Text('粘贴 Cookie 登录'),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _showCookieHelp(context),
              child: const Text('怎么获取 Cookie', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCookieHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusCard)),
        title: const Text('获取 Cookie', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: const SizedBox(
          width: 380,
          child: Text(
            '1. 在电脑浏览器登录 welearn.sflep.com\n'
            '2. 按 F12 → Network，刷新页面，点任意请求\n'
            '3. 复制请求头里的 Cookie 整行\n'
            '4. 发到手机（微信/文件传输助手），回到这里点「从剪贴板读取」\n\n'
            '手机浏览器也能登录，但取 Cookie 需要支持导出插件的浏览器。',
            style: TextStyle(fontSize: 12.5, color: Tokens.textSecondary, height: 1.7),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
        ],
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final noData = state.lessons.isEmpty;
    final filtering = state.selectedUnit != null || state.filter != 'all' || state.query.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 28, color: Tokens.borderStrong),
            const SizedBox(height: 10),
            Text(
              noData ? '没有待处理的小节' : (filtering ? '没有符合条件的小节' : '没有待处理的小节'),
              style: const TextStyle(fontSize: 13, color: Tokens.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              noData ? '可能都完成了，也可能需要重新扫描' : '当前筛选条件下没有内容',
              style: const TextStyle(fontSize: 11.5, color: Tokens.textTertiary),
            ),
            const SizedBox(height: 16),
            if (filtering)
              OutlinedButton(
                onPressed: () {
                  state.setUnit(null);
                  state.setFilter('all');
                  state.setQuery('');
                },
                child: const Text('清除筛选'),
              )
            else
              FilledButton(
                onPressed: state.running || state.currentCid == null
                    ? null
                    : () => state.loadCourse(state.currentCid!),
                child: const Text('重新扫描'),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 抽屉：小节详情 / 日志
// ═══════════════════════════════════════════════════════════
void showLessonSheet(BuildContext context, Lesson lesson) {
  final state = AppScope.of(context);
  final status = state.statusOf(lesson.scoid);
  final result = state.results[lesson.scoid];

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tokens.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.radiusCard)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Tokens.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(lesson.location,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.35)),
            const SizedBox(height: 4),
            Text(lesson.scoid, style: monoStyle(size: 10.5, color: Tokens.textTertiary)),
            const SizedBox(height: 12),
            Row(
              children: [
                StatusPill(status),
                const SizedBox(width: 10),
                if (lesson.learnTime.isNotEmpty && lesson.learnTime != '00:00:00')
                  Text('平台记录 ${lesson.learnTime}',
                      style: monoStyle(size: 11, color: Tokens.textTertiary)),
              ],
            ),
            const SizedBox(height: 14),
            if (result == null)
              const Text(
                '尚未解析，运行到本节时会解析题目',
                style: TextStyle(fontSize: 12, color: Tokens.textTertiary, height: 1.5),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Tokens.surfaceAlt,
                  borderRadius: BorderRadius.circular(Tokens.radiusControl),
                  border: Border.all(color: Tokens.border),
                ),
                child: Row(
                  children: [
                    _Meta(label: '题目', value: '${result.stat.questions}'),
                    const SizedBox(width: 18),
                    _Meta(label: '已答', value: '${result.stat.answered}'),
                    const SizedBox(width: 18),
                    _Meta(label: '口语', value: '${result.stat.oral}'),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: Tokens.tapMin,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: null,
                child: const Text('只跑这一节（暂未支持）'),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '整队列运行时会包含本节；单节运行需要引擎提供入口，尚未实现。',
              style: TextStyle(fontSize: 11, color: Tokens.textTertiary, height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: Tokens.textTertiary)),
        const SizedBox(width: 5),
        Text(value, style: monoStyle(size: 12, color: Tokens.textPrimary)),
      ],
    );
  }
}

void showLogSheet(BuildContext context) {
  final state = AppScope.of(context);
  var filter = 'all';

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Tokens.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.radiusCard)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setLocal) {
        final logs = state.logs.where((l) {
          if (filter == 'beat') return l.level == 'beat';
          if (filter == 'issue') return l.level == 'error' || l.level == 'warn';
          return true;
        }).toList();

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, controller) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (controller.hasClients) {
                controller.jumpTo(controller.position.maxScrollExtent);
              }
            });

            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Tokens.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                  child: Row(
                    children: [
                      _LogChip(label: '全部', active: filter == 'all', onTap: () => setLocal(() => filter = 'all')),
                      const SizedBox(width: 6),
                      _LogChip(label: '心跳', active: filter == 'beat', onTap: () => setLocal(() => filter = 'beat')),
                      const SizedBox(width: 6),
                      _LogChip(label: '异常', active: filter == 'issue', onTap: () => setLocal(() => filter = 'issue')),
                      const Spacer(),
                      IconButton(
                        tooltip: '复制日志',
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        onPressed: () async {
                          final text = logs
                              .map((l) => '${l.clock} ${l.level.toUpperCase().padRight(5)} ${l.message}')
                              .join('\n');
                          await Clipboard.setData(ClipboardData(text: text));
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(content: Text('已复制 ${logs.length} 条日志'), duration: const Duration(seconds: 2)),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: logs.isEmpty
                      ? const Center(
                          child: Text('暂无日志', style: TextStyle(fontSize: 12, color: Tokens.textTertiary)),
                        )
                      : ListView.builder(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                          itemCount: logs.length,
                          itemBuilder: (context, i) {
                            final log = logs[i];
                            return LogLine(time: log.clock, level: log.level, message: log.message);
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class _LogChip extends StatelessWidget {
  const _LogChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 28,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? Tokens.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? Tokens.textPrimary : Tokens.border),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11.5, color: active ? Colors.white : Tokens.textSecondary),
        ),
      ),
    );
  }
}

Future<void> _confirmStop(BuildContext context, AppState state) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Tokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusCard)),
      title: const Text('停止运行', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      content: const Text(
        '当前节不会提交，已完成的节会保留。',
        style: TextStyle(fontSize: 12.5, color: Tokens.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('继续运行')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Tokens.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('停止'),
        ),
      ],
    ),
  );
  if (ok ?? false) state.stopRun();
}
