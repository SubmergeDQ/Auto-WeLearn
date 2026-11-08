import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../components.dart';
import '../nav.dart';
import '../widgets.dart';

/// 面板：一屏看清"跑到哪了、还剩多少、刚才发生了什么"。
///
/// 桌面端把纵向空间用满（指标 → 运行 + 单元 → 结果 + 日志），
/// 移动端保持自然高度滚动，不为填满而拉长卡片。
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.onNavigate,
    required this.onOpenUnit,
  });

  final ValueChanged<AppSection> onNavigate;
  final ValueChanged<int> onOpenUnit;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _logFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final size = MediaQuery.sizeOf(context);
    // 两栏门槛与设置 / 任务页一致：低于 1080 时内容区只剩 800 出头，
    // 再硬分两栏会让右侧的单元与日志挤成一条窄缝。
    final wide = size.width >= 1080;
    final compact = size.width < 720;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 扫描横幅会占掉一行高度；这时不再把卡片拉满剩余空间，
        // 否则运行卡的固定内容（倒计时 / 按钮 / 接下来）会被压到溢出。
        final fill = wide && constraints.maxHeight > 700 && !state.scanning;
        final padding = EdgeInsets.fromLTRB(
          compact ? Tokens.pagePaddingCompact : Tokens.pagePadding,
          compact ? 14 : 20,
          compact ? Tokens.pagePaddingCompact : Tokens.pagePadding,
          24,
        );

        // 空态直接占满剩余高度并垂直居中：手机上不会出现"卡片贴顶、下面一整屏空白"。
        if (!state.loggedIn || state.lessons.isEmpty) {
          return Padding(
            padding: padding,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Tokens.pageMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(state, compact),
                    const SizedBox(height: 16),
                    Expanded(
                      child: PanelCard(
                        padding: EdgeInsets.zero,
                        // SingleChildScrollView 会给子级无限高度，直接塞 EmptyState
                        // 会让「去登录」停在卡片顶部；用 minHeight 撑满可视区再居中。
                        child: LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: EmptyState(
                                    icon: state.loggedIn
                                        ? Icons.cloud_sync_outlined
                                        : (state.autoLoginAttempting
                                              ? Icons.autorenew_rounded
                                              : Icons.person_outline),
                                    // 扫描中的实时反馈已经在标题下的横幅里；
                                    // 空态只说明"扫描完会出现什么"，避免两处都写「正在扫描」。
                                    title: state.loggedIn
                                        ? (state.scanning
                                              ? '扫描完成后显示课程结构'
                                              : '还没有扫描到小节')
                                        : (state.autoLoginAttempting
                                              ? '正在尝试自动登录'
                                              : '还没有登录'),
                                    body: state.loggedIn
                                        ? (state.scanning
                                              ? '单元和小节会在扫描结束后出现在这里和任务页。'
                                              : '到任务页重新扫描一次，就能看到所有小节和待处理数量。')
                                        : (state.autoLoginAttempting
                                              ? '正在用保存的账号密码恢复登录状态，请稍候…'
                                              : '在设置里用内置浏览器登录 WE Learn，或者粘贴一份 Cookie。登录后才能扫描课程与运行任务。'),
                                    actionLabel: state.loggedIn
                                        ? (state.scanning ? null : '去任务页')
                                        : (state.autoLoginAttempting
                                              ? null
                                              : '去登录'),
                                    onAction: state.loggedIn
                                        ? (state.scanning
                                              ? null
                                              : () => widget.onNavigate(
                                                  AppSection.tasks,
                                                ))
                                        : (state.autoLoginAttempting
                                              ? null
                                              : () => widget.onNavigate(
                                                  AppSection.settings,
                                                )),
                                  ),
                                ),
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final body = _body(state, wide: wide, compact: compact, fill: fill);

        if (!fill) {
          return SingleChildScrollView(
            padding: padding,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Tokens.pageMaxWidth,
                ),
                child: body,
              ),
            ),
          );
        }

        return Padding(
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Tokens.pageMaxWidth),
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: body,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(AppState state, bool compact) {
    // 扫描进度条挂在标题行下面，空态和正常态都能看见，不需要两处各写一遍
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '面板',
          subtitle: _subtitle(state),
          compact: compact,
          actions: [
            ScanButton(
              scanning: state.scanning,
              label: '重新扫描',
              onPressed:
                  state.loggedIn && !state.running && state.currentCid != null
                  ? () => state.loadCourse(state.currentCid!)
                  : null,
            ),
            if (state.running)
              OutlinedButton.icon(
                onPressed: state.stopRun,
                style: toolbarDanger(),
                icon: const Icon(Icons.stop_rounded, size: 16),
                label: const Text('停止'),
              )
            else
              FilledButton.icon(
                style: toolbarFilled(),
                onPressed: state.selectedCount == 0 ? null : state.startRun,
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: Text(
                  state.selectedCount == 0
                      ? '开始运行'
                      : '开始运行 · ${state.selectedCount} 节',
                ),
              ),
          ],
        ),
        if (state.scanning) ...[
          const SizedBox(height: 12),
          ScanIndicator(stage: state.scanStage, compact: compact),
        ],
      ],
    );
  }

  Widget _body(
    AppState state, {
    required bool wide,
    required bool compact,
    required bool fill,
  }) {
    // 上下两行必须用同一条分栏比例。之前上行 3:1、下行 3:4，
    // 两条竖向接缝错开，卡片看起来像没对齐。
    Widget twoColumns({
      required Widget left,
      required Widget right,
      required bool stretch,
    }) => Row(
      crossAxisAlignment: stretch
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: left),
        const SizedBox(width: 16),
        Expanded(flex: 1, child: right),
      ],
    );

    final logCard = _LogCard(
      state: state,
      filter: _logFilter,
      onFilter: (f) => setState(() => _logFilter = f),
      fill: fill,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(state, compact),
        SizedBox(height: compact ? 14 : 18),
        _Metrics(state: state, compact: compact),
        SizedBox(height: compact ? 12 : 16),
        // 卡片顺序按要求固定：4 个指标 → 运行 → 最近完成 → 单元完整度 → 日志。
        // 宽屏两两并排，但阅读顺序仍是从上到下、从左到右。
        if (wide && fill)
          Expanded(
            flex: 6,
            child: twoColumns(
              left: _RunCard(state: state, fill: fill),
              right: _RecentCard(state: state, fill: fill),
              stretch: true,
            ),
          )
        else if (wide)
          twoColumns(
            left: _RunCard(state: state, fill: false),
            right: _RecentCard(state: state, fill: false),
            stretch: false,
          )
        else ...[
          _RunCard(state: state, fill: false),
          const SizedBox(height: 12),
          _RecentCard(state: state, fill: false),
        ],
        SizedBox(height: compact ? 12 : 16),
        if (wide && fill)
          Expanded(
            flex: 5,
            child: twoColumns(
              left: _UnitsCard(
                state: state,
                onOpenUnit: widget.onOpenUnit,
                fill: fill,
              ),
              right: logCard,
              stretch: true,
            ),
          )
        else if (wide)
          twoColumns(
            left: _UnitsCard(
              state: state,
              onOpenUnit: widget.onOpenUnit,
              fill: false,
            ),
            right: logCard,
            stretch: false,
          )
        else ...[
          _UnitsCard(state: state, onOpenUnit: widget.onOpenUnit, fill: false),
          const SizedBox(height: 12),
          logCard,
        ],
      ],
    );
  }

  String _subtitle(AppState state) {
    if (!state.loggedIn) return '未连接账号';
    final course = state.currentCourse;
    if (course == null) return '已连接账号';
    return '${course.name} · 平台进度 ${course.percent}%';
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.state, required this.compact});

  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final totalVisible = state.lessons.where((l) => l.visible).length;
    final hidden = state.lessons.length - totalVisible;
    final cards = [
      MetricCard(
        label: '已完成',
        value: '${state.doneCount}',
        unit: '/ $totalVisible',
        hint: state.currentCourse == null
            ? null
            : '平台进度 ${state.currentCourse!.percent}%',
        accent: Tokens.success,
        icon: Icons.check_circle_outline,
      ),
      MetricCard(
        label: '待处理',
        value: '${state.candidates.length}',
        unit: '节',
        hint: hidden > 0 ? '另有 $hidden 节未解锁' : '全部小节已解锁',
        icon: Icons.pending_outlined,
      ),
      MetricCard(
        label: '失败',
        value: '${state.failedCount}',
        unit: '节',
        hint: state.failedCount > 0 ? '可在任务页筛选后重试' : '本次没有失败',
        accent: state.failedCount > 0 ? Tokens.danger : null,
        icon: Icons.error_outline,
      ),
      MetricCard(
        label: '预计剩余',
        value: humanDuration(state.remainingEstimate),
        hint: '按已选 ${state.selectedCount} 节估算',
        icon: Icons.schedule_outlined,
      ),
    ];

    if (compact) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 10),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.state, required this.fill});

  final AppState state;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final lesson = state.currentScoid == null
        ? null
        : state.lessons.where((l) => l.scoid == state.currentScoid).firstOrNull;
    final upcoming = _upcoming();
    // 先建好行，fill 时放进可滚动区域，避免长标题把「接下来」最后一行顶出卡片。
    final upcomingRows = <Widget>[
      for (final l in upcoming)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              StatusDot(state.statusOf(l.scoid), size: 6),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shortLocation(l),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];

    return PanelCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                state.running ? '正在运行' : '运行',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              if (state.running)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Tokens.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '第 ${state.runDone + 1} / ${state.runTotal} 节',
                    style: monoStyle(size: 10.5, color: Tokens.accent),
                  ),
                )
              else if (state.runTotal > 0)
                Text(
                  '上次 ${state.runDone} / ${state.runTotal} 节',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Tokens.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.running && lesson != null) ...[
            Text(
              // 平台可能把单元写成 U01，这里和单元标题一样统一成 Unit 1
              displayLocation(lesson),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  state.inGap
                      ? clockText(state.gapRemain)
                      : clockText(state.currentWait - state.currentElapsed),
                  style: monoStyle(
                    size: 46,
                    weight: FontWeight.w600,
                    color: Tokens.accent,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 8),
                  child: Text(
                    state.inGap ? '后进入下一节' : '剩余',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Tokens.textTertiary,
                    ),
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      state.currentStage,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '心跳 ${state.currentHeartbeats} 次',
                      style: monoStyle(size: 10.5, color: Tokens.textTertiary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ThinBar(
              value: state.inGap
                  ? (state.gapTotal == 0
                        ? 0
                        : state.gapElapsed / state.gapTotal)
                  : (state.currentWait == 0
                        ? 0
                        : state.currentElapsed / state.currentWait),
              height: 4,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  state.inGap ? '间隔用时' : '本节用时',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Tokens.textTertiary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  state.inGap
                      ? '${clockText(state.gapElapsed)} / ${clockText(state.gapTotal)}'
                      : '${clockText(state.currentElapsed)} / ${clockText(state.currentWait)}',
                  style: monoStyle(size: 10.5, color: Tokens.textTertiary),
                ),
              ],
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${state.selectedCount}',
                  style: monoStyle(
                    size: 46,
                    weight: FontWeight.w600,
                    color: Tokens.textPrimary,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10, left: 6),
                  child: Text(
                    '节已选',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Tokens.textTertiary,
                    ),
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      humanDuration(state.remainingEstimate),
                      style: monoStyle(size: 13, color: Tokens.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '预计总耗时',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Tokens.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ThinBar(
              value: state.runTotal == 0 ? 0 : state.runProgress,
              height: 4,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.selectedCount == 0
                        ? '还没有勾选小节，去任务页选择要跑的节'
                        : _lastRunLine(state),
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Tokens.textTertiary,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: state.selectedCount == 0 ? null : state.startRun,
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: const Text('开始运行'),
                ),
              ],
            ),
          ],
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const Text(
              '接下来',
              style: TextStyle(
                fontSize: 11,
                color: Tokens.textTertiary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            // fill 时按剩余高度只显示完整的行：长标题或小窗口下不会把
            // 最后一行画到卡片边界外，也不会出现半截文字。
            if (fill)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const rowHeight = 22.0;
                    final maxRows = (constraints.maxHeight / rowHeight).floor();
                    return Column(
                      children: upcomingRows
                          .take(maxRows.clamp(0, upcomingRows.length).toInt())
                          .toList(),
                    );
                  },
                ),
              )
            else
              for (final row in upcomingRows) row,
          ],
        ],
      ),
    );
  }

  List<Lesson> _upcoming() {
    final queue = state.selectedLessons();
    if (queue.isEmpty) return const [];
    final index = queue.indexWhere((l) => l.scoid == state.currentScoid);
    final start = index >= 0 ? index + 1 : 0;
    // 先取候选，fill 时由 LayoutBuilder 按剩余高度裁掉放不下的整行。
    return queue.skip(start).take(fill ? 4 : 2).toList();
  }

  String _lastRunLine(AppState state) {
    final duration = state.lastRunDuration;
    if (duration == null) {
      return '运行参数在任务页调整；运行中可随时停止，当前节不会提交。';
    }
    return '上次运行用时 ${humanDuration(duration.inSeconds)}，已完成的节不会重复提交。';
  }
}

