import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/browser_login.dart';
import '../core/updater.dart';
import '../theme.dart';
import 'app_scope.dart';
import 'login_web_page.dart';
import 'widgets.dart';

/// 登录入口。桌面用对话框，手机用底部抽屉。
///
/// 手机上没有开发者工具，所以先给「从剪贴板读取」；读到的 Cookie **不回显**，
/// 只显示识别到的项数与前几个名字（截图不会泄露凭据）。
/// 登录入口。桌面用对话框，手机用底部抽屉。
///
/// [pasteOnly] 为 true 时只显示粘贴方式——设置页把「内置浏览器登录」做成了独立按钮，
/// 再在弹窗里放一遍会造成两个入口做同一件事。
Future<void> showLoginDialog(
  BuildContext context, {
  bool pasteOnly = false,
}) async {
  final state = AppScope.of(context);
  final compact = MediaQuery.sizeOf(context).width < 600;
  final controller = TextEditingController();
  var showRaw = pasteOnly || !compact;
  String? summary;

  Widget body(StateSetter setLocal) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pasteOnly
              ? (compact
                    ? '先在手机浏览器登录 welearn.sflep.com，复制 Cookie，再点下面的按钮读取。'
                    : '在浏览器登录 welearn.sflep.com，从开发者工具复制 Cookie，粘到下面。')
              : (compact
                    ? '用内置浏览器登录最省事；也可以先在手机浏览器登录后复制 Cookie。'
                    : '用内置浏览器登录，或者从开发者工具复制 Cookie 粘贴。'),
          style: const TextStyle(
            fontSize: 12,
            color: Tokens.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (!pasteOnly) ...[
          SizedBox(
            width: double.infinity,
            height: compact ? Tokens.tapMin : Tokens.controlHeight + 8,
            child: FilledButton.icon(
              onPressed: state.busy
                  ? null
                  : () async {
                      final ok = await openBrowserLogin(context);
                      if (ok && context.mounted) Navigator.pop(context);
                    },
              icon: const Icon(Icons.language_rounded, size: 18),
              label: const Text('用内置浏览器登录'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '或粘贴 Cookie',
                  style: TextStyle(fontSize: 11, color: Tokens.textTertiary),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 10),
        ],
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
                  color: summary!.startsWith('已读取')
                      ? Tokens.success
                      : Tokens.warning,
                  height: 1.4,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setLocal(() => showRaw = true),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
              ),
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
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('改用剪贴板读取', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
        if (state.lastError != null) ...[
          const SizedBox(height: 8),
          Text(
            state.lastError!,
            style: const TextStyle(
              fontSize: 11.5,
              color: Tokens.danger,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 6),
        const Text(
          '账号密码只在平台页面里输入；默认不保存密码，可在登录成功后选择保存。',
          style: TextStyle(
            fontSize: 11,
            color: Tokens.textTertiary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Future<void> submit(BuildContext dialogContext) async {
    final ok = await state.login(controller.text);
    if (!dialogContext.mounted) return;
    if (!ok) return;
    Navigator.pop(dialogContext);
    // 粘贴 Cookie 登录没有账号密码，只询问是否保存登录状态
    if (!state.rememberLogin && context.mounted) {
      await promptSaveLogin(context, state);
    }
  }

  if (compact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Tokens.radiusCard),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
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
                  const Text(
                    '登录 WE Learn',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: const Text(
          '登录 WE Learn',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(width: 460, child: body(setLocal)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
      ),
      title: const Text(
        '退出登录',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      content: const SizedBox(
        width: 360,
        child: Text(
          '退出后会清除本机保存的 Cookie 与当前课程数据，下次需要重新粘贴 Cookie 才能登录。运行设置会保留。',
          style: TextStyle(
            fontSize: 12.5,
            color: Tokens.textSecondary,
            height: 1.5,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
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

/// 强制清除所有本机会话凭据前的确认。
Future<bool> confirmForceClear(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Tokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
      ),
      title: const Text(
        '强制清除会话凭据',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      content: const SizedBox(
        width: 360,
        child: Text(
          '会删除本机保存的所有账号 Cookie，并停止当前运行；课程与扫描结果也会清空。下次需要重新登录。',
          style: TextStyle(
            fontSize: 12.5,
            color: Tokens.textSecondary,
            height: 1.5,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Tokens.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('强制清除'),
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
                  onChange: (a, b) => setLocal(
                    () => draft = draft.copyWith(waitMin: a, waitMax: b),
                  ),
                ),
                _RangeField(
                  label: '目标正确率（%）',
                  min: 0,
                  max: 100,
                  range: draft.rateMin.toDouble(),
                  range2: draft.rateMax.toDouble(),
                  onChange: (a, b) => setLocal(
                    () => draft = draft.copyWith(rateMin: a, rateMax: b),
                  ),
                ),
                _RangeField(
                  label: '节间间隔（秒）',
                  min: 0,
                  max: 60,
                  range: draft.intervalMin.toDouble(),
                  range2: draft.intervalMax.toDouble(),
                  onChange: (a, b) => setLocal(
                    () =>
                        draft = draft.copyWith(intervalMin: a, intervalMax: b),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: draft.skipOralLesson,
                  onChanged: (v) =>
                      setLocal(() => draft = draft.copyWith(skipOralLesson: v)),
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Tokens.radiusCard),
        ),
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
                const Text(
                  '运行设置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
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
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: const Text(
          '运行设置',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(width: 420, child: form(setLocal)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
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
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Tokens.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${start.round()} – ${end.round()}',
                style: monoStyle(size: 11.5, color: Tokens.textPrimary),
              ),
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

/// 关闭窗口时的选择结果
class CloseDecision {
  const CloseDecision({required this.toTray, required this.remember});
  final bool toTray;
  final bool remember;
}

/// 点关闭按钮后的询问：退出应用 / 最小化到托盘继续运行。
/// 返回 null 表示取消（窗口保持打开）。
Future<CloseDecision?> showCloseDialog(BuildContext context) async {
  final state = AppScope.of(context);
  var remember = false;

  return showDialog<CloseDecision>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        backgroundColor: Tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: const Text(
          '关闭 WeLearn 助手',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.running
                    ? '当前有任务在运行。最小化到托盘可以让它继续；退出应用会中断本节（已完成的节保留）。'
                    : '要退出应用，还是缩小到托盘继续运行？',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Tokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '托盘图标在任务栏右下角，右键可以重新打开或退出。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Tokens.textTertiary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => setLocal(() => remember = !remember),
                borderRadius: BorderRadius.circular(Tokens.radiusControl),
                child: Row(
                  children: [
                    AppCheckbox(
                      value: remember,
                      label: '下次不再询问',
                      onChanged: (v) => setLocal(() => remember = v),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        '下次不再询问（记住本次选择）',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              CloseDecision(toTray: false, remember: remember),
            ),
            style: TextButton.styleFrom(foregroundColor: Tokens.danger),
            child: const Text('关闭应用'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              CloseDecision(toTray: true, remember: remember),
            ),
            child: const Text('最小化到托盘'),
          ),
        ],
      ),
    ),
  );
}

/// 登录成功后询问是否保存登录状态。
///
/// 返回 `null` 表示不保存；`false` 只保存 Cookie；`true` 同时记录账号密码。
/// [hasCredentials] 为 false（例如粘贴 Cookie 登录）时不提供密码选项。
Future<bool?> askSaveLoginAfterLogin(
  BuildContext context, {
  required bool hasCredentials,
}) async {
  // 与设置页一致：窄屏竖排全宽按钮，桌面端横排
  final compact = MediaQuery.sizeOf(context).width < 600;
  final body = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        '是否保存登录状态？保存后从托盘完全退出应用再打开会自动恢复登录。',
        style: TextStyle(
          fontSize: 12.5,
          color: Tokens.textSecondary,
          height: 1.5,
        ),
      ),
      if (hasCredentials) ...[
        const SizedBox(height: 10),
        const Text(
          '也可以同时记录刚才输入的账号密码：登录信息在别处失效时会在后台自动重登。账号密码只保存在本机，不会上传。',
          style: TextStyle(
            fontSize: 12.5,
            color: Tokens.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    ],
  );

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      if (compact) {
        return Dialog(
          backgroundColor: Tokens.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusCard),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '登录成功',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                body,
                const SizedBox(height: 18),
                if (hasCredentials) ...[
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('保存账号密码'),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(hasCredentials ? '仅保存登录状态' : '保存登录状态'),
                ),
                const SizedBox(height: 2),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('暂不保存'),
                ),
              ],
            ),
          ),
        );
      }
      return AlertDialog(
        backgroundColor: Tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: const Text(
          '登录成功',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(width: 420, child: body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('暂不保存'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(hasCredentials ? '仅保存登录状态' : '保存登录状态'),
          ),
          if (hasCredentials)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存账号密码'),
            ),
        ],
      );
    },
  );
}

/// 登录成功后按用户选择写入「保存登录状态」与账号密码。
Future<void> promptSaveLogin(
  BuildContext context,
  AppState state, {
  String? username,
  String? password,
}) async {
  final hasCredentials = username != null && password != null;
  final choice = await askSaveLoginAfterLogin(
    context,
    hasCredentials: hasCredentials,
  );
  if (choice == null) return;
  await state.setRememberLogin(true, savePassword: choice);
  if (choice && hasCredentials) {
    await state.saveCredentials(username, password);
  }
}

/// 发现新版本时的更新询问弹窗。
///
/// 弹窗内直接展示版本内容并下载、显示进度；下载期间提供「后台更新」，
/// 关闭弹窗后下载继续，进度同步到安卓通知栏 / Windows 任务栏。
Future<void> showUpdateDialog(BuildContext context) async {
  final state = AppScope.of(context);
  final release = state.latestRelease;
  if (release == null) return;
  final progressHost =
      defaultTargetPlatform == TargetPlatform.android ? '通知栏' : '任务栏';

  await showDialog<void>(
    context: context,
    // 下载中误点外部会中断用户对进度条的观察，只允许按钮关闭
    barrierDismissible: false,
    builder: (dialogContext) {
      // 通过 AppScope 读取，下载进度 notifyListeners 时弹窗自动重建
      final live = AppScope.of(dialogContext);
      final notes = release.notes.trim();
      final percent = (live.updateProgress * 100).round();

      return AlertDialog(
        backgroundColor: Tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: Text(
          '发现新版本 ${release.version}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '当前版本 $appVersion，可更新到 ${release.version}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Tokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Tokens.canvas,
                  borderRadius: BorderRadius.circular(Tokens.radiusControl),
                  border: Border.all(color: Tokens.border),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    notes.isEmpty ? '本次更新包含问题修复与体验改进。' : notes,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Tokens.textSecondary,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
              if (live.downloadingUpdate || live.updateProgress > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: live.updateProgress > 0
                        ? live.updateProgress
                        : null,
                    minHeight: 5,
                    backgroundColor: Tokens.mutedSoft,
                    valueColor: const AlwaysStoppedAnimation(Tokens.accent),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '正在下载 $percent%，进度同步显示在$progressHost',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Tokens.textTertiary,
                  ),
                ),
              ],
              if (live.updateError != null) ...[
                const SizedBox(height: 8),
                Text(
                  live.updateError!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Tokens.danger,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (live.downloadingUpdate)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('后台更新'),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('拒绝更新'),
            ),
            FilledButton(
              onPressed: () => _runUpdate(dialogContext, live),
              child: const Text('更新'),
            ),
          ],
        ],
      );
    },
  );
}

/// 下载并安装更新。
///
/// 用弹窗的上下文只在下载完成、弹窗仍打开时关闭它；用户点过「后台更新」
/// 后即使上下文已失效，下载与安装仍会继续。
Future<void> _runUpdate(BuildContext dialogContext, AppState state) async {
  final path = await state.downloadUpdate();
  if (path == null) return;
  if (dialogContext.mounted) Navigator.pop(dialogContext);
  await state.installUpdate(path);
}

/// 打开内置浏览器完成登录，成功后直接把 Cookie 交给 [AppState.login]。
/// 返回是否登录成功（用户取消返回 false）。
Future<bool> openBrowserLogin(BuildContext context) async {
  final state = AppScope.of(context);
  // 先清掉 WebView 里的旧会话：否则失效 Cookie 会让登录页直接跳到
  // /student/，被误判为「已登录」并立刻关闭（用户感知就是内置浏览器闪退）。
  await clearBrowserSession();
  if (!context.mounted) return false;
  final result = await Navigator.of(context).push<LoginPageResult>(
    MaterialPageRoute(builder: (_) => const LoginWebPage()),
  );
  if (result == null || result.cookie.isEmpty) return false;
  final ok = await state.login(result.cookie);
  if (!ok) return false;

  final username = result.username;
  final password = result.password;
  if (state.rememberLogin) {
    // 已开启保存登录状态时，只按用户此前是否选择记录密码来决定是否补存
    if (username != null && password != null) {
      await state.saveCredentials(username, password);
    }
  } else if (context.mounted) {
    // 默认不保存：登录成功后询问一次，避免用户以为「刚登录就失效」
    await promptSaveLogin(
      context,
      state,
      username: username,
      password: password,
    );
  }
  return true;
}
