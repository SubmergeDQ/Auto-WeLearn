import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
import 'app_scope.dart';

/// 登录入口。桌面用对话框，手机用底部抽屉。
///
/// 手机上没有开发者工具，所以先给「从剪贴板读取」；读到的 Cookie **不回显**，
/// 只显示识别到的项数与前几个名字（截图不会泄露凭据）。
Future<void> showLoginDialog(BuildContext context) async {
  final state = AppScope.of(context);
  final compact = MediaQuery.sizeOf(context).width < 600;
  final controller = TextEditingController();
  var showRaw = !compact;
  String? summary;

  Widget body(StateSetter setLocal) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          compact
              ? '先在手机浏览器登录 welearn.sflep.com，复制 Cookie，再点下面的按钮读取。'
              : '在浏览器登录 welearn.sflep.com，从开发者工具复制 Cookie，粘到下面。',
          style: const TextStyle(fontSize: 12, color: Tokens.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 12),
        if (!showRaw) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                final text = data?.text?.trim() ?? '';
                if (text.isEmpty) {
                  setLocal(() => summary = '剪贴板是空的，先复制 Cookie 再试');
                  return;
                }
                final names = _cookieNames(text);
                controller.text = text;
                setLocal(() {
                  summary = names.isEmpty
                      ? '没识别到 Cookie（需要 a=1; b=2 或 EditThisCookie 导出的 JSON）'
                      : '已读取 ${names.length} 项 · ${names.take(3).join('、')}${names.length > 3 ? '…' : ''}';
                });
              },
              icon: const Icon(Icons.content_paste_rounded, size: 17),
              label: const Text('从剪贴板读取'),
            ),
          ),
          if (summary != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                summary!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: summary!.startsWith('已读取') ? Tokens.success : Tokens.warning,
                  height: 1.4,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setLocal(() => showRaw = true),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
              child: const Text('手动粘贴', style: TextStyle(fontSize: 12)),
            ),
          ),
        ] else ...[
          TextField(
            controller: controller,
            maxLines: compact ? 3 : 5,
            style: const TextStyle(fontSize: 12, height: 1.4),
            decoration: const InputDecoration(
              hintText: 'acw_tc=...; area=dbC; .AspNet.Cookies=...',
              hintStyle: TextStyle(fontSize: 11.5, color: Tokens.textTertiary),
            ),
          ),
          if (compact)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setLocal(() => showRaw = false),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                child: const Text('改用剪贴板读取', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
        if (state.lastError != null) ...[
          const SizedBox(height: 8),
          Text(state.lastError!, style: const TextStyle(fontSize: 11.5, color: Tokens.danger, height: 1.4)),
        ],
        const SizedBox(height: 6),
        const Text(
          '账号密码登录暂不支持（平台使用 PKCE 流程，改版风险高）。',
          style: TextStyle(fontSize: 11, color: Tokens.textTertiary, height: 1.4),
        ),
      ],
    );
  }

  Future<void> submit(BuildContext dialogContext) async {
    final ok = await state.login(controller.text);
    if (!dialogContext.mounted) return;
    if (ok) Navigator.pop(dialogContext);
  }

  if (compact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.radiusCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SheetHandle(),
                  const SizedBox(height: 8),
                  const Text('登录 WE Learn',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  body(setLocal),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: Tokens.tapMin,
                    child: FilledButton(
                      onPressed: state.busy ? null : () => submit(sheetContext),
                      child: Text(state.busy ? '连接中…' : '登录'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        backgroundColor: Tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusCard)),
        title: const Text('登录 WE Learn', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: SizedBox(width: 460, child: body(setLocal)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(
            onPressed: state.busy ? null : () => submit(dialogContext),
            child: Text(state.busy ? '连接中…' : '登录'),
          ),
        ],
      ),
    ),
  );
}

List<String> _cookieNames(String raw) {
  try {
    return parseCookieInput(raw).map((e) => e.key).toList();
  } catch (_) {
    return const [];
  }
}

