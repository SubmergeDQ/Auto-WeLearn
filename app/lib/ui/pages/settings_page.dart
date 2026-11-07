import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
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

const String _repoUrl = 'https://github.com/SubmergeDQ/Auto-WeLearn';

Future<void> _openRepo(BuildContext context) async {
  final launched = await launchUrl(
    Uri.parse(_repoUrl),
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
    const about = _AboutGroup();
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
                  onPressed: state.busy
                      ? null
                      : () => openBrowserLogin(context),
                  icon: const Icon(Icons.language_rounded, size: 15),
                  label: Text(state.busy ? '连接中…' : '内置浏览器登录'),
                ),
                OutlinedButton(
                  style: toolbarOutlined(),
                  onPressed: state.busy
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
      ],
    );
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

class _MobileAppGroupState extends State<_MobileAppGroup> {
  BackgroundPermission? _permission;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
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

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final granted = _permission?.notification;
    final wakeLockGranted = _permission?.wakeLock;

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
          description: '通知栏显示「后台运行中」，点通知可回到应用；相当于桌面端的托盘',
          trailing: Switch(
            value: state.persistentNotification,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => state.setBackgroundMode(persistent: v),
          ),
        ),
        SettingRow(
          title: '权限申请',
          description: wakeLockGranted == false
              ? 'Wake Lock 权限未授予，息屏续跑可能失效'
              : (granted == null
                    ? 'Wake Lock 安装时授予；Android 13+ 还要授权通知才能常驻'
                    : (granted ? 'Wake Lock 与通知权限均已授予' : '通知权限未授予，常驻通知不会显示')),
          trailing: TextButton(
            style: toolbarText(),
            onPressed: _requesting ? null : _requestPermission,
            child: Text(
              _requesting ? '申请中…' : (granted == true ? '重新检查' : '申请权限'),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            '锁屏续跑依赖上面两项；长时间挂机还需要到系统设置里把本应用加入电池优化白名单。',
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
  const _AboutGroup();

  @override
  Widget build(BuildContext context) {
    return SettingGroup(
      title: '关于',
      children: [
        const SettingRow(
          title: 'WeLearn 助手',
          description: '1.0.2 · Flutter 桌面 / 安卓双端',
          trailing: Text(
            '本地运行',
            style: TextStyle(fontSize: 11, color: Tokens.textTertiary),
          ),
        ),
        SettingRow(
          title: 'GitHub 仓库',
          description: _repoUrl,
          trailing: TextButton(
            style: toolbarText(),
            onPressed: () => _openRepo(context),
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
