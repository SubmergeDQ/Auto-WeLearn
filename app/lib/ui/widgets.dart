import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../theme.dart';

/// 完成时间的相对显示：1 分钟内「刚刚」，1 小时内「n 分钟前」，
/// 24 小时内「n 小时前」，超过一天改为具体日期时间（跨年带年份）。
String relativeTimeText(DateTime? time, {DateTime? now}) {
  if (time == null) return '—';
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';

  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  if (time.year == current.year) {
    return '${time.month} 月 ${time.day} 日 $hh:$mm';
  }
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day $hh:$mm';
}

/// 状态点：颜色 + 形状双编码，不只靠颜色
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key, this.size = 8});
  final LessonStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (color, filled) = switch (status) {
      LessonStatus.pending => (Tokens.borderStrong, false),
      LessonStatus.running => (Tokens.accent, true),
      LessonStatus.done => (Tokens.success, true),
      LessonStatus.partial => (Tokens.warning, true),
      LessonStatus.failed => (Tokens.danger, true),
      LessonStatus.skipped => (Tokens.muted, false),
      LessonStatus.interrupted => (Tokens.muted, false),
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }
}

/// 状态胶囊：浅底 + 状态色文字
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final LessonStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status) {
      LessonStatus.pending => (Tokens.textTertiary, Tokens.mutedSoft),
      LessonStatus.running => (Tokens.accent, Tokens.accentSoft),
      LessonStatus.done => (Tokens.success, Tokens.successSoft),
      LessonStatus.partial => (Tokens.warning, Tokens.warningSoft),
      LessonStatus.failed => (Tokens.danger, Tokens.dangerSoft),
      LessonStatus.skipped => (Tokens.muted, Tokens.mutedSoft),
      LessonStatus.interrupted => (Tokens.muted, Tokens.mutedSoft),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 分组小标题
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.gap8),
      child: Row(
        children: [
          Text(
            text,
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
    );
  }
}

/// 细进度条
class ThinBar extends StatelessWidget {
  const ThinBar({
    super.key,
    required this.value,
    this.color = Tokens.accent,
    this.height = 4,
  });
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: Tokens.mutedSoft,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// 小组件：向下的小三角。
///
/// 不用 `Icons.expand_more`：那个字形在部分构建里会被图标字体子集漏掉，
/// 结果是一个 15px 的空白占位——胶囊看起来仍然是纯状态标签，用户根本不知道能点。
/// 用 CustomPaint 画三角形不依赖任何字体。
class Caret extends StatelessWidget {
  const Caret({super.key, required this.color, this.width = 7});
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * 0.62),
      painter: _CaretPainter(color),
    );
  }
}

class _CaretPainter extends CustomPainter {
  const _CaretPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter oldDelegate) => oldDelegate.color != color;
}

/// 队列行
class LessonTile extends StatelessWidget {
  const LessonTile({
    super.key,
    required this.index,
    required this.lesson,
    required this.status,
    required this.selected,
    required this.onTap,
    this.height = 56,
    this.maxLines = 1,
    this.showChevron = false,
  });

  final int index;
  final Lesson lesson;
  final LessonStatus status;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final int maxLines;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final isDone = status == LessonStatus.done;

