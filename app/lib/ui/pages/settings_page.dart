import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../core/updater.dart';
import '../../mobile_background.dart';
import '../../theme.dart';
import '../app_scope.dart';
import '../components.dart';
import '../dialogs.dart';
import '../widgets.dart' show AccountAvatar, Caret;

/// 手机上没有托盘，桌面 / 安卓的「应用」设置各有一套。
/// 用 defaultTargetPlatform 而不是 dart:io.Platform：窗口尺寸测试里也能切换。
/// 只认 Android —— 本项目没有 iOS 构建，别在不支持的平台显示不可用的开关。
bool get isMobilePlatform => defaultTargetPlatform == TargetPlatform.android;

Future<void> _openRepo(BuildContext context, String url) async {
  final launched = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法打开浏览器，请手动访问 GitHub 仓库')));
  }
}

/// 设置：账号、课程、应用行为、本机数据。
///
/// 只放"软件本身"的配置；每节等待、正确率这类跟一次运行绑定的参数在任务页。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final wide = width >= 1080;

    final account = _AccountGroup(state: state, compact: compact);
    final course = _CourseGroup(state: state);
    final Widget app = isMobilePlatform
        ? const _MobileAppGroup()
        : _DesktopAppGroup(state: state, compact: compact);
    final data = _DataGroup(state: state);
    final about = _AboutGroup(state: state);
    final status = _StatusCard(state: state);
    final lastRun = _LastRunCard(state: state);

    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 18),
          children[i],
        ],
      ],
    );

    final content = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: column([account, course, app, data, about])),
              const SizedBox(width: 20),
              SizedBox(width: 320, child: column([status, lastRun])),
            ],
          )
        : column([account, course, app, data, status, lastRun, about]);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        compact ? Tokens.pagePaddingCompact : Tokens.pagePadding,
        compact ? 14 : 20,
        compact ? Tokens.pagePaddingCompact : Tokens.pagePadding,
        28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Tokens.pageMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(
                title: '设置',
                subtitle: '账号、课程与软件行为；运行参数在任务页调整',
              ),
              const SizedBox(height: 18),
              content,
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({required this.state, required this.compact});

  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final account = state.activeAccount;
    final course = state.currentCourse;
    final initials = (course?.name ?? 'W').characters.first;

    return SettingGroup(
      title: '账号',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              AccountAvatar(
                bytes: state.avatarBytes,
                initials: initials,
                size: 36,
                loggedIn: state.loggedIn,
                loading: state.avatarLoading,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.loggedIn ? (course?.name ?? '已连接') : '未登录',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.loggedIn
                          ? [
                              if (account?.uid != null) 'uid ${account!.uid}',
                              '${state.courses.length} 门课程',
                              if (state.lastLoginAt != null)
                                '最近登录 ${_stamp(state.lastLoginAt!)}',
                            ].join(' · ')
                          : '登录后才能扫描课程与运行任务',
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Tokens.textTertiary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.loggedIn) ...[
                IconButton(
                  onPressed: state.avatarLoading ? null : state.refreshAvatar,
                  tooltip: '从 WeLearn 刷新头像',
                  iconSize: 16,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(28, 28),
                    fixedSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: state.avatarLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Tokens.accent,
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: Tokens.textTertiary,
                        ),
                ),
                const SizedBox(width: 6),
              ],
              if (state.loggedIn)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Tokens.successSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '已连接',
                    style: TextStyle(fontSize: 10.5, color: Tokens.success),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: Tokens.border.withValues(alpha: 0.6)),
        // 登录失效后正在后台重登：未登录按钮先禁用，避免手动操作打断自动恢复
        if (!state.loggedIn && state.autoLoginAttempting)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Tokens.accent,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正在用保存的账号密码自动登录，请稍候…',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Tokens.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (state.loggedIn) ...[
                OutlinedButton.icon(
                  style: toolbarOutlined(),
                  onPressed: state.running || state.scanning
                      ? null
                      : () => openBrowserLogin(context),
                  icon: const Icon(Icons.language_rounded, size: 15),
                  label: const Text('更换账号'),
                ),
                OutlinedButton(
                  style: toolbarOutlined(),
                  onPressed: () => showLoginDialog(context, pasteOnly: true),
                  child: const Text('粘贴 Cookie'),
                ),
                TextButton(
                  onPressed: state.running
                      ? null
                      : () async {
                          if (await confirmLogout(context)) {
                            await state.logout();
                          }
                        },
                  style: toolbarText(foreground: Tokens.danger),
                  child: const Text('退出登录'),
                ),
              ] else ...[
                FilledButton.icon(
                  style: toolbarFilled(),
                  onPressed: state.busy || state.autoLoginAttempting
                      ? null
                      : () => openBrowserLogin(context),
                  icon: const Icon(Icons.language_rounded, size: 15),
                  label: Text(
                    state.autoLoginAttempting
                        ? '自动登录中…'
                        : (state.busy ? '连接中…' : '内置浏览器登录'),
                  ),
                ),
                OutlinedButton(
                  style: toolbarOutlined(),
                  onPressed: state.busy || state.autoLoginAttempting
                      ? null
                      : () => showLoginDialog(context, pasteOnly: true),
                  child: const Text('粘贴 Cookie'),
                ),
              ],
            ],
          ),
        ),
        Padding(
          // 和按钮行拉开 6px；错误提示贴在说明文字上方，
          // 不再单独悬在按钮和说明之间。
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.lastError != null) ...[
                Text(
                  state.lastError!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Tokens.danger,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                compact
                    ? '内置浏览器里直接输入平台账号密码；头像登录时从 WeLearn 读取，可点右侧刷新。'
                    : '内置浏览器打开真实登录页，账号密码只在平台页面输入；头像从 WeLearn 学生主页实时读取。',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Tokens.textTertiary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Tokens.border.withValues(alpha: 0.6)),
        SettingRow(
          title: '保存登录状态',
          description: _rememberHint(),
          trailing: CompactSwitch(
            value: state.rememberLogin,
            tooltip: '保存登录状态',
            onChanged: state.busy
                ? null
                : (value) => _toggleRememberLogin(context, value),
          ),
        ),
      ],
    );
  }

  /// 开关下方的说明：区分「已记录账号密码」「尚未记录」和「已关闭」三种状态。
  String _rememberHint() {
    if (!state.rememberLogin) {
      return '关闭后从托盘完全退出应用不会保留登录信息，下次需要重新登录';
    }
    if (state.savePassword) {
      return state.activeAccount?.hasCredentials == true
          ? '已记录本机账号密码；Cookie 过期或在别处登录导致失效时，会在后台自动重登'
          : '尚未记录账号密码；下次通过内置浏览器登录时自动记录，之后可后台自动重登';
    }
    return '只保存 Cookie；失效后需要手动重新登录';
  }

  /// 开启时询问是否同时记录账号密码（关闭则直接生效）。
  ///
  /// 账号密码用于 Cookie 失效后的后台自动重登，属于更敏感的数据，
  /// 所以不默认勾选，必须由用户明确选择；取消时保持关闭状态。
  Future<void> _toggleRememberLogin(BuildContext context, bool value) async {
    if (!value) {
      await state.setRememberLogin(false);
      return;
    }
    // 手机上 AlertDialog 的 actions 会把两个按钮挤成上下两行，很难看；
    // 窄屏改成竖排全宽按钮，桌面端保持横排。
    final compact = MediaQuery.sizeOf(context).width < 600;
    const body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '开启后，从托盘完全退出应用再打开会恢复上次登录。',
          style: TextStyle(
            fontSize: 12.5,
            color: Tokens.textSecondary,
            height: 1.5,
          ),
        ),
        SizedBox(height: 10),
        Text(
          '是否同时记录内置浏览器里输入过的账号密码？记录后，当登录信息在别处失效时会在后台自动重新登录，避免运行中断。账号密码只保存在本机，不会上传。',
          style: TextStyle(
            fontSize: 12.5,
            color: Tokens.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );

    final choice = await showDialog<bool>(
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
                    '保存登录状态',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  body,
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('保存账号密码'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('仅保存登录状态'),
                  ),
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'),
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
            '保存登录状态',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          content: const SizedBox(width: 400, child: body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('仅保存登录状态'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存账号密码'),
            ),
          ],
        );
      },
    );
    if (choice == null) return;
    await state.setRememberLogin(true, savePassword: choice);
  }

  String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _CourseGroup extends StatelessWidget {
  const _CourseGroup({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final course = state.currentCourse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingGroup(
          title: '课程',
          children: [
            SettingRow(
              title: '当前课程',
              description: state.courses.isEmpty
                  ? '登录后自动识别账号下的课程'
                  : (course == null ? '未选择' : '平台进度 ${course.percent}%'),
              trailing: state.courses.length > 1
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
                      child: _DropdownChip(label: course?.name ?? '选择课程'),
                    )
                  : Text(
                      course?.name ?? '—',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Tokens.textSecondary,
                      ),
                    ),
            ),
            SettingRow(
              title: '重新扫描',
              description: '重新读取单元与小节列表，勾选状态会重置为全部待处理',
              trailing: ScanButton(
                scanning: state.scanning,
                onPressed: state.running || state.currentCid == null
                    ? null
                    : () => state.loadCourse(state.currentCid!),
              ),
            ),
          ],
        ),
        if (state.scanning) ...[
          const SizedBox(height: 10),
          ScanIndicator(stage: state.scanStage, compact: true),
        ],
      ],
    );
  }
}

