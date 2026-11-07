import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../components.dart';
import '../nav.dart';
import '../widgets.dart';

/// 任务：扫描结果 + 勾选要跑的节 + 运行参数。
///
/// 参数从原来的弹窗挪到这里，是因为它和"选哪些节"是同一个决定的两半：
/// 选完节马上要看到预计时长，改完等待时长也应该立刻反映到预计上。
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.onNavigate});

  final ValueChanged<AppSection> onNavigate;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final wide = width >= 1080;

    if (!state.loggedIn) {
      return Center(
        child: EmptyState(
          icon: Icons.person_outline,
          title: '还没有登录',
          body: '登录后才能扫描课程、勾选要跑的小节。',
          actionLabel: '去设置登录',
          onAction: () => widget.onNavigate(AppSection.settings),
        ),
      );
    }

    final entries = _buildEntries(state);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? Tokens.pagePaddingCompact : Tokens.pagePadding,
            compact ? 14 : 20,
            compact ? Tokens.pagePaddingCompact : Tokens.pagePadding,
            10,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Tokens.pageMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: '任务',
                    subtitle: _subtitle(state),
                    compact: compact,
                    actions: [
                      TextButton(
                        style: toolbarText(),
                        onPressed: state.lessons.isEmpty || state.scanning
                            ? null
                            : state.selectAllPending,
                        child: const Text('全选待处理'),
                      ),
                      TextButton(
                        style: toolbarText(),
                        onPressed: state.selectedCount == 0 || state.scanning
                            ? null
                            : state.clearSelection,
                        child: const Text('全不选'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 扫描横幅跟面板页一样挂在标题下方通栏显示；
                  // 之前塞在列表区中央，上下留一大片空白，看着像页面没加载出来。
                  if (state.scanning) ...[
                    ScanIndicator(stage: state.scanStage, compact: compact),
                    const SizedBox(height: 12),
                  ],
                  _Toolbar(state: state, search: _search, compact: compact),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Tokens.pageMaxWidth),
              child: SizedBox(
                height: double.infinity,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact
                        ? Tokens.pagePaddingCompact
                        : Tokens.pagePadding,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: PanelCard(
                          padding: EdgeInsets.zero,
                          child: _LessonList(
                            state: state,
                            entries: entries,
                            compact: compact,
                          ),
                        ),
                      ),
                      if (wide) ...[
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 300,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RunPanel(state: state, compact: false),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // 720–1080 之间：没有右栏，也放不下底部摘要条，参数从顶栏齿轮进
        if (!wide)
          _MobileBar(state: state, onParams: () => _showParams(context))
        else
          const SizedBox(height: 16),
      ],
    );
  }

  String _subtitle(AppState state) {
    if (state.lessons.isEmpty) {
      return state.scanning ? '正在扫描课程结构…' : '还没有扫描结果';
    }
    final visible = state.lessons.where((l) => l.visible).length;
    return '${state.units.where((u) => u.visible).length} 单元 · $visible 小节 · '
        '待处理 ${state.candidates.length}';
  }

  List<_Entry> _buildEntries(AppState state) {
    final visible = state.visibleLessons;
    final byUnit = <int, List<Lesson>>{};
    for (final l in visible) {
      byUnit.putIfAbsent(l.unitIndex, () => []).add(l);
    }

    final entries = <_Entry>[];
    for (final unit in state.units.where((u) => u.visible)) {
      final lessons = byUnit[unit.index];
      if (lessons == null || lessons.isEmpty) continue;
      entries.add(_UnitEntry(unit, lessons));
      for (var i = 0; i < lessons.length; i++) {
        entries.add(_LessonEntry(lessons[i], i + 1));
      }
    }
    return entries;
  }

  Future<void> _showParams(BuildContext context) async {
    final state = AppScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Tokens.radiusCard),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 10),
              const Text(
                '运行参数',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                '修改立即生效，作用于之后运行的每一节。',
                style: TextStyle(fontSize: 11.5, color: Tokens.textTertiary),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: SingleChildScrollView(
                  child: _RunPanel(state: state, compact: true, embedded: true),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: Tokens.tapMin,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

sealed class _Entry {
  const _Entry();
}

class _UnitEntry extends _Entry {
  const _UnitEntry(this.unit, this.lessons);
  final CourseUnit unit;
  final List<Lesson> lessons;
}

class _LessonEntry extends _Entry {
  const _LessonEntry(this.lesson, this.index);
  final Lesson lesson;
  final int index;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.search,
    required this.compact,
  });

  final AppState state;
  final TextEditingController search;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final course = state.currentCourse;

    final courseMenu = state.courses.length > 1
        ? PopupMenuButton<String>(
            tooltip: '切换课程',
            onSelected: state.running || state.scanning
                ? null
                : (cid) => state.loadCourse(cid),
            itemBuilder: (_) => [
              for (final c in state.courses)
                PopupMenuItem(
                  value: c.cid,
                  child: Text(
                    '${c.name} · ${c.percent}%',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
            child: Container(
              height: Tokens.controlHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Tokens.surface,
                borderRadius: BorderRadius.circular(Tokens.radiusControl),
                border: Border.all(color: Tokens.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      course?.name ?? '选择课程',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Caret(color: Tokens.textTertiary, width: 6),
                ],
              ),
            ),
          )
        : null;

    final searchField = SizedBox(
      height: Tokens.controlHeight,
      child: TextField(
        controller: search,
        onChanged: state.setQuery,
        style: const TextStyle(fontSize: 12.5),
        decoration: const InputDecoration(
          hintText: '搜索小节',
          filled: true,
          fillColor: Tokens.surface,
          prefixIcon: Icon(Icons.search, size: 15, color: Tokens.textTertiary),
          prefixIconConstraints: BoxConstraints(minWidth: 30),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),
    );

    final scanButton = ScanButton(
      scanning: state.scanning,
      onPressed: state.running || state.currentCid == null
          ? null
          : () => state.loadCourse(state.currentCid!),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 手机上多门课 + 搜索 + 扫描塞不进一行：课程切换单独一行，
        // 搜索框吃掉剩余宽度，避免右侧留一条空白。
        if (compact && courseMenu != null) ...[
          courseMenu,
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (!compact && courseMenu != null) ...[
              courseMenu,
              const SizedBox(width: 8),
            ],
            if (compact)
              Expanded(child: searchField)
            else
              SizedBox(width: 260, child: searchField),
            const SizedBox(width: 8),
            scanButton,
            if (!compact) const Spacer(),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 28,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _UnitChip(
                label: '全部',
                count: state.candidates.length,
                active: state.selectedUnit == null,
                onTap: () => state.setUnit(null),
              ),
              for (final unit in state.units.where((u) => u.visible))
                _UnitChip(
                  label: unit.label,
                  count: state.lessons
                      .where(
                        (l) =>
                            l.unitIndex == unit.index &&
                            !l.complete &&
                            state.statusOf(l.scoid) != LessonStatus.done,
                      )
                      .length,
                  active: state.selectedUnit == unit.index,
                  onTap: () => state.setUnit(unit.index),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({
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
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? Tokens.textPrimary : Tokens.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active ? Tokens.textPrimary : Tokens.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: active ? Colors.white : Tokens.textSecondary,
                    fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: monoStyle(
                      size: 10,
                      color: active ? Colors.white70 : Tokens.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LessonList extends StatelessWidget {
  const _LessonList({
    required this.state,
    required this.entries,
    required this.compact,
  });

  final AppState state;
  final List<_Entry> entries;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // 扫描进度已经在标题下的横幅里；列表区只保留空态说明，
    // 不再把一条进度卡吊在整片空白正中间。
    if (state.scanning) {
      return const EmptyState(
        icon: Icons.manage_search_rounded,
        title: '正在扫描课程结构',
        body: '单元和小节会在扫描结束后出现在这里。',
      );
    }

    if (state.lessons.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_sync_outlined,
        title: '还没有扫描结果',
        body: '扫描一次课程，就能按单元勾选要跑的小节。',
        actionLabel: '重新扫描',
        onAction: () {
          final cid = state.currentCid;
          if (cid != null) state.loadCourse(cid);
        },
      );
    }

    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: '当前筛选没有匹配的小节',
        body: '换个单元、清空搜索词，或者切回「全部」。',
      );
    }

    return Column(
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Tokens.border)),
          ),
          child: Row(
            children: [
              Text(
                '共 ${entries.whereType<_LessonEntry>().length} 节',
                style: const TextStyle(
                  fontSize: 11,
                  color: Tokens.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                '已选 ${state.selectedCount} 节',
                style: monoStyle(
                  size: 11,
                  color: state.selectedCount > 0
                      ? Tokens.accent
                      : Tokens.textTertiary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            // 手机上列表夹在工具栏与固定操作条之间，留一点底部余量，
            // 滚到底时最后一行不会被贴得死死的（布局本身是分区，不是浮层遮挡）
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final entry = entries[i];
              if (entry is _UnitEntry) {
                return _GroupHeader(
                  state: state,
                  entry: entry,
                  compact: compact,
                );
              }
              final lesson = (entry as _LessonEntry).lesson;
              return _TaskRow(
                state: state,
                lesson: lesson,
                index: entry.index,
                compact: compact,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.state,
    required this.entry,
    required this.compact,
  });

  final AppState state;
  final _UnitEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final picked = entry.lessons
        .where((l) => state.selectedScoids.contains(l.scoid))
        .length;
    final pending = entry.lessons.where((l) => !l.complete).length;
    // 手机上点击区要 44，组头也得跟着长高；否则选择框会溢出，
    // 而且和下面 44 点击区的行错开 5px，两个勾选框的竖列就不齐了。
    final double tapSize = compact ? Tokens.tapMin : 34;

    return Container(
      height: compact ? Tokens.tapMin : 36,
      padding: const EdgeInsets.only(left: 6, right: 10),
      color: Tokens.surfaceAlt,
      child: Row(
        children: [
          AppCheckbox(
            value: state.unitSelection(entry.unit.index),
            tapSize: tapSize,
            onChanged: state.running
                ? null
                : (_) => state.toggleUnit(entry.unit.index),
            label: '全选 ${entry.unit.label}',
          ),
          Expanded(
            child: Text(
              entry.unit.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${entry.lessons.length} 节 · 待处理 $pending',
            style: const TextStyle(fontSize: 10.5, color: Tokens.textTertiary),
          ),
          if (picked > 0) ...[
            const SizedBox(width: 10),
            Text(
              '已选 $picked',
              style: monoStyle(size: 10.5, color: Tokens.accent),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.state,
    required this.lesson,
    required this.index,
    required this.compact,
  });

  final AppState state;
  final Lesson lesson;
  final int index;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = state.statusOf(lesson.scoid);
    final checked = state.selectedScoids.contains(lesson.scoid);
    final done = status == LessonStatus.done;

    return Material(
      color: checked
          ? Tokens.accentSoft.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        onTap: state.running ? null : () => state.toggleSelected(lesson.scoid),
        hoverColor: Tokens.mutedSoft.withValues(alpha: 0.5),
        child: Container(
          height: compact ? 62 : 52,
          padding: const EdgeInsets.only(left: 6, right: 10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Tokens.border, width: 0.6),
            ),
          ),
          child: Row(
            children: [
              AppCheckbox(
                value: checked,
                tapSize: compact ? Tokens.tapMin : 34,
                label: '选择 ${shortLocation(lesson)}',
                onChanged: state.running
                    ? null
                    : (v) => state.setSelected(lesson.scoid, v),
              ),
              StatusDot(status, size: 7),
              const SizedBox(width: 8),
              if (!compact) ...[
                SizedBox(
                  width: 26,
                  child: Text(
                    '$index',
                    style: monoStyle(size: 10.5, color: Tokens.textTertiary),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: compact
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shortLocation(lesson),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.3,
                              color: done
                                  ? Tokens.textTertiary
                                  : Tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              status.label,
                              if (lesson.learnTime.isNotEmpty &&
                                  lesson.learnTime != '00:00:00')
                                lesson.learnTime,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Tokens.textTertiary,
                              height: 1.2,
                            ),
                          ),
                        ],
                      )
                    : Tooltip(
                        message: displayLocation(lesson),
                        child: Text(
                          shortLocation(lesson),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: done
                                ? Tokens.textTertiary
                                : Tokens.textPrimary,
                          ),
                        ),
                      ),
              ),
              if (!compact) ...[
                const SizedBox(width: 10),
                if (lesson.learnTime.isNotEmpty &&
                    lesson.learnTime != '00:00:00')
                  Text(
                    lesson.learnTime,
                    style: monoStyle(size: 10.5, color: Tokens.textTertiary),
                  ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: StatusPill(status),
                  ),
                ),
                SizedBox(
                  width: 76,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: state.running
                          ? null
                          : () => state.startRun(only: lesson),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        textStyle: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'Segoe UI',
                          fontFamilyFallback: Tokens.fontFallback,
                        ),
                      ),
                      child: Text(done ? '重跑本节' : '只跑本节'),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: state.running
                      ? null
                      : () => state.startRun(only: lesson),
                  tooltip: done ? '重跑本节' : '只跑本节',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.play_circle_outline,
                    size: 20,
                    color: Tokens.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RunPanel extends StatefulWidget {
  const _RunPanel({
    required this.state,
    required this.compact,
    this.embedded = false,
  });

  final AppState state;
  final bool compact;
  final bool embedded;

  @override
  State<_RunPanel> createState() => _RunPanelState();
}

class _RunPanelState extends State<_RunPanel> {
  late RunSettings _draft = widget.state.settings;
  late RunSettings _saved = widget.state.settings;

  @override
  void didUpdateWidget(_RunPanel old) {
    super.didUpdateWidget(old);
    // 外部（比如手机端的参数抽屉）保存过参数时，把草稿同步过来。
    // 只比较已保存值，拖动过程中的草稿不会被回滚。
    if (widget.state.settings != _saved) {
      _saved = widget.state.settings;
      if (!widget.state.running) _draft = _saved;
    }
  }

  void _commit(RunSettings next) {
    setState(() => _draft = next);
    _saved = next;
    widget.state.saveSettings(next);
  }

  int _estimate(int count) {
    final avgWait = (_draft.waitMin + _draft.waitMax) ~/ 2;
    final gap = (_draft.intervalMin + _draft.intervalMax) ~/ 2;
    return count * (avgWait + gap);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final locked = state.running;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              '运行参数',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (locked)
              const Text(
                '运行中只读',
                style: TextStyle(fontSize: 10.5, color: Tokens.warning),
              )
            else
              Text(
                '立即生效',
                style: TextStyle(fontSize: 10.5, color: Tokens.textTertiary),
              ),
          ],
        ),
        const SizedBox(height: 10),
        RangeField(
          label: '每节等待',
          min: 30,
          max: 900,
          start: _draft.waitMin,
          end: _draft.waitMax,
          suffix: ' 秒',
          enabled: !locked,
          step: 2, // 只允许偶数：等待时长按 2 秒一档
          onChanged: (a, b) =>
              setState(() => _draft = _draft.copyWith(waitMin: a, waitMax: b)),
          onChangeEnd: (a, b) =>
              _commit(_draft.copyWith(waitMin: a, waitMax: b)),
        ),
        const SizedBox(height: 4),
        RangeField(
          label: '目标正确率',
          min: 0,
          max: 100,
          start: _draft.rateMin,
          end: _draft.rateMax,
          suffix: '%',
          enabled: !locked,
          onChanged: (a, b) =>
              setState(() => _draft = _draft.copyWith(rateMin: a, rateMax: b)),
          onChangeEnd: (a, b) =>
              _commit(_draft.copyWith(rateMin: a, rateMax: b)),
        ),
        const SizedBox(height: 4),
        RangeField(
          label: '节间间隔',
          min: 0,
          max: 60,
          start: _draft.intervalMin,
          end: _draft.intervalMax,
          suffix: ' 秒',
          enabled: !locked,
          onChanged: (a, b) => setState(
            () => _draft = _draft.copyWith(intervalMin: a, intervalMax: b),
          ),
          onChangeEnd: (a, b) =>
              _commit(_draft.copyWith(intervalMin: a, intervalMax: b)),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('跳过口语小节', style: TextStyle(fontSize: 12)),
                  SizedBox(height: 1),
                  Text(
                    '按小节名识别，重新扫描后生效',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Tokens.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _draft.skipOralLesson,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: locked
                  ? null
                  : (v) => _commit(_draft.copyWith(skipOralLesson: v)),
            ),
          ],
        ),
        const Divider(height: 20),
        Row(
          children: [
            Text(
              '已选 ${state.selectedCount} 节',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              humanDuration(_estimate(state.selectedCount)),
              style: monoStyle(size: 11.5, color: Tokens.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          '预计总耗时',
          style: TextStyle(fontSize: 10.5, color: Tokens.textTertiary),
        ),
        const SizedBox(height: 12),
        if (state.running)
          SizedBox(
            height: Tokens.tapMin,
            child: OutlinedButton.icon(
              onPressed: state.stopRun,
              icon: const Icon(
                Icons.stop_rounded,
                size: 16,
                color: Tokens.danger,
              ),
              label: const Text('停止运行', style: TextStyle(color: Tokens.danger)),
            ),
          )
        else
          SizedBox(
            height: Tokens.tapMin,
            child: FilledButton.icon(
              // 主按钮固定 44 高；把纵向内边距从全局的 14 收到 10，
              // 否则 14+18px 图标+14 会超过 44，文字在 150% 缩放下容易被压扁。
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Tokens.tapMin),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: state.selectedCount == 0 ? null : state.startRun,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                state.selectedCount == 0
                    ? '先勾选小节'
                    : '开始运行 ${state.selectedCount} 节',
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          state.selectedCount == 0 ? '勾选左侧小节后即可开始。' : '运行中可随时停止，当前节不会提交。',
          style: const TextStyle(
            fontSize: 10.5,
            color: Tokens.textTertiary,
            height: 1.5,
          ),
        ),
      ],
    );

    if (widget.embedded) return content;

    return PanelCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: content,
    );
  }
}

class _MobileBar extends StatelessWidget {
  const _MobileBar({required this.state, required this.onParams});

  final AppState state;
  final VoidCallback onParams;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Tokens.surface,
        border: Border(top: BorderSide(color: Tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '已选 ${state.selectedCount} 节 · ${humanDuration(state.remainingEstimate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: onParams,
                      child: Text(
                        '等待 ${state.settings.waitMin}–${state.settings.waitMax} 秒 · '
                        '正确率 ${state.settings.rateMin}–${state.settings.rateMax}% · 调整',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Tokens.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: Tokens.tapMin,
                child: state.running
                    ? OutlinedButton(
                        onPressed: state.stopRun,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Tokens.danger,
                          side: const BorderSide(color: Tokens.danger),
                        ),
                        child: const Text('停止'),
                      )
                    : FilledButton(
                        onPressed: state.selectedCount == 0
                            ? null
                            : state.startRun,
                        child: const Text('开始运行'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
