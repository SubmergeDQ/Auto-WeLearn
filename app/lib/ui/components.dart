import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 白色卡片：面板、任务、设置三页共用的表面。
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Tokens.surface,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.all(color: Tokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 页面标题行：标题、说明、右侧动作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: compact ? 18 : 20,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: -0.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 12,
              color: Tokens.textTertiary,
              height: 1.4,
            ),
          ),
        ],
      ],
    );

    if (actions.isEmpty) return heading;

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: heading),
        const SizedBox(width: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: actions,
        ),
      ],
    );
  }
}

/// 指标卡：标签 + 主数值 + 补充说明。
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
    this.accent,
    this.icon,
  });

  final String label;
  final String value;
  final String? unit;
  final String? hint;
  final Color? accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Tokens.textPrimary;
    return PanelCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      // 四张卡统一最小高度：hint 有无不会让底边参差。
      // 不用 Row 的 stretch —— 面板在滚动视图里拿到的是无限高度约束。
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: color.withValues(alpha: 0.75)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Tokens.textTertiary,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      size: 22,
                      weight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 3),
                  Text(
                    unit!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Tokens.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(
                hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Tokens.textTertiary,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 环形进度：中间放主数值，比纯数字更容易一眼看出比例。
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 96,
    this.stroke = 7,
    this.color = Tokens.accent,
    this.child,
  });

  final double value;
  final double size;
  final double stroke;
  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => CustomPaint(
          painter: _RingPainter(animated, stroke, color),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value, this.stroke, this.color);
  final double value;
  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Tokens.mutedSoft
      ..strokeCap = StrokeCap.round;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, track);
    if (value > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.stroke != stroke;
}

/// 空态：图标 + 标题 + 说明 + 一个明确的下一步。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Tokens.mutedSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: Tokens.textTertiary),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Tokens.textTertiary,
                  height: 1.6,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置项：左侧标题与说明，右侧控件。
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.description,
    this.trailing,
    this.bottom,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            // 顶部对齐：右侧如果是「桌面端可用」这类纯文字，会和标题同一基线；
            // 居中会把文字落到第二行说明上，看起来像飘在描述里。
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Tokens.textTertiary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                // 右侧控件统一占一个 32 高的槽位：按钮、文字、开关不再
                // 因为各自默认高度不同而把整行拉得参差不齐。
                SizedBox(
                  height: Tokens.controlHeight,
                  child: Align(alignment: Alignment.topRight, child: trailing!),
                ),
              ],
            ],
          ),
          if (bottom != null) ...[const SizedBox(height: 10), bottom!],
        ],
      ),
    );
  }
}