/// 桌面端：关闭窗口的行为与托盘图标。
class _DesktopAppGroup extends StatelessWidget {
  const _DesktopAppGroup({required this.state, required this.compact});

  final AppState state;
  final bool compact;

  static const _options = [
    ('ask', '每次询问'),
    ('tray', '最小化到托盘'),
    ('quit', '直接退出'),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingGroup(
      title: '应用',
      children: [
        SettingRow(
          title: '关闭窗口时',
          description: compact ? '仅桌面端生效' : '点击右上角 × 后的行为，也可以在弹窗里勾选「不再询问」',
          bottom: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (value, label) in _options)
                _ChoiceButton(
                  label: label,
                  active: state.closeAction == value,
                  onTap: () => state.setCloseAction(value),
                ),
            ],
          ),
        ),
        SettingRow(
          title: '托盘图标',
          description: '最小化后在任务栏右下角（可能折叠在 ^ 里）；左键打开窗口，右键菜单可重新扫描或退出',
          trailing: const Text(
            '桌面端可用',
            style: TextStyle(fontSize: 11, color: Tokens.textTertiary),
          ),
        ),
      ],
    );
  }
}

/// 手机端：托盘的等价物是 Wake Lock + 前台服务常驻通知。
class _MobileAppGroup extends StatefulWidget {
  const _MobileAppGroup();