class _UnitsCard extends StatelessWidget {
  const _UnitsCard({
    required this.state,
    required this.onOpenUnit,
    required this.fill,
  });

  final AppState state;
  final ValueChanged<int> onOpenUnit;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final unit in state.units.where((u) => u.visible)) {
      final inUnit = state.lessons
          .where((l) => l.unitIndex == unit.index)
          .toList();
      if (inUnit.isEmpty) continue;
      final done = inUnit
          .where((l) => state.statusOf(l.scoid) == LessonStatus.done)
          .length;
      final total = inUnit.length;
      rows.add(
        InkWell(
          onTap: () => onOpenUnit(unit.index),
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: fill ? 9 : 6,
              horizontal: 0,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        unit.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    Text(
                      '$done/$total',
                      style: monoStyle(
                        size: 10.5,
                        color: done == total
                            ? Tokens.success
                            : Tokens.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ThinBar(
                  value: total == 0 ? 0 : done / total,
                  height: 3,
                  color: done == total ? Tokens.success : Tokens.accent,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final list = Column(children: rows);

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '单元完成度',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${rows.length} 个单元',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Tokens.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '单元列表还是空的，先重新扫描。',
                style: TextStyle(fontSize: 11.5, color: Tokens.textTertiary),
              ),
            )
          else if (fill)
            Expanded(child: SingleChildScrollView(child: list))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 230),
              child: SingleChildScrollView(child: list),
            ),
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.state, required this.fill});

  final AppState state;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final items = state.recentResults.take(fill ? 8 : 5).toList();

    final list = Column(
      children: [
        for (final r in items)
          Padding(
            padding: EdgeInsets.symmetric(vertical: fill ? 7 : 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: StatusDot(r.status, size: 7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nameOf(r.scoid),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${r.stat.answered}/${r.stat.questions} 题 · '
                        '${relativeTimeText(r.finishedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Tokens.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${r.waitSec}s',
                    textAlign: TextAlign.right,
                    style: monoStyle(size: 10.5, color: Tokens.textTertiary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最近完成',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '还没有运行记录。开始运行后，这里按倒序显示每节结果。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Tokens.textTertiary,
                  height: 1.5,
                ),
              ),
            )
          else if (fill)
            Expanded(child: SingleChildScrollView(child: list))
          else
            list,
        ],
      ),
    );
  }

  String _nameOf(String scoid) {
    final lesson = state.lessons.where((l) => l.scoid == scoid).firstOrNull;
    return lesson == null ? scoid : shortLocation(lesson);
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.state,
    required this.filter,
    required this.onFilter,
    required this.fill,
  });

  final AppState state;
  final String filter;
  final ValueChanged<String> onFilter;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final entries = state.logs.where((l) {
      if (filter == 'beat') return l.level == 'beat';
      if (filter == 'error') return l.level == 'error' || l.level == 'warn';
      return true;
    }).toList();
    // 面板日志跟随卡片高度：宽屏拉满时显示 16 条，窄屏保持 8 条；
    // 内存里则保留最近 2000 条，长挂机不会整段丢失。
    final limit = fill ? 16 : 8;
    final visible = entries.length > limit
        ? entries.sublist(entries.length - limit)
        : entries;

    final lines = Column(
      children: [
        for (final e in visible)
          LogLine(time: e.clock, level: e.level, message: e.message),
      ],
    );

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '日志',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              _LogFilter(
                label: '全部',
                active: filter == 'all',
                onTap: () => onFilter('all'),
              ),
              const SizedBox(width: 4),
              _LogFilter(
                label: '心跳',
                active: filter == 'beat',
                onTap: () => onFilter('beat'),
              ),
              const SizedBox(width: 4),
              _LogFilter(
                label: '异常',
                active: filter == 'error',
                onTap: () => onFilter('error'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '这一类还没有记录。',
                style: TextStyle(fontSize: 11.5, color: Tokens.textTertiary),
              ),
            )
          else if (fill)
            Expanded(child: ListView(children: [lines]))
          else
            lines,
        ],
      ),
    );
  }
}

class _LogFilter extends StatelessWidget {
  const _LogFilter({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      // 固定 24 高让三个筛选标签与 12px 的「日志」标题在同一水平线上
      child: SizedBox(
        height: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: active ? Tokens.accent : Tokens.textTertiary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