/// 退出登录前的确认。Cookie 需要手动重新粘贴，误点一次成本不低。
Future<bool> confirmLogout(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Tokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusCard)),
      title: const Text('退出登录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      content: const SizedBox(
        width: 360,
        child: Text(
          '退出后会清除本机保存的 Cookie 与当前课程数据，下次需要重新粘贴 Cookie 才能登录。运行设置会保留。',
          style: TextStyle(fontSize: 12.5, color: Tokens.textSecondary, height: 1.5),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Tokens.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('退出登录'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 运行设置。手机用底部抽屉，桌面用对话框；运行中整块只读并说明原因。
Future<void> showRunSettings(BuildContext context) async {
  final state = AppScope.of(context);
  final compact = MediaQuery.sizeOf(context).width < 600;
  var draft = state.settings;

  Widget form(StateSetter setLocal) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.running) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Tokens.warningSoft,
              borderRadius: BorderRadius.circular(Tokens.radiusControl),
            ),
            child: const Text(
              '运行中不可修改，结束后再调',
              style: TextStyle(fontSize: 11.5, color: Tokens.warning),
            ),
          ),
          const SizedBox(height: 10),
        ],
        IgnorePointer(
          ignoring: state.running,
          child: Opacity(
            opacity: state.running ? 0.55 : 1,
            child: Column(
              children: [
                _RangeField(
                  label: '每节等待（秒）',
                  min: 30,
                  max: 900,
                  range: draft.waitMin.toDouble().clamp(30, 900),
                  range2: draft.waitMax.toDouble().clamp(30, 900),
                  onChange: (a, b) => setLocal(() => draft = draft.copyWith(waitMin: a, waitMax: b)),
                ),
                _RangeField(
                  label: '目标正确率（%）',
                  min: 0,
                  max: 100,
                  range: draft.rateMin.toDouble(),
                  range2: draft.rateMax.toDouble(),
                  onChange: (a, b) => setLocal(() => draft = draft.copyWith(rateMin: a, rateMax: b)),
                ),
                _RangeField(
                  label: '节间间隔（秒）',
                  min: 0,
                  max: 60,
                  range: draft.intervalMin.toDouble(),
                  range2: draft.intervalMax.toDouble(),
                  onChange: (a, b) => setLocal(() => draft = draft.copyWith(intervalMin: a, intervalMax: b)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: draft.skipOralLesson,
                  onChanged: (v) => setLocal(() => draft = draft.copyWith(skipOralLesson: v)),
                  title: const Text('跳过口语小节', style: TextStyle(fontSize: 12.5)),
                  subtitle: const Text(
                    '按小节名识别，重新扫描后生效',
                    style: TextStyle(fontSize: 11, color: Tokens.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '口语/录音类题目默认不提交（解析层已跳过）。',
          style: TextStyle(fontSize: 11, color: Tokens.textTertiary),
        ),
      ],
    );
  }

  if (compact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.radiusCard)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocal) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 8),
                const Text('运行设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                form(setLocal),
                const SizedBox(height: 16),
                SizedBox(
                  height: Tokens.tapMin,
                  child: FilledButton(
                    onPressed: state.running
                        ? null
                        : () async {
                            await state.saveSettings(draft);
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          },
                    child: Text(state.running ? '运行中不可修改' : '保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        backgroundColor: Tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusCard)),
        title: const Text('运行设置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: SizedBox(width: 420, child: form(setLocal)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(
            onPressed: state.running
                ? null
                : () async {
                    await state.saveSettings(draft);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Tokens.borderStrong,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.label,
    required this.min,
    required this.max,
    required this.range,
    required this.range2,
    required this.onChange,
  });

  final String label;
  final double min;
  final double max;
  final double range;
  final double range2;
  final void Function(int a, int b) onChange;

  @override
  Widget build(BuildContext context) {
    final start = range < range2 ? range : range2;
    final end = range < range2 ? range2 : range;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Tokens.textSecondary)),
              const Spacer(),
              Text('${start.round()} – ${end.round()}',
                  style: monoStyle(size: 11.5, color: Tokens.textPrimary)),
            ],
          ),
          RangeSlider(
            values: RangeValues(start, end),
            min: min,
            max: max,
            divisions: (max - min).round(),
            activeColor: Tokens.accent,
            inactiveColor: Tokens.mutedSoft,
            labels: RangeLabels('${start.round()}', '${end.round()}'),
            onChanged: (v) => onChange(v.start.round(), v.end.round()),
          ),
        ],
      ),
    );
  }
}