  @override
  State<_MobileAppGroup> createState() => _MobileAppGroupState();
}

class _MobileAppGroupState extends State<_MobileAppGroup>
    with WidgetsBindingObserver {
  BackgroundPermission? _permission;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页返回时刷新授权状态，不用重开应用
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final value = await MobileBackground.status();
    if (mounted) setState(() => _permission = value);
  }

  Future<void> _requestPermission() async {
    setState(() => _requesting = true);
    await MobileBackground.requestNotificationPermission();
    await _refreshPermission();
    if (mounted) setState(() => _requesting = false);
  }

  Future<void> _showPermissionGuide() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Tokens.radiusCard),
        ),
      ),
      builder: (_) => const _PermissionGuideSheet(),
    );
    await _refreshPermission();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final granted = _permission?.notification;
    final battery = _permission?.batteryUnrestricted;

    final summary = _permission == null
        ? '通知、电池与自启动都会影响息屏后的续跑'
        : '通知${granted == true ? "已授予" : "未授予"} · '
              '电池${battery == true ? "无限制" : "可能被优化"}';

    return SettingGroup(
      title: '应用',
      children: [
        SettingRow(
          title: '保持后台运行',
          description: '息屏后保持 CPU 运行（Wake Lock），长任务不会被系统冻结；会多耗一点电',
          trailing: Switch(
            value: state.keepAwake,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => state.setBackgroundMode(keepAwake: v),
          ),
        ),
        SettingRow(
          title: '任务栏常驻',
          description: '通知栏显示任务进度与「开始 / 停止」按钮，点通知可回到应用；相当于桌面端的托盘',
          trailing: Switch(
            value: state.persistentNotification,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => state.setBackgroundMode(persistent: v),
          ),
        ),
        SettingRow(
          title: '权限申请',
          description: summary,
          trailing: TextButton(
            style: toolbarText(),
            onPressed: _showPermissionGuide,
            child: const Text('权限引导'),
          ),
          bottom: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                style: toolbarOutlined(),
                onPressed: _requesting ? null : _requestPermission,
                child: Text(
                  _requesting ? '申请中…' : (granted == true ? '通知已开启' : '开启通知'),
                ),
              ),
              OutlinedButton(
                style: toolbarOutlined(),
                onPressed: battery == true
                    ? null
                    : MobileBackground.requestIgnoreBatteryOptimizations,
                child: Text(battery == true ? '电池无限制' : '设为电池无限制'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            '锁屏续跑依赖通知权限与 Wake Lock；长时间挂机还需要电池无限制、允许自启动，'
            '并在最近任务里锁定本应用。点「权限引导」按步骤设置。',
            style: TextStyle(
              fontSize: 10.5,
              color: Tokens.textTertiary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// 后台权限引导：通知、电池无限制、自启动、最近任务锁定，逐项给出入口。
class _PermissionGuideSheet extends StatefulWidget {
  const _PermissionGuideSheet();

  @override
  State<_PermissionGuideSheet> createState() => _PermissionGuideSheetState();
}

class _PermissionGuideSheetState extends State<_PermissionGuideSheet>
    with WidgetsBindingObserver {
  BackgroundPermission? _permission;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final value = await MobileBackground.status();
    if (mounted) setState(() => _permission = value);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final notification = _permission?.notification;
    final battery = _permission?.batteryUnrestricted;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SingleChildScrollView(
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
              const SizedBox(height: 12),
              const Text(
                '后台运行权限引导',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                '安卓系统会回收长时间后台的应用。下面四项建议全部设置，息屏挂机才不容易中断。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Tokens.textTertiary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              _GuideRow(
                title: '1. 通知权限',
                description: '任务栏常驻与进度显示依赖通知权限（Android 13+ 需要手动授权）',
                status: notification == true ? '已授予' : '未授予',
                ok: notification == true,
                actionLabel: notification == true ? '重新申请' : '去授权',
                onTap: _busy
                    ? null
                    : () => _run(
                        () async =>
                            MobileBackground.requestNotificationPermission(),
                      ),
              ),
              const Divider(height: 1),
              _GuideRow(
                title: '2. 电池优化',
                description: '把应用设为「无限制」，避免系统在息屏后冻结后台任务',
                status: battery == true ? '无限制' : '受系统优化',
                ok: battery == true,
                actionLabel: battery == true ? '重新检查' : '设为无限制',
                onTap: _busy
                    ? null
                    : () => _run(
                        MobileBackground.requestIgnoreBatteryOptimizations,
                      ),
              ),
              const Divider(height: 1),
              _GuideRow(
                title: '3. 自启动',
                description: '部分厂商（小米 / 华为 / OPPO / vivo）需要允许应用自启动与后台活动',
                status: '按厂商设置',
                ok: false,
                actionLabel: '打开自启动设置',
                onTap: _busy
                    ? null
                    : () => _run(MobileBackground.openAutoStartSettings),
              ),
              const Divider(height: 1),
              _GuideRow(
                title: '4. 最近任务锁定',
                description: '打开最近任务，把本应用卡片下拉（或点小锁图标）锁定，防止一键清理时被划掉',
                status: '手动操作',
                ok: false,
                actionLabel: '打开应用详情',
                onTap: _busy
                    ? null
                    : () => _run(MobileBackground.openAppSettings),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Tokens.accentSoft,
                  borderRadius: BorderRadius.circular(Tokens.radiusControl),
                ),
                child: const Text(
                  '设置完成后回到本页，状态会自动刷新。任务运行时通知栏会显示「第 n/总 节」、'
                  '本节剩余时间，并提供开始 / 停止按钮。',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Tokens.textSecondary,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: Tokens.tapMin,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
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

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.title,
    required this.description,
    required this.status,
    required this.ok,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String description;
  final String status;
  final bool ok;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: ok ? Tokens.successSoft : Tokens.mutedSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10,
                          color: ok ? Tokens.success : Tokens.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Tokens.textTertiary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: toolbarText(),
            onPressed: onTap,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _DataGroup extends StatelessWidget {
  const _DataGroup({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SettingGroup(
      title: '数据',
      children: [
        SettingRow(
          title: '日志',
          description: '只清空面板里的运行日志与最近结果，不影响登录态',
          trailing: TextButton(
            style: toolbarText(),
            onPressed: state.logs.isEmpty && state.recentResults.isEmpty
                ? null
                : state.clearLogs,
            child: const Text('清空'),
          ),
        ),
        SettingRow(
          title: '会话凭据',
          description: 'Cookie 只保存在本机应用数据目录，不会上传到任何服务器',
          trailing: const Text(
            '仅本机',
            style: TextStyle(fontSize: 11, color: Tokens.textTertiary),
          ),
          bottom: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: toolbarText(foreground: Tokens.danger),
              onPressed: state.accounts.isEmpty && !state.loggedIn
                  ? null
                  : () async {
                      if (await confirmForceClear(context)) {
                        await state.forceClearCredentials();
                      }
                    },
              child: const Text('强制清除会话凭据'),
            ),
          ),
        ),
      ],
    );
  }
}

class _AboutGroup extends StatelessWidget {
  const _AboutGroup({required this.state});

  final AppState state;

  String _status() {
    if (state.checkingUpdate) return '正在检查 GitHub Releases…';
    if (state.downloadingUpdate) {
      return '正在下载更新包（${(state.updateProgress * 100).round()}%）';
    }
    final release = state.latestRelease;
    if (release != null) {
      return state.hasUpdate
          ? '发现新版本 ${release.version}，可一键更新'
          : '已是最新版本 $appVersion';
    }
    return '从 GitHub Releases 检查最新版本';
  }

  Future<void> _install(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await state.downloadUpdate();
    if (!context.mounted) return;
    if (path == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(state.updateError ?? '下载更新失败')),
      );
      return;
    }
    await state.installUpdate(path);
    if (!context.mounted) return;
    final error = state.updateError;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = state.latestRelease;

    return SettingGroup(
      title: '关于',
      children: [
        SettingRow(
          title: 'WeLearn 助手',
          description: '$appVersion · Flutter 桌面 / 安卓双端',
          trailing: Text(
            state.hasUpdate ? '可更新 ${release!.version}' : '本地运行',
            style: TextStyle(
              fontSize: 11,
              color: state.hasUpdate ? Tokens.accent : Tokens.textTertiary,
            ),
          ),
        ),
        SettingRow(
          title: '检查更新',
          description: _status(),
          trailing: TextButton(
            style: toolbarText(),
            onPressed: state.checkingUpdate || state.downloadingUpdate
                ? null
                : state.checkForUpdate,
            child: Text(state.checkingUpdate ? '检查中…' : '检查更新'),
          ),
          bottom: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.downloadingUpdate) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: state.updateProgress > 0
                        ? state.updateProgress
                        : null,
                    minHeight: 4,
                    backgroundColor: Tokens.mutedSoft,
                    valueColor: const AlwaysStoppedAnimation(Tokens.accent),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '正在下载 ${(state.updateProgress * 100).round()}%，完成后${isMobilePlatform ? '会打开系统安装器' : '会自动重启安装'}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Tokens.textTertiary,
                  ),
                ),
              ] else if (state.hasUpdate) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    style: toolbarFilled(),
                    onPressed: () => _install(context),
                    icon: const Icon(Icons.system_update_alt_rounded, size: 16),
                    label: Text(isMobilePlatform ? '下载并安装 APK' : '下载并自动安装'),
                  ),
                ),
              ],
              if (state.updateError != null) ...[
                const SizedBox(height: 6),
                Text(
                  state.updateError!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Tokens.danger,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        SettingRow(
          title: '版本更新历史',
          description: '点击此处可查看历史版本更新信息',
          trailing: TextButton(
            style: toolbarText(),
            onPressed: () => showReleaseHistory(context),
            child: const Text('查看'),
          ),
        ),
        SettingRow(
          title: 'GitHub 仓库',
          description: state.repoUrl,
          trailing: TextButton(
            style: toolbarText(),
            onPressed: () => _openRepo(context, state.repoUrl),
            child: const Text('打开'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '本工具用于个人学习与接口自动化练习。请自行确认使用行为符合所在学校与平台的服务条款；'
            '由此产生的一切后果由使用者承担。不包含验证码识别、设备指纹伪造等规避安全机制的代码。',
            style: TextStyle(
              fontSize: 10.5,
              color: Tokens.textTertiary,
              height: 1.65,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final course = state.currentCourse;
    final rows = <(String, String)>[
      ('登录状态', state.loggedIn ? '已连接' : '未登录'),
      ('课程', course?.name ?? '—'),
      ('平台进度', course == null ? '—' : '${course.percent}%'),
      ('小节', state.lessons.isEmpty ? '未扫描' : '${state.lessons.length} 节'),
      ('待处理', '${state.candidates.length} 节'),
      ('已选', '${state.selectedCount} 节'),
      ('预计耗时', humanDuration(state.remainingEstimate)),
      (
        '账号',
        state.activeAccount?.uid == null
            ? '—'
            : 'uid ${state.activeAccount!.uid}',
      ),
    ];

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本机状态',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 68,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Tokens.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 18),
          Text(
            state.running
                ? (isMobilePlatform
                      ? '任务正在运行，保持后台运行与常驻通知可避免息屏中断。'
                      : '任务正在运行，关闭窗口可以选择最小化到托盘。')
                : '当前没有运行中的任务。',
            style: const TextStyle(
              fontSize: 10.5,
              color: Tokens.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LastRunCard extends StatelessWidget {
  const _LastRunCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final duration = state.lastRunDuration;
    final end = state.runFinishedAt;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最近一次运行',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (state.runTotal == 0)
            const Text(
              '还没有运行记录。到任务页勾选小节后开始。',
              style: TextStyle(
                fontSize: 11,
                color: Tokens.textTertiary,
                height: 1.5,
              ),
            )
          else ...[
            _kv('队列', '${state.runTotal} 节'),
            _kv('完成', '${state.runDone} 节'),
            _kv('失败', '${state.failedCount} 节'),
            _kv(
              '用时',
              duration == null ? '—' : humanDuration(duration.inSeconds),
            ),
            _kv('结束', end == null ? '进行中' : _stamp(end)),
          ],
        ],
      ),
    );
  }

  /// 与 _StatusCard 的行完全同一套：68 标签列 + 基线对齐 + 右对齐数值
  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 68,
          child: Text(
            k,
            style: const TextStyle(fontSize: 11, color: Tokens.textTertiary),
          ),
        ),
        Expanded(
          child: Text(
            v,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
      ],
    ),
  );

  String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _DropdownChip extends StatelessWidget {
  const _DropdownChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Caret(color: Tokens.textTertiary, width: 6),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Tokens.accentSoft : Tokens.surface,
      borderRadius: BorderRadius.circular(Tokens.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: Container(
          height: Tokens.controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.radiusControl),
            border: Border.all(color: active ? Tokens.accent : Tokens.border),
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: active ? Tokens.accent : Tokens.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