    return Material(
      color: selected
          ? Tokens.accentSoft.withValues(alpha: 0.55)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Tokens.mutedSoft.withValues(alpha: 0.6),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? Tokens.accent : Colors.transparent,
                width: 2,
              ),
              bottom: const BorderSide(color: Tokens.border, width: 0.6),
            ),
          ),
          child: Row(
            children: [
              StatusDot(status),
              const SizedBox(width: 10),
              SizedBox(
                width: 30,
                child: Text(
                  '$index',
                  style: monoStyle(size: 11, color: Tokens.textTertiary),
                ),
              ),
              Expanded(
                child: Text(
                  lesson.location,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDone ? Tokens.textTertiary : Tokens.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (lesson.learnTime.isNotEmpty && lesson.learnTime != '00:00:00')
                Text(
                  lesson.learnTime,
                  style: monoStyle(size: 11, color: Tokens.textTertiary),
                ),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: StatusPill(status),
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Tokens.borderStrong,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 账号头像：优先显示从 WeLearn 拉回来的实时头像，
/// 没有拿到（未登录 / 解析失败 / 下载失败）才退回课程名首字或人形图标。
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.bytes,
    required this.initials,
    this.size = 32,
    this.loggedIn = true,
    this.loading = false,
  });

  final Uint8List? bytes;
  final String initials;
  final double size;
  final bool loggedIn;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: loggedIn ? Tokens.accentSoft : Tokens.mutedSoft,
        border: Border.all(
          color: image == null ? Colors.transparent : Tokens.border,
          width: 0.8,
        ),
      ),
      child: ClipOval(
        child: image != null
            ? Image.memory(
                image,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : (loading && loggedIn
                  ? Center(
                      child: SizedBox(
                        width: size * 0.42,
                        height: size * 0.42,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Tokens.accent,
                        ),
                      ),
                    )
                  : _fallback()),
      ),
    );
  }

  Widget _fallback() => Center(
    child: loggedIn
        ? Text(
            initials.isEmpty ? 'W' : initials,
            style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w600,
              color: Tokens.accent,
            ),
          )
        : Icon(
            Icons.person_outline,
            size: size * 0.5,
            color: Tokens.textTertiary,
          ),
  );
}

/// 选择框：和圆角、强调色、180ms 状态过渡保持同一套语言。
///
/// 替换了原生 compact Checkbox —— 那个方形小框在 52/62 高的行里显得又小又生硬，
/// 三态时只有一个短横，几乎看不出是"部分选中"。
/// 选中后有轻微的强调色投影和缩放回弹，勾选动作更容易被看见，但不会抢状态点的戏。
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 20,
    this.tapSize = 34,
    this.label,
  });

  /// true / false / null（三态的部分选中）
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final double size;
  final double tapSize;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final mixed = value == null;
    final checked = value == true;
    final active = checked || mixed;
    final fill = active
        ? (enabled ? Tokens.accent : Tokens.borderStrong)
        : Tokens.surface;
    final borderColor = active
        ? fill
        : (enabled ? Tokens.borderStrong : Tokens.border);

    Widget mark;
    if (mixed) {
      mark = Container(
        key: const ValueKey('mixed'),
        width: size * 0.55,
        height: 2.2,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    } else if (checked) {
      mark = SizedBox(
        key: const ValueKey('checked'),
        width: size * 0.8,
        height: size * 0.8,
        child: CustomPaint(painter: _CheckMarkPainter(color: Colors.white)),
      );
    } else {
      mark = const SizedBox(key: ValueKey('empty'));
    }

    return Semantics(
      label: label,
      checked: checked,
      mixed: mixed,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? () => onChanged!(value != true) : null,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        hoverColor: Tokens.accentSoft,
        child: SizedBox(
          width: tapSize,
          height: tapSize,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: fill,
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(size * 0.3),
                boxShadow: active && enabled
                    ? [
                        BoxShadow(
                          color: Tokens.accent.withValues(alpha: 0.16),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: mark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 手绘勾：圆头两段线，比图标字体更贴合 20px 的方框，也不会被字体子集裁掉。
class _CheckMarkPainter extends CustomPainter {
  const _CheckMarkPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.13
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final path = Path()
      ..moveTo(size.width * 0.14, size.height * 0.52)
      ..lineTo(size.width * 0.4, size.height * 0.76)
      ..lineTo(size.width * 0.86, size.height * 0.24);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 日志行
class LogLine extends StatelessWidget {
  const LogLine({
    super.key,
    required this.time,
    required this.level,
    required this.message,
  });
  final String time;
  final String level;
  final String message;

  @override
  Widget build(BuildContext context) {
    final (color, tag) = switch (level) {
      'error' => (Tokens.danger, 'ERR'),
      'warn' => (Tokens.warning, 'WRN'),
      'done' => (Tokens.success, 'OK '),
      'beat' => (Tokens.accent, 'HB '),
      _ => (Tokens.textTertiary, 'INF'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        // 时间、级别、正文三种字号不同，按基线对齐才不会上下错开
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              time,
              style: monoStyle(size: 10.5, color: Tokens.textTertiary),
            ),
          ),
          SizedBox(
            width: 26,
            child: Text(
              tag,
              style: monoStyle(
                size: 10.5,
                color: color,
                weight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: level == 'error' ? Tokens.danger : Tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