/// 分组卡片：标题 + 若干设置项。
class SettingGroup extends StatelessWidget {
  const SettingGroup({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 与卡片内 16 的左内边距一致，分组标题才不会比下面的文字长出 14px
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: Tokens.textTertiary,
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
        PanelCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          // Column 默认 crossAxisAlignment.center，会让分隔线短一截、
          // 按钮组整块居中，看起来和内容左边缘完全对不上。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 秒数 → `1 小时 12 分` / `12 分 30 秒`
String humanDuration(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return m > 0 ? '$h 小时 $m 分' : '$h 小时';
  if (m > 0) return s > 0 ? '$m 分 $s 秒' : '$m 分';
  return '$s 秒';
}

/// 秒数 → `06:12`
String clockText(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final m = total ~/ 60;
  final s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 把滑杆数值吸附到 [step] 的整数倍。
///
/// 等待时长的滑杆按 10 秒一档，避免滑到 313 秒这种没有意义的数字。
int snapToStep(int value, {required int min, required int max, int step = 1}) {
  final clamped = value.clamp(min, max);
  if (step <= 1) return clamped;
  final snapped = ((clamped - min) / step).round() * step + min;
  return snapped.clamp(min, max);
}

/// 紧凑开关：默认 Material Switch 在运行参数行里视觉偏大，
/// 这里固定一个更小的盒子并等比缩放，同时保留 enabled / disabled 样式。
class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.tooltip,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final body = SizedBox(
      width: 48,
      height: 30,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
    return tooltip == null
        ? body
        : Tooltip(message: tooltip!, child: body);
  }
}

/// 区间滑杆：标签、当前值、双端滑块。
///
/// 放在任务页的运行参数里——这些值以前藏在弹窗，改一次要点开两层。
/// 拖动期间用本地连续值渲染，松手后才吸附到 [step]：
/// 否则受控回写会把滑块拽回档位，快速滑动时看起来"不跟手"。
class RangeField extends StatefulWidget {
  const RangeField({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.start,
    required this.end,
    required this.onChanged,
    this.onChangeEnd,
    this.suffix = '',
    this.enabled = true,
    this.divisions,
    this.step = 1,
  });

  final String label;
  final double min;
  final double max;
  final int start;
  final int end;
  final void Function(int a, int b) onChanged;

  /// 松手时才触发：拖动过程只更新本地草稿，避免每一像素都写盘。
  final void Function(int a, int b)? onChangeEnd;
  final String suffix;
  final bool enabled;
  final int? divisions;

  /// 取值步长：滑杆只能落在 `min + k * step` 上。等待时长用 10 秒一档。
  final int step;

  @override
  State<RangeField> createState() => _RangeFieldState();
}

enum _RangeDragMode { start, end, both }

class _RangeFieldState extends State<RangeField> {
  /// 拖动中的原始值；为 null 时显示外部传入的吸附值
  RangeValues? _drag;

  /// 原生 RangeSlider 在两个 thumb 靠得太近时无法分别命中，
  /// 这里自己接管手势：接近时按距离选端点，完全重合时整体平移。
  _RangeDragMode? _mode;
  double _dragStartX = 0;
  RangeValues _dragStartValues = const RangeValues(0, 0);

  /// 与 Slider 轨道左右内边距保持一致（thumb 半径 + overlay 的一半）
  static const double _trackInset = 14;

  (int, int) _snap(RangeValues v) => (
    snapToStep(
      v.start.round(),
      min: widget.min.round(),
      max: widget.max.round(),
      step: widget.step,
    ),
    snapToStep(
      v.end.round(),
      min: widget.min.round(),
      max: widget.max.round(),
      step: widget.step,
    ),
  );

  RangeValues _resting() {
    final (a, b) = _snap(RangeValues(
      widget.start.toDouble(),
      widget.end.toDouble(),
    ));
    final lower = a.toDouble().clamp(widget.min, widget.max);
    final upper = b.toDouble().clamp(widget.min, widget.max);
    return lower <= upper ? RangeValues(lower, upper) : RangeValues(upper, lower);
  }

  /// 按下的位置与值：原生 RangeSlider 在 onDragStart 时才开始选端点，
  /// 此时手指已经越过 18px 判定阈值，很容易选错相邻端点；这里按下就锁定。
  RangeValues _downValues = const RangeValues(0, 0);

  /// 拖动手势：离哪个端点近就拖哪个；两端完全重合时整体平移。
  void _handlePanDown(
    DragDownDetails details,
    RangeValues values,
    double startX,
    double endX,
  ) {
    final x = details.localPosition.dx;
    final same = (values.end - values.start).abs() < 1e-9;
    _mode = same || (endX - startX).abs() < 3
        ? _RangeDragMode.both
        : ((x - startX).abs() <= (x - endX).abs()
            ? _RangeDragMode.start
            : _RangeDragMode.end);
    _downValues = values;
  }

  void _beginDrag(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragStartValues = _downValues;
    setState(() => _drag = _downValues);
  }

  void _updateDrag(DragUpdateDetails details, double usable) {
    final mode = _mode;
    if (mode == null) return;
    final span = widget.max - widget.min;
    final delta = (details.localPosition.dx - _dragStartX) / usable * span;
    var a = _dragStartValues.start;
    var b = _dragStartValues.end;

    switch (mode) {
      case _RangeDragMode.start:
        a = (a + delta).clamp(widget.min, b);
      case _RangeDragMode.end:
        b = (b + delta).clamp(a, widget.max);
      case _RangeDragMode.both:
        // 重合时整体平移，区间宽度保持不变
        final width = b - a;
        a = (a + delta).clamp(
          widget.min,
          math.max(widget.min, widget.max - width),
        );
        b = a + width;
    }

    setState(() => _drag = RangeValues(a, b));
    final (sa, sb) = _snap(RangeValues(a, b));
    widget.onChanged(sa, sb);
  }

  void _endDrag() {
    if (_mode == null) return;
    final values = _drag ?? _resting();
    final (a, b) = _snap(values);
    setState(() {
      _drag = null;
      _mode = null;
    });
    widget.onChangeEnd?.call(a, b);
  }

  void _tapTrack(
    double x,
    RangeValues values,
    double startX,
    double endX,
    double Function(double) valueFor,
  ) {
    final target = valueFor(x).clamp(widget.min, widget.max);
    final same = (values.end - values.start).abs() < 1e-9;
    final RangeValues next;
    if (same) {
      // 重合状态点一下：把整个区间移过去
      next = RangeValues(target, target);
    } else {
      final nearStart = (x - startX).abs() <= (x - endX).abs();
      next = nearStart
          ? RangeValues(target.clamp(widget.min, values.end), values.end)
          : RangeValues(values.start, target.clamp(values.start, widget.max));
    }
    final (a, b) = _snap(next);
    setState(() {
      _drag = null;
      _mode = null;
    });
    widget.onChanged(a, b);
    widget.onChangeEnd?.call(a, b);
  }

  /// 精确输入：两个 thumb 重合时（例如 100–100）无法再用滑块分别选中，
  /// 这里直接给出输入框，保证任何区间（含两端相等）都能设置。
  Future<void> _editValues() async {
    if (!widget.enabled) return;
    final (currentStart, currentEnd) = _snap(_drag ?? _resting());
    final result = await showDialog<RangeValues>(
      context: context,
      builder: (_) => _RangeValueDialog(
        label: widget.label,
        min: widget.min.round(),
        max: widget.max.round(),
        step: widget.step,
        suffix: widget.suffix,
        start: currentStart,
        end: currentEnd,
      ),
    );
    if (result == null || !mounted) return;

    final a = result.start.round();
    final b = result.end.round();
    setState(() => _drag = null);
    widget.onChanged(a, b);
    widget.onChangeEnd?.call(a, b);
  }

  @override
  Widget build(BuildContext context) {
    final values = _drag ?? _resting();
    final enabled = widget.enabled;
    // 拖动中显示吸附后的整数，滑块本身保持连续
    final (shownStart, shownEnd) = _snap(values);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Tokens.textSecondary,
                ),
              ),
            ),
            Tooltip(
              message: '点击精确输入',
              child: InkWell(
                onTap: enabled ? _editValues : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  child: Text(
                    '$shownStart – $shownEnd${widget.suffix}',
                    style: monoStyle(
                      size: 11.5,
                      color: enabled
                          ? Tokens.textPrimary
                          : Tokens.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            rangeThumbShape: const RoundRangeSliderThumbShape(
              enabledThumbRadius: 7,
            ),
            activeTrackColor: enabled ? Tokens.accent : Tokens.borderStrong,
            inactiveTrackColor: Tokens.mutedSoft,
            thumbColor: enabled ? Tokens.accent : Tokens.borderStrong,
            overlayColor: Tokens.accent.withValues(alpha: 0.10),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final span = widget.max - widget.min;
              final usable = math.max(1.0, width - 2 * _trackInset);
              double xFor(double v) =>
                  _trackInset + (v - widget.min) / span * usable;
              double valueFor(double x) =>
                  widget.min + (x - _trackInset) / usable * span;
              final startX = xFor(values.start);
              final endX = xFor(values.end);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: enabled
                    ? (d) => _tapTrack(
                        d.localPosition.dx,
                        values,
                        startX,
                        endX,
                        valueFor,
                      )
                    : null,
                onPanDown: enabled
                    ? (d) => _handlePanDown(d, values, startX, endX)
                    : null,
                onPanStart: enabled ? _beginDrag : null,
                onPanUpdate: enabled ? (d) => _updateDrag(d, usable) : null,
                onPanEnd: enabled ? (_) => _endDrag() : null,
                onPanCancel: enabled ? _endDrag : null,
                // 原生 RangeSlider 只负责绘制；命中全部交给上面的手势层，
                // 这样两个 thumb 靠得再近也能按需选中，重合时还能整体拖动。
                child: IgnorePointer(
                  child: RangeSlider(
                    values: values,
                    min: widget.min,
                    max: widget.max,
                    divisions: _drag == null
                        ? (widget.divisions ??
                              ((widget.max - widget.min) / widget.step).round())
                        : null,
                    onChanged: enabled ? (_) {} : null,
                    onChangeEnd: null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 区间滑杆的精确输入弹窗。
///
/// 两个 thumb 重合后（例如 100–100）滑块上很难再分别选中，
/// 这里用输入框保证包括「两端相等」在内的任何区间都能设置。
class _RangeValueDialog extends StatefulWidget {
  const _RangeValueDialog({
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    required this.suffix,
    required this.start,
    required this.end,
  });

  final String label;
  final int min;
  final int max;
  final int step;
  final String suffix;
  final int start;
  final int end;

  @override
  State<_RangeValueDialog> createState() => _RangeValueDialogState();
}

class _RangeValueDialogState extends State<_RangeValueDialog> {
  late final TextEditingController _startController = TextEditingController(
    text: '${widget.start}',
  );
  late final TextEditingController _endController = TextEditingController(
    text: '${widget.end}',
  );
  String? _error;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _submit() {
    final a = int.tryParse(_startController.text.trim());
    final b = int.tryParse(_endController.text.trim());
    if (a == null || b == null) {
      setState(() => _error = '请输入整数');
      return;
    }
    if (a < widget.min || a > widget.max || b < widget.min || b > widget.max) {
      setState(() => _error = '取值范围 ${widget.min} – ${widget.max}');
      return;
    }
    if (a > b) {
      setState(() => _error = '下限不能大于上限');
      return;
    }
    final snappedA = snapToStep(
      a,
      min: widget.min,
      max: widget.max,
      step: widget.step,
    );
    final snappedB = snapToStep(
      b,
      min: widget.min,
      max: widget.max,
      step: widget.step,
    );
    Navigator.pop(context, RangeValues(snappedA.toDouble(), snappedB.toDouble()));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.label}精确设置',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '范围 ${widget.min} – ${widget.max}${widget.suffix}，两端可以相等。',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Tokens.textTertiary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _startController,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '下限',
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _endController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '上限',
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 11, color: Tokens.danger),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(onPressed: _submit, child: const Text('确定')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 扫描中的显式反馈：转圈 + 阶段文字 + 实时已用时 + 不确定进度条。
///
/// 扫描要逐单元请求平台，慢的时候界面上完全没有动静，用户会以为没点上
/// 而反复点「扫描」。这一条横幅在面板、任务、设置三页共用；已用时每秒
/// 刷新一次，即使平台卡在同一个阶段，也能看出程序还在跑。
class ScanIndicator extends StatefulWidget {
  const ScanIndicator({super.key, required this.stage, this.compact = false});

  final String stage;
  final bool compact;

  @override
  State<ScanIndicator> createState() => _ScanIndicatorState();
}

class _ScanIndicatorState extends State<ScanIndicator> {
  late final DateTime _startedAt = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int get _elapsedSeconds => DateTime.now().difference(_startedAt).inSeconds;

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage.isEmpty ? '正在读取课程信息…' : widget.stage;

    return Semantics(
      liveRegion: true,
      label: '正在扫描课程结构，$stage',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 12 : 14,
          // 标题 + 阶段文字和右侧计时上下留 12，互不挤压
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: Tokens.accentSoft,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          border: Border.all(color: Tokens.accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Tokens.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '正在扫描课程结构…',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Tokens.accent,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          stage,
                          key: ValueKey(stage),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Tokens.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '已用时 ${clockText(_elapsedSeconds)}',
                      style: monoStyle(size: 10.5, color: Tokens.accent),
                    ),
                    // 手机宽度不够，右侧只留实时计时；按钮已显示「扫描中…」，
                    // 再放一行「请勿重复扫描」会把阶段文字挤到前面。
                    if (!widget.compact) ...[
                      const SizedBox(height: 2),
                      const Text(
                        '请勿重复扫描',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Tokens.textTertiary,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Tokens.accent.withValues(alpha: 0.14),
                valueColor: const AlwaysStoppedAnimation(Tokens.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 所有「扫描 / 重新扫描」入口共用一个按钮：扫描中禁用并显示转圈，
/// 避免用户以为没点上而重复触发（AppState.loadCourse 里还有一层兜底）。
class ScanButton extends StatelessWidget {
  const ScanButton({
    super.key,
    required this.scanning,
    required this.onPressed,
    this.label = '扫描',
  });

  final bool scanning;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: toolbarOutlined(),
      onPressed: scanning ? null : onPressed,
      icon: scanning
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Tokens.accent,
              ),
            )
          : const Icon(Icons.refresh_rounded, size: 15),
      label: Text(scanning ? '扫描中…' : label),
    );
  }
}
