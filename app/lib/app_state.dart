import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/api.dart';
import 'core/auto_login.dart';
import 'core/browser_login.dart';
import 'core/errors.dart';
import 'core/models.dart';
import 'core/runner.dart';
import 'core/session.dart';
import 'core/updater.dart';
import 'mobile_background.dart';

const _defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class LogEntry {
  LogEntry(this.level, this.message, {DateTime? time})
    : time = time ?? DateTime.now();
  final String level; // info | warn | error | beat | done
  final String message;
  final DateTime time;

  String get clock =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'l': level,
    'm': message,
    't': time.toIso8601String(),
  };

  static LogEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final message = raw['m'];
    if (message is! String) return null;
    return LogEntry(
      raw['l'] as String? ?? 'info',
      message,
      time: DateTime.tryParse('${raw['t']}'),
    );
  }
}

/// 已保存的账号。
///
/// 这一轮界面只展示当前账号，但存储按列表设计：以后加多账号切换时不用迁移数据结构。
class SavedAccount {
  const SavedAccount({
    required this.id,
    required this.cookie,
    required this.savedAt,
    this.uid,
    this.username,
    this.password,
  });

  final String id;
  final String cookie;
  final DateTime savedAt;
  final String? uid;

  /// 内置浏览器里输入的账号密码，用于登录失效后自动重登。
  /// 只保存在本机应用数据目录，不会随更新检查或运行请求发送。
  final String? username;
  final String? password;

  bool get hasCredentials =>
      (username?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);

  /// 清掉账号密码，只保留 Cookie / UID（关闭保存登录状态或只保存 Cookie 时用）。
  SavedAccount withoutCredentials() {
    if (username == null && password == null) return this;
    return SavedAccount(id: id, cookie: cookie, savedAt: savedAt, uid: uid);
  }

  SavedAccount copyWith({
    String? cookie,
    DateTime? savedAt,
    String? uid,
    String? username,
    String? password,
  }) => SavedAccount(
    id: id,
    cookie: cookie ?? this.cookie,
    savedAt: savedAt ?? this.savedAt,
    uid: uid ?? this.uid,
    username: username ?? this.username,
    password: password ?? this.password,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'cookie': cookie,
    'savedAt': savedAt.toIso8601String(),
    if (uid != null) 'uid': uid,
    if (username != null) 'username': username,
    if (password != null) 'password': password,
  };

  static SavedAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final cookie = raw['cookie'];
    if (id is! String || cookie is! String) return null;
    return SavedAccount(
      id: id,
      cookie: cookie,
      savedAt: DateTime.tryParse('${raw['savedAt']}') ?? DateTime.now(),
      uid: raw['uid'] is String ? raw['uid'] as String : null,
      username: raw['username'] is String ? raw['username'] as String : null,
      password: raw['password'] is String ? raw['password'] as String : null,
    );
  }
}

/// 全局状态。界面只读这里的数据，写操作都走方法。
class AppState extends ChangeNotifier {
  AppState() {
    _loadPersisted();
  }

  final Session _session = Session(
    baseUrl: 'https://welearn.sflep.com',
    userAgent: _defaultUserAgent,
  );
  late final Api _api = Api(_session);

  // 登录与课程
  bool loggedIn = false;

  /// 启动恢复中：读取本地账号并静默校验登录态。
  ///
  /// 这段时间界面不渲染「未登录」空态——冷启动时磁盘与网络都是异步的，
  /// 先画一帧未登录、再跳到已登录，就会看到明显的闪烁。
  bool restoring = true;

  /// 登录/连接中（登录弹窗用）
  bool busy = false;

  /// 正在扫描课程结构。以前 `loadCourse` 完全不置位，界面上所有
  /// 「正在扫描…」文案实际永远不会出现，按钮也能被反复点。
  bool scanning = false;
  String scanStage = '';

  String? lastError;
  List<Course> courses = const [];
  String? currentCid;

  /// 上次选择/运行的课程，登录后自动回到这门课
  String? lastCid;
  CourseMeta? meta;
  List<CourseUnit> units = const [];
  List<Lesson> lessons = const [];
  String? selectedScoid;

  /// 已勾选要运行的小节（跨筛选保持，重新扫描时重置为全部待处理）
  final Set<String> selectedScoids = <String>{};

  // 运行
  final Map<String, LessonStatus> statuses = {};
  final Map<String, LessonResult> results = {};
  final List<LessonResult> recentResults = [];
  final List<LogEntry> logs = [];
  bool running = false;
  String? currentScoid;
  int currentElapsed = 0;
  int currentWait = 0;
  int currentHeartbeats = 0;

  /// 节间间隔：总秒数与已过秒数。间隔期间 currentScoid 仍是上一节，
  /// 界面改显示这个倒计时，而不是上一节归零后的 0:00。
  int gapTotal = 0;
  int gapElapsed = 0;

  bool get inGap => running && gapTotal > 0;
  int get gapRemain => (gapTotal - gapElapsed).clamp(0, gapTotal);

  DateTime? runStartedAt;
  DateTime? runFinishedAt;

  /// 本次运行的队列规模与已完成数（「第 n/总 节」用）
  int runTotal = 0;
  int runDone = 0;
  CancelToken? _token;
  RunSettings settings = const RunSettings();
  String filter = 'all'; // all | pending | failed
  String query = '';
  int? selectedUnit;

  // 账号（存储按多账号设计，界面这轮只展示当前账号）
  List<SavedAccount> accounts = const [];
  String? activeAccountId;
  DateTime? lastLoginAt;

  /// 上次检查 GitHub 更新的时间，用来做「每天最多自动检查一次」的节流
  DateTime? lastUpdateCheckAt;

  /// 是否把登录 Cookie 保存到本机。默认关闭；开启时由设置页询问是否记录账号密码。
  bool rememberLogin = false;

  /// 是否同时记录内置浏览器的账号密码（用于 Cookie 失效后的后台自动重登）。
  bool savePassword = false;

  /// 按账号 UID 保留的最近一次运行数据（日志、最近完成、小节状态）。
  /// 登录失效或退出登录后不会被清空，同一 UID 再次登录时恢复。
  final Map<String, Map<String, dynamic>> _history = {};

  String? get historyUid => activeAccount?.uid ?? activeAccount?.id;

  /// 正在用保存的账号密码自动重登：未登录页据此显示「正在尝试登录」
  bool autoLoginAttempting = false;

  /// 自动重登时复用当前账号记录，避免新增一条重复账号
  String? _reuseAccountId;
  bool _pendingAutoLogin = false;

  /// 从 WeLearn 学生主页实时拉取的头像字节；拉不到时界面回退文字占位。
  Uint8List? avatarBytes;
  bool avatarLoading = false;

  /// 手机端后台运行开关（桌面端不展示、不生效）
  bool keepAwake = true;
  bool persistentNotification = true;

  /// 桌面侧边栏：宽度可拖拽，点击应用图标可收起成图标栏
  double railWidth = 208;
  bool railCollapsed = false;
  static const minRailWidth = 176.0;
  static const maxRailWidth = 320.0;

  // ── 更新 ─────────────────────────────────────────────
  /// 更新源仓库链接，可在设置里改成任意公开 GitHub 仓库
  String repoUrl = defaultRepoUrl;
  final UpdateService _updater = UpdateService();
  ReleaseInfo? latestRelease;
  bool checkingUpdate = false;
  bool downloadingUpdate = false;
  double updateProgress = 0;
  String? updateError;

  /// 检查到新版本后置位，界面据此弹出「是否更新」询问。
  bool updatePromptPending = false;

  /// 已提示过的版本：同一次会话里每 6 小时的自动检查不会反复弹窗。
  String? _promptedUpdateVersion;

  /// 界面接管弹窗后清除待提示标记。
  void markUpdatePromptShown() {
    updatePromptPending = false;
  }

  bool get hasUpdate {
    final release = latestRelease;
    if (release == null) return false;
    return isNewerVersion(release.version, appVersion);
  }

  /// 通知栏进度推送的节流时间戳：每秒最多同步一次，避免逐 tick 打扰原生
  DateTime _lastTaskPush = DateTime.fromMillisecondsSinceEpoch(0);

  SavedAccount? get activeAccount {
    final id = activeAccountId;
    if (id == null) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  String get _cookie => activeAccount?.cookie ?? '';

  // ── 计算属性 ─────────────────────────────────────────
  Course? get currentCourse {
    final cid = currentCid;
    if (cid == null) return null;
    for (final c in courses) {
      if (c.cid == cid) return c;
    }
    return null;
  }

  List<Lesson> get candidates => lessons.where((l) {
    final st = statusOf(l.scoid);
    return l.visible &&
        (l.complete
            ? false
            : st != LessonStatus.done && st != LessonStatus.skipped);
  }).toList();

  List<Lesson> get visibleLessons {
    final q = query.trim().toLowerCase();
    return lessons.where((l) {
      if (selectedUnit != null && l.unitIndex != selectedUnit) return false;
      if (filter == 'pending' && l.complete) return false;
      if (filter == 'failed' && statusOf(l.scoid) != LessonStatus.failed) {
        return false;
      }
      if (q.isNotEmpty && !l.location.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  /// 可见且可勾选的小节（隐藏小节不参与选择）
  List<Lesson> get selectableLessons =>
      visibleLessons.where((l) => l.visible).toList();

  List<Lesson> selectedLessons() =>
      lessons.where((l) => selectedScoids.contains(l.scoid)).toList();

  int get selectedCount => selectedScoids.length;

  void setUnit(int? index) {
    selectedUnit = index;
    notifyListeners();
  }

  LessonStatus statusOf(String scoid) {
    final st = statuses[scoid];
    if (st != null) return st;
    final lesson = lessons.where((l) => l.scoid == scoid).firstOrNull;
    if (lesson != null && lesson.complete) return LessonStatus.done;
    return LessonStatus.pending;
  }

  int get doneCount =>
      lessons.where((l) => statusOf(l.scoid) == LessonStatus.done).length;
  int get failedCount =>
      lessons.where((l) => statusOf(l.scoid) == LessonStatus.failed).length;
  int get skippedCount =>
      lessons.where((l) => statusOf(l.scoid) == LessonStatus.skipped).length;

  int get queueTotal => candidates.length + doneCount;

  double get progress {
    final total = queueTotal;
    if (total == 0) return 0;
    return (doneCount / total).clamp(0.0, 1.0);
  }

  /// 本次运行的进度（0–1）
  double get runProgress {
    if (runTotal == 0) return 0;
    return (runDone / runTotal).clamp(0.0, 1.0);
  }

  /// 当前节处于哪个阶段：在跑但还没开始计时 = 准备；计时中未到点 = 等待；
  /// 两节之间的间隔单独成阶段，避免界面显示上一节的 0:00。
  String get currentStage {
    if (!running) return 'idle';
    if (inGap) return '间隔';
    if (currentWait == 0) return '准备';
    if (currentElapsed >= currentWait) return '提交';
    return '等待';
  }

  /// 按 [count] 节估算耗时（秒）：平均等待 + 平均节间间隔
  int estimateSeconds(int count) {
    final avgWait = (settings.waitMin + settings.waitMax) ~/ 2;
    final avgGap = (settings.intervalMin + settings.intervalMax) ~/ 2;
    return count * (avgWait + avgGap);
  }

  /// 已选小节还要多久；没勾选时按待处理估算
  int get remainingEstimate =>
      estimateSeconds(selectedCount > 0 ? selectedCount : candidates.length);

  Duration? get lastRunDuration {
    final start = runStartedAt;
    final end = runFinishedAt;
    if (start == null || end == null) return null;
    return end.difference(start);
  }

  void addLog(String level, String message) {
    logs.add(LogEntry(level, message));
    // 保留最近 2000 条：长挂机（75 节 × 多条心跳）不会再让早期日志整段消失
    if (logs.length > 2000) logs.removeRange(0, logs.length - 2000);
    notifyListeners();
  }

  // ── 选择集 ───────────────────────────────────────────
  void toggleSelected(String scoid) {
    if (!selectedScoids.remove(scoid)) selectedScoids.add(scoid);
    notifyListeners();
  }

  void setSelected(String scoid, bool value) {
    if (value) {
      selectedScoids.add(scoid);
    } else {
      selectedScoids.remove(scoid);
    }
    notifyListeners();
  }

  void selectAllVisible() {
    selectedScoids.addAll(selectableLessons.map((l) => l.scoid));
    notifyListeners();
  }

  void selectAllPending() {
    selectedScoids
      ..clear()
      ..addAll(candidates.map((l) => l.scoid));
    notifyListeners();
  }

  void clearSelection() {
    selectedScoids.clear();
    notifyListeners();
  }

  /// 单元组头的三态：全选 / 部分 / 未选
  bool? unitSelection(int unitIndex) {
    final inUnit = lessons
        .where((l) => l.unitIndex == unitIndex && l.visible)
        .toList();
    if (inUnit.isEmpty) return false;
    final picked = inUnit.where((l) => selectedScoids.contains(l.scoid)).length;
    if (picked == 0) return false;
    if (picked == inUnit.length) return true;
    return null;
  }

  void toggleUnit(int unitIndex) {
    final inUnit = lessons
        .where((l) => l.unitIndex == unitIndex && l.visible)
        .toList();
    if (inUnit.isEmpty) return;
    final all = inUnit.every((l) => selectedScoids.contains(l.scoid));
    for (final l in inUnit) {
      if (all) {
        selectedScoids.remove(l.scoid);
      } else {
        selectedScoids.add(l.scoid);
      }
    }
    notifyListeners();
  }

  // ── 持久化 ───────────────────────────────────────────
  Future<void> _loadPersisted() async {
    try {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/app_state.json');
        if (await file.exists()) {
          final data =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;

          rememberLogin = data['rememberLogin'] as bool? ?? false;
          savePassword =
              rememberLogin && (data['savePassword'] as bool? ?? false);
          final historyRaw = data['history'];
          if (historyRaw is Map) {
            for (final entry in historyRaw.entries) {
              final value = entry.value;
              if (value is Map) {
                _history['${entry.key}'] = Map<String, dynamic>.from(value);
              }
            }
          }
          accounts =
              (data['accounts'] as List?)
                  ?.map(SavedAccount.fromJson)
                  .whereType<SavedAccount>()
                  .toList() ??
              const [];
          activeAccountId = data['activeAccountId'] as String?;

          // 关闭「保存登录状态」时磁盘上不应留着 Cookie；
          // 兼容旧版本写下的数据，这里也直接丢掉。
          if (!rememberLogin) {
            accounts = const [];
            activeAccountId = null;
          }

          // 1.1.5 起默认关闭「保存登录状态」：旧版本开启过的用户统一强制关闭，
          // 避免升级后未经重新确认就继续把 Cookie / 账号密码留在磁盘上。
          final storedVersion = (data['version'] as num?)?.toInt() ?? 0;
          if (storedVersion < 3) {
            rememberLogin = false;
            savePassword = false;
            accounts = const [];
            activeAccountId = null;
          }

          // 旧版本只存了一个 cookie 字段，这里迁移成账号列表
          final legacy = data['cookie'] as String?;
          if (rememberLogin &&
              accounts.isEmpty &&
              legacy != null &&
              legacy.isNotEmpty) {
            final acc = SavedAccount(
              id: 'legacy',
              cookie: legacy,
              savedAt: DateTime.now(),
            );
            accounts = [acc];
            activeAccountId = acc.id;
          }

          lastCid = data['lastCid'] as String?;
          closeAction = (data['closeAction'] as String?) ?? 'ask';
          keepAwake = data['keepAwake'] as bool? ?? true;
          persistentNotification =
              data['persistentNotification'] as bool? ?? true;
          repoUrl = data['repoUrl'] as String? ?? defaultRepoUrl;
          railWidth = ((data['railWidth'] as num?)?.toDouble() ?? 208).clamp(
            minRailWidth,
            maxRailWidth,
          );
          railCollapsed = data['railCollapsed'] as bool? ?? false;
          lastLoginAt = DateTime.tryParse('${data['lastLoginAt']}');
          lastUpdateCheckAt = DateTime.tryParse(
            '${data['lastUpdateCheckAt']}',
          );
          final s = data['settings'];
          if (s is Map<String, dynamic>) settings = RunSettings.fromJson(s);
          notifyListeners();
          // 迁移后立即写回磁盘，避免每次都按旧数据重新判定
          if (storedVersion < 3) unawaited(_persist());
        }
      } catch (_) {
        // 首次启动或缓存损坏，忽略；仍按默认值恢复后台模式
      }

      // 无论有没有缓存文件，都要把当前开关同步给原生服务：
      // 首次安装时两个开关默认打开，若只靠「有缓存才 apply」，
      // 界面显示已开启但 Wake Lock / 常驻通知实际没启动。
      unawaited(
        MobileBackground.apply(
          keepAwake: keepAwake,
          persistent: persistentNotification,
        ),
      );

      final cookie = _cookie;
      if (rememberLogin && cookie.isNotEmpty) {
        // 只等会话校验，课程扫描交给页面里的扫描横幅，避免占位页停留过久
        await login(cookie, silent: true, awaitCourse: false);
      }
    } finally {
      // 无论恢复成功与否都要退出占位：静默登录失败时才会显示真正的未登录空态
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/app_state.json');
      await file.writeAsString(
        jsonEncode({
          'version': 3,
          // 关闭「保存登录状态」时磁盘上不留 Cookie，但本次会话仍保持登录
          'accounts': rememberLogin
              ? accounts.map((a) => a.toJson()).toList()
              : <dynamic>[],
          if (rememberLogin && activeAccountId != null)
            'activeAccountId': activeAccountId,
          'settings': settings.toJson(),
          if (lastCid != null) 'lastCid': lastCid,
          'closeAction': closeAction,
          'keepAwake': keepAwake,
          'persistentNotification': persistentNotification,
          'repoUrl': repoUrl,
          'rememberLogin': rememberLogin,
          'savePassword': savePassword,
          'history': _history,
          'railWidth': railWidth,
          'railCollapsed': railCollapsed,
          if (lastLoginAt != null)
            'lastLoginAt': lastLoginAt!.toIso8601String(),
          if (lastUpdateCheckAt != null)
            'lastUpdateCheckAt': lastUpdateCheckAt!.toIso8601String(),
        }),
      );
    } catch (_) {
      // 写盘失败不影响使用
    }
  }

  /// 把当前账号的日志、最近完成、小节状态存进历史。
  ///
  /// 键优先用平台 UID：登录失效、换 Cookie 重新登录后仍能找回同一账号的数据。
  /// 同一 UID 只保留最近一次运行。
  void _saveHistory({bool persist = true}) {
    final uid = historyUid;
    if (uid == null) return;
    if (logs.isEmpty && recentResults.isEmpty && statuses.isEmpty) return;
    _history[uid] = {
      'savedAt': DateTime.now().toIso8601String(),
      'logs': [for (final e in logs) e.toJson()],
      'recentResults': [for (final r in recentResults) r.toJson()],
      'statuses': statuses.map((k, v) => MapEntry(k, v.name)),
      'runDone': runDone,
      'runTotal': runTotal,
      if (runStartedAt != null) 'runStartedAt': runStartedAt!.toIso8601String(),
      if (runFinishedAt != null)
        'runFinishedAt': runFinishedAt!.toIso8601String(),
    };
    if (persist) unawaited(_persist());
  }

  /// 登录并扫描完成后恢复该 UID 的历史；只补空缺，不覆盖本次新产生的记录。
  void _restoreHistory(String uid) {
    final raw = _history[uid];
    if (raw == null) return;

    final restoredLogs = <LogEntry>[];
    final rawLogs = raw['logs'];
    if (rawLogs is List) {
      for (final item in rawLogs) {
        final entry = LogEntry.fromJson(item);
        if (entry != null) restoredLogs.add(entry);
      }
    }
    if (restoredLogs.isNotEmpty) {
      logs.insertAll(0, restoredLogs);
      if (logs.length > 2000) logs.removeRange(0, logs.length - 2000);
    }

    final rawResults = raw['recentResults'];
    if (recentResults.isEmpty && rawResults is List) {
      for (final item in rawResults) {
        final result = LessonResult.fromJson(item);
        if (result == null) continue;
        recentResults.add(result);
        results.putIfAbsent(result.scoid, () => result);
      }
      if (recentResults.length > 12) {
        recentResults.removeRange(12, recentResults.length);
      }
    }

    final rawStatuses = raw['statuses'];
    if (rawStatuses is Map) {
      for (final entry in rawStatuses.entries) {
        final name = '${entry.value}';
        final status = LessonStatus.values
            .where((s) => s.name == name)
            .firstOrNull;
        if (status != null) statuses.putIfAbsent('${entry.key}', () => status);
      }
    }

    runDone = (raw['runDone'] as num?)?.toInt() ?? runDone;
    runTotal = (raw['runTotal'] as num?)?.toInt() ?? runTotal;
    runStartedAt ??= DateTime.tryParse('${raw['runStartedAt']}');
    runFinishedAt ??= DateTime.tryParse('${raw['runFinishedAt']}');
    notifyListeners();
  }

  /// 关闭窗口时的行为：ask（每次询问）/ tray（最小化到托盘）/ quit（直接退出）
  String closeAction = 'ask';

  /// 记住关闭方式（桌面端托盘用）
  Future<void> setCloseAction(String value) async {
    closeAction = value;
    notifyListeners();
    await _persist();
  }

  Future<void> saveSettings(RunSettings next) async {
    settings = next;
    notifyListeners();
    await _persist();
  }

  /// 手机端「保持后台运行 / 任务栏常驻」的开关：记住选择并同步给原生服务。
  Future<void> setBackgroundMode({bool? keepAwake, bool? persistent}) async {
    if (keepAwake != null) this.keepAwake = keepAwake;
    if (persistent != null) persistentNotification = persistent;
    notifyListeners();
    await _persist();
    await MobileBackground.apply(
      keepAwake: this.keepAwake,
      persistent: persistentNotification,
    );
  }

  // ── 侧边栏 ───────────────────────────────────────────
  /// 拖拽时只更新内存与界面，松手后再写盘（[commitRailWidth]）。
  void setRailWidth(double value) {
    final next = value.clamp(minRailWidth, maxRailWidth);
    if (next == railWidth) return;
    railWidth = next;
    notifyListeners();
  }

  void toggleRailCollapsed() {
    railCollapsed = !railCollapsed;
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> commitRailWidth() => _persist();

  // ── 更新 ─────────────────────────────────────────────
  /// 检查 GitHub Releases 上的最新版本。
  ///
  /// [silent] 为 true 时用于后台检查：失败不写错误提示，避免离线启动时
  /// 设置页一直挂着一条红色失败信息。
  Future<void> checkForUpdate({bool silent = false}) async {
    if (checkingUpdate) return;
    checkingUpdate = true;
    updateError = null;
    notifyListeners();
    try {
      final release = await _updater.fetchLatest(repoUrl);
      latestRelease = release;
      // 发现新版本时让界面弹一次询问；同一版本拒绝后本次会话不再重复打扰
      if (isNewerVersion(release.version, appVersion) &&
          release.version != _promptedUpdateVersion) {
        _promptedUpdateVersion = release.version;
        updatePromptPending = true;
      }
      if (!silent) {
        addLog(
          'info',
          isNewerVersion(release.version, appVersion)
              ? '发现新版本 ${release.version}（当前 $appVersion）'
              : '已是最新版本 $appVersion',
        );
      }
    } on UpdateException catch (e) {
      if (!silent) {
        updateError = e.message;
        addLog('warn', '检查更新失败：${e.message}');
      }
    } catch (e) {
      if (!silent) {
        updateError = '检查更新失败：$e';
        addLog('warn', updateError!);
      }
    } finally {
      checkingUpdate = false;
      // 失败也记一次时间：离线时不会每次启动都重发请求
      lastUpdateCheckAt = DateTime.now();
      unawaited(_persist());
      notifyListeners();
    }
  }

  /// 每天最多自动检查一次更新。
  ///
  /// 启动时调用一次，另外由运行期间每 6 小时的定时器兜底，
  /// 保证长时间挂机的用户跨天也能收到版本提示。
  Future<void> autoCheckForUpdate() async {
    final last = lastUpdateCheckAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 24)) {
      return;
    }
    await checkForUpdate(silent: true);
  }

  /// 下载当前平台对应的更新包，返回本地路径；失败时把原因写进 [updateError]。
  Future<String?> downloadUpdate() async {
    final release = latestRelease;
    if (release == null) {
      updateError = '还没有检查到可用版本，先点「检查更新」';
      notifyListeners();
      return null;
    }
    final target = Platform.isWindows
        ? UpdateTarget.windows
        : UpdateTarget.android;
    final asset = selectUpdateAsset(release, target);
    if (asset == null) {
      updateError = Platform.isWindows
          ? '这个 Release 里没有 Windows 安装包'
          : '这个 Release 里没有 APK';
      notifyListeners();
      return null;
    }

    downloadingUpdate = true;
    updateProgress = 0;
    updateError = null;
    _pushDownloadProgress(0);
    notifyListeners();
    try {
      final file = await _updater.downloadAsset(
        asset,
        onProgress: (received, total) {
          final next = total <= 0
              ? 0.0
              : (received / total).clamp(0.0, 1.0).toDouble();
          // 每 1% 才刷新一次，避免整页随下载字节数反复重建
          if (next >= 1.0 || next - updateProgress >= 0.01) {
            updateProgress = next;
            _pushDownloadProgress(next);
            notifyListeners();
          }
        },
      );
      addLog('info', '更新包已下载：${file.path}');
      return file.path;
    } on UpdateException catch (e) {
      updateError = e.message;
      addLog('warn', '下载更新失败：${e.message}');
      return null;
    } catch (e) {
      updateError = '下载更新失败：$e';
      addLog('warn', updateError!);
      return null;
    } finally {
      _pushDownloadProgress(0, active: false);
      downloadingUpdate = false;
      notifyListeners();
    }
  }

  /// 把更新下载进度同步到安卓通知栏 / Windows 任务栏进度。
  void _pushDownloadProgress(double progress, {bool active = true}) {
    if (MobileBackground.supported) {
      unawaited(
        MobileBackground.updateDownload(
          active: active,
          progress: progress.clamp(0.0, 1.0).toDouble(),
        ),
      );
      return;
    }
    if (!Platform.isWindows) return;
    try {
      unawaited(windowManager.setProgressBar(active ? progress : -1));
    } catch (_) {
      // 窗口尚未初始化或插件不可用时忽略
    }
  }

  /// 安装已下载的更新包。
  ///
  /// Windows：启动 NSIS 安装程序（安装版带 `/S` 静默安装），随后退出进程，
  /// 让安装程序覆盖正在运行的 exe；Android：交给系统安装器。
  Future<bool> installUpdate(String path) async {
    if (Platform.isWindows) {
      if (!path.toLowerCase().endsWith('.exe')) {
        await Process.start('explorer.exe', [
          '/select,',
          path,
        ], mode: ProcessStartMode.detached);
        updateError = '已下载便携包，请在文件管理器中解压后覆盖安装目录';
        notifyListeners();
        return false;
      }
      await Process.start(path, ['/S'], mode: ProcessStartMode.detached);
      addLog('info', '安装程序已启动，应用将在 1 秒内退出并完成更新');
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 1));
      exit(0);
    }

    if (Platform.isAndroid) {
      final outcome = await MobileBackground.installApk(path);
      switch (outcome) {
        case ApkInstallOutcome.started:
          addLog('info', '已打开系统安装器，按提示完成安装');
          notifyListeners();
          return true;
        case ApkInstallOutcome.permissionRequired:
          updateError = '请允许「安装未知应用」后再次点击安装';
          addLog('warn', updateError!);
          notifyListeners();
          return false;
        case ApkInstallOutcome.failed:
          updateError = '无法启动系统安装器，请到文件管理器手动安装下载的 APK';
          addLog('warn', updateError!);
          notifyListeners();
          return false;
      }
    }
    return false;
  }

  /// 把当前运行进度同步到安卓常驻通知（桌面端直接返回）。
  void _pushMobileTask({bool force = false}) {
    if (!MobileBackground.supported) return;
    if (running) {
      if (!force &&
          DateTime.now().difference(_lastTaskPush) <
              const Duration(seconds: 1)) {
        return;
      }
      _lastTaskPush = DateTime.now();
      final lesson = currentScoid == null
          ? null
          : lessons.where((l) => l.scoid == currentScoid).firstOrNull;
      final current = (runDone + 1).clamp(1, runTotal <= 0 ? 1 : runTotal);
      final remain = inGap
          ? gapRemain
          : (currentWait <= 0
              ? 0
              : (currentWait - currentElapsed).clamp(0, currentWait));
      unawaited(
        MobileBackground.updateTask(
          running: true,
          current: current,
          total: runTotal,
          text: inGap
              ? '第 $current/$runTotal 节 · 等待进入下一节'
              : (lesson == null
                  ? '正在运行'
                  : '第 $current/$runTotal 节 · ${shortLocation(lesson)}'),
          detail: inGap
              ? '间隔 ${_mmss(gapRemain)} 后继续'
              : '$currentStage · 本节剩余 ${_mmss(remain)} · 心跳 $currentHeartbeats 次',
        ),
      );
    } else {
      _lastTaskPush = DateTime.fromMillisecondsSinceEpoch(0);
      unawaited(
        MobileBackground.updateTask(
          running: false,
          current: runDone,
          total: runTotal,
          text: runTotal > 0 ? '上次运行 $runDone/$runTotal 节' : '任务未运行',
          detail: '点通知里的「开始」运行任务页已选小节',
        ),
      );
    }
  }

  /// 秒数 → `mm:ss`（通知栏用，不依赖界面层的格式化函数）
  String _mmss(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 重新拉一次账号头像。网络失败时静默回退到文字占位，不影响登录态。
  Future<void> refreshAvatar() async {
    if (!loggedIn || avatarLoading) return;
    avatarLoading = true;
    notifyListeners();
    try {
      avatarBytes = await _api.fetchAvatar();
    } catch (_) {
      avatarBytes = null;
    } finally {
      avatarLoading = false;
      notifyListeners();
    }
  }

  void _rememberAccount(String cookieText) {
    // 自动重登：沿用当前账号的 UID / 账号密码，只换新 Cookie
    final reuseId = _reuseAccountId;
    if (reuseId != null) {
      final index = accounts.indexWhere((a) => a.id == reuseId);
      if (index >= 0) {
        accounts = [
          for (final a in accounts)
            if (a.id == reuseId)
              a.copyWith(cookie: cookieText, savedAt: DateTime.now())
            else
              a,
        ];
        activeAccountId = reuseId;
        return;
      }
    }

    final idx = accounts.indexWhere((a) => a.cookie == cookieText);
    if (idx >= 0) {
      activeAccountId = accounts[idx].id;
      return;
    }
    final acc = SavedAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      cookie: cookieText,
      savedAt: DateTime.now(),
    );
    accounts = [...accounts, acc];
    activeAccountId = acc.id;
  }

  void _rememberUid(String uid) {
    final acc = activeAccount;
    if (acc == null || acc.uid == uid) return;
    // 首次登录时历史键是账号 id，拿到 UID 后迁移过去，保证下次按 UID 恢复
    final legacyHistory = _history.remove(acc.id);
    if (legacyHistory != null) {
      _history.putIfAbsent(uid, () => legacyHistory);
    }
    accounts = [
      for (final a in accounts)
        if (a.id == acc.id) a.copyWith(uid: uid) else a,
    ];
    unawaited(_persist());
  }

  // ── 登录 ─────────────────────────────────────────────
  /// 切换「保存登录状态」。
  ///
  /// [savePassword] 由设置页的询问结果决定：true 时保留/允许记录账号密码，
  /// 用于 Cookie 失效后的自动重登；false 时只保存 Cookie 并清掉账号密码。
  Future<void> setRememberLogin(
    bool value, {
    bool savePassword = false,
  }) async {
    rememberLogin = value;
    this.savePassword = value && savePassword;
    if (!value || !savePassword) {
      accounts = [for (final a in accounts) a.withoutCredentials()];
    }
    notifyListeners();
    await _persist();
  }

  /// 保存内置浏览器里输入过的账号密码，供 Cookie 失效后自动重登。
  Future<void> saveCredentials(String username, String password) async {
    if (!rememberLogin || !savePassword) return;
    final acc = activeAccount;
    if (acc == null) return;
    if (acc.username == username && acc.password == password) return;
    accounts = [
      for (final a in accounts)
        if (a.id == acc.id)
          a.copyWith(username: username, password: password)
        else
          a,
    ];
    notifyListeners();
    await _persist();
  }

  /// 用保存的账号密码自动重登（纯后台 HTTP，不打开任何界面）。
  ///
  /// 只在现有 Cookie 被平台明确判定失效后调用：Cookie 有效时始终先用 Cookie，
  /// 避免每次启动都做一次密码登录而触发平台风控。
  Future<void> _attemptAutoLogin() async {
    if (autoLoginAttempting || !rememberLogin) return;
    final acc = activeAccount;
    if (acc == null || !acc.hasCredentials) return;

    autoLoginAttempting = true;
    lastError = '登录信息已失效，正在后台自动重登…';
    notifyListeners();
    try {
      final cookie = await AutoLoginService().login(
        acc.username!,
        acc.password!,
      );
      if (cookie != null && cookie.isNotEmpty) {
        // 复用当前账号记录，保留 UID 与账号密码，不新增重复账号
        _reuseAccountId = acc.id;
        final ok = await login(cookie, silent: true, awaitCourse: false);
        if (ok) {
          lastError = null;
          addLog('info', '已使用保存的账号密码恢复登录');
        }
      } else {
        lastError = '自动重登失败，请手动登录';
        addLog('warn', lastError!);
      }
    } catch (e) {
      lastError = '自动重登失败：$e';
      addLog('warn', lastError!);
    } finally {
      _reuseAccountId = null;
      autoLoginAttempting = false;
      notifyListeners();
    }
  }

  /// [awaitCourse] 为 false 时，登录校验成功后立刻返回，课程扫描放到后台，
  /// 界面可以马上退出「启动恢复」占位并显示扫描进度横幅。
  Future<bool> login(
    String cookieText, {
    bool silent = false,
    bool awaitCourse = true,
  }) async {
    if (busy) return false;
    busy = true;
    lastError = null;
    if (!silent) notifyListeners();

    try {
      final pairs = {
        for (final p in parseCookieInput(cookieText)) p.key: p.value,
      };
      _session.setCookies(pairs);
      final list = await _api.listCourses();
      courses = list;
      loggedIn = true;
      _rememberAccount(cookieText);
      lastLoginAt = DateTime.now();
      addLog('info', '登录成功，共 ${list.length} 门课程');
      await _persist();
      // 头像不参与登录判定，异步刷新，失败也不影响已登录状态
      unawaited(refreshAvatar());

      if (currentCid == null && list.isNotEmpty) {
        // 优先回到上次跑的那门课；找不到（换号/课程被移除）再退回第一门
        final preferred = list.any((c) => c.cid == lastCid)
            ? lastCid!
            : list.first.cid;
        if (awaitCourse) {
          await loadCourse(preferred);
        } else {
          unawaited(loadCourse(preferred));
        }
      }
      return true;
    } on AppException catch (e) {
      loggedIn = false;
      if (silent) {
        // 启动恢复：只有服务端明确判定凭据失效才提示重新登录；
        // 网络/代理问题保留保存的 Cookie，下次启动继续尝试。
        if (e.isAuthExpired) {
          final saved = activeAccount;
          if (saved != null && saved.hasCredentials) {
            lastError = '登录信息已失效，正在尝试使用保存的账号密码自动登录…';
            _pendingAutoLogin = true;
          } else {
            lastError = '保存的登录信息已失效，请重新登录';
          }
        } else {
          lastError = '暂时无法恢复登录：${e.message}';
        }
        addLog('warn', lastError!);
      } else {
        lastError = e.message;
        addLog('error', e.message);
      }
      return false;
    } finally {
      busy = false;
      notifyListeners();
      // 等 busy 复位后再自动重登，否则内部的 login 会被 busy 挡住
      if (_pendingAutoLogin) {
        _pendingAutoLogin = false;
        unawaited(_attemptAutoLogin());
      }
    }
  }

  void _stopSessionRun() {
    if (running) {
      _token?.cancel();
      _token = null;
      running = false;
    }
  }

  /// 清空会话相关的界面数据；账号列表由调用方决定保留还是全部删除。
  void _resetSessionView() {
    lastLoginAt = null;
    loggedIn = false;
    busy = false;
    avatarBytes = null;
    avatarLoading = false;
    lastError = null;
    courses = const [];
    units = const [];
    lessons = const [];
    selectedScoids.clear();
    currentCid = null;
    meta = null;
    selectedScoid = null;
    selectedUnit = null;
    currentScoid = null;
    currentElapsed = 0;
    currentWait = 0;
    currentHeartbeats = 0;
    gapTotal = 0;
    gapElapsed = 0;
    recentResults.clear();
    runTotal = 0;
    runDone = 0;
    statuses.clear();
    results.clear();
    filter = 'all';
    query = '';
  }

  /// 退出登录：停掉运行、清空会话与课程数据，并抹掉当前账号保存的 Cookie。
  /// 运行设置（等待时长、正确率等）保留，重新登录后不用再调一遍。
  Future<void> logout() async {
    _stopSessionRun();
    // 先按 UID 存好本次运行数据，再清账号；下次同 UID 登录会自动恢复
    _saveHistory();
    _session.clearCookies();
    // 顺带清掉内置浏览器里的会话，避免下次打开登录页时又被旧 Cookie 自动带走
    await clearBrowserSession();
    final id = activeAccountId;
    if (id != null) {
      accounts = accounts.where((a) => a.id != id).toList();
    }
    activeAccountId = null;
    _resetSessionView();
    addLog('info', '已退出登录，本地保存的 Cookie 已清除');
    notifyListeners();
    await _persist();
  }

  /// 强制清除：不依赖登录态，把本机保存的所有账号 Cookie 一并清掉。
  /// 登录过期但账号记录还在时，普通「退出登录」入口不显示，这个入口兜底。
  Future<void> forceClearCredentials() async {
    _stopSessionRun();
    // 历史记录只含日志与运行结果，不含凭据；先留存，登录失效也不丢数据
    _saveHistory();
    _session.clearCookies();
    // 内置浏览器的 Cookie / 缓存 / 本地存储一起清，登录态失效后残留的
    // WebView 会话会让内置浏览器一打开就自动跳回学生主页。
    await clearBrowserSession();
    accounts = const [];
    activeAccountId = null;
    _resetSessionView();
    addLog('warn', '已强制清除本机会话凭据与内置浏览器数据');
    notifyListeners();
    await _persist();
  }

  /// 只清日志与本次运行结果，保留登录态。
  ///
  /// 同时丢掉该账号的历史快照，否则重新登录或下次启动会把它们恢复回来。
  void clearLogs() {
    logs.clear();
    recentResults.clear();
    final uid = historyUid;
    if (uid != null) _history.remove(uid);
    notifyListeners();
    unawaited(_persist());
  }

  // ── 课程与扫描 ───────────────────────────────────────
  Future<void> loadCourse(String cid, {bool rescan = true}) async {
    // 一次扫描要逐单元请求平台，慢的时候很容易被误以为没点上而重复触发。
    // 状态置位 + 按钮禁用 + 页面上的动画，三处一起防重复。
    if (scanning) {
      addLog('warn', '正在扫描，等这一轮完成再试');
      return;
    }
    scanning = rescan;
    scanStage = rescan ? '正在读取课程信息…' : '';
    currentCid = cid;
    lastCid = cid;
    units = const [];
    lessons = const [];
    selectedScoids.clear();
    statuses.clear();
    results.clear();
    notifyListeners();
    unawaited(_persist());

    try {
      final m = await _api.getCourseMeta(cid);
      meta = m;
      _rememberUid(m.uid);
      // 同一 UID 上次的日志、最近完成与状态在这里接回来；
      // 即使这次是登录失效后重新登录，数据也不会凭空消失。
      _restoreHistory(m.uid);
      if (rescan) {
        scanStage = '正在读取单元与小节…';
        notifyListeners();
        addLog('info', '正在扫描课程结构…');
        final scan = await scanCourse(
          _api,
          meta: m,
          skipOralLesson: settings.skipOralLesson,
          onLog: (msg) {
            scanStage = msg;
            addLog('info', msg);
          },
        );
        units = scan.units;
        lessons = scan.lessons;
        // 默认全选待处理：延续"点开始就跑"的习惯，不想跑的点全不选即可
        selectedScoids
          ..clear()
          ..addAll(scan.candidates.map((l) => l.scoid));
        for (final w in scan.warnings) {
          addLog('warn', w);
        }
        addLog(
          'info',
          '扫描完成：${scan.units.length} 单元 / ${scan.lessons.length} 小节 / 待处理 ${scan.candidates.length}',
        );
      }
    } on AppException catch (e) {
      lastError = e.message;
      addLog('error', e.message);
    } finally {
      scanning = false;
      scanStage = '';
      notifyListeners();
    }
  }

  // ── 运行 ─────────────────────────────────────────────
  /// 本次要跑的队列：默认用勾选集；传 [only] 时只跑这一节（可重跑已完成的节）。
  List<Lesson> runQueue({Lesson? only}) =>
      only != null ? <Lesson>[only] : selectedLessons();

  void startRun({Lesson? only}) {
    if (running) return;
    final m = meta;
    if (m == null) {
      addLog('warn', '还没有扫描完成，先重新扫描');
      return;
    }

    final queue = runQueue(only: only);
    if (queue.isEmpty) {
      addLog('warn', '没有勾选的小节，先在任务页选中要跑的节');
      return;
    }

    running = true;
    runTotal = queue.length;
    runDone = 0;
    runStartedAt = DateTime.now();
    runFinishedAt = null;
    _token = CancelToken();
    notifyListeners();
    addLog(
      'info',
      only == null ? '开始运行 ${queue.length} 节' : '只运行本节：${shortLocation(only)}',
    );
    _pushMobileTask(force: true);
    unawaited(_loop(m, queue));
  }

  Future<void> _loop(CourseMeta m, List<Lesson> queue) async {
    final rng = Random();
    final token = _token!;
    try {
      for (var i = 0; i < queue.length; i++) {
        if (token.isCancelled) break;
        final lesson = queue[i];
        currentScoid = lesson.scoid;
        currentElapsed = 0;
        currentHeartbeats = 0;
        currentWait = pickWait(settings.waitMin, settings.waitMax, rng);
        statuses[lesson.scoid] = LessonStatus.running;
        final crate = pickCrate(settings.rateMin, settings.rateMax, rng);
        addLog(
          'info',
          '[${i + 1}/${queue.length}] ${shortLocation(lesson)}  rate=$crate%',
        );
        notifyListeners();
        _pushMobileTask(force: true);

        final result = await runLesson(
          api: _api,
          meta: m,
          lesson: lesson,
          crate: crate,
          waitSec: currentWait,
          settings: settings,
          token: token,
          random: rng,
          onLog: (level, message) => addLog(level, message),
          onTick: (elapsed, beats) {
            currentElapsed = elapsed;
            currentHeartbeats = beats;
            notifyListeners();
            _pushMobileTask();
          },
        );

        results[lesson.scoid] = result;
        statuses[lesson.scoid] = result.status;
        recentResults.insert(0, result);
        if (recentResults.length > 12) recentResults.removeLast();
        runDone++;
        // 跑完就不再保持在勾选里，避免下次点开始重复提交
        if (result.status == LessonStatus.done ||
            result.status == LessonStatus.skipped) {
          selectedScoids.remove(lesson.scoid);
        }
        addLog(
          result.status == LessonStatus.done
              ? 'done'
              : (result.status == LessonStatus.partial ? 'warn' : 'error'),
          '${result.status.label}  题 ${result.stat.answered}/${result.stat.questions}  '
          '用时 ${result.waitSec}s  心跳 ${result.heartbeats} 次'
          '${result.errorMessage != null ? '  ${result.errorMessage}' : ''}',
        );
        // 每节结束落盘一次：登录突然失效或应用被关闭时，已跑完的记录不会丢
        _saveHistory();
        notifyListeners();

        if (result.status == LessonStatus.interrupted) break;

        if (i < queue.length - 1) {
          final gap = pickInterval(
            settings.intervalMin,
            settings.intervalMax,
            rng,
          );
          // 逐秒计时，让运行卡在间隔阶段显示「距离下一节 mm:ss」，
          // 而不是停留在上一节已经归零的倒计时上。
          gapTotal = gap.round();
          gapElapsed = 0;
          if (gapTotal > 0) {
            addLog('info', '间隔 ${gapTotal}s 后进入下一节');
            notifyListeners();
            _pushMobileTask(force: true);
            while (gapElapsed < gapTotal) {
              await sleepInterruptible(
                const Duration(seconds: 1),
                token,
                step: const Duration(milliseconds: 250),
              );
              gapElapsed++;
              notifyListeners();
              _pushMobileTask();
            }
          }
          gapTotal = 0;
          gapElapsed = 0;
          notifyListeners();
        }
      }
    } on AppException catch (e) {
      addLog('error', e.message);
      if (e.isAuthExpired) {
        loggedIn = false;
        final saved = activeAccount;
        if (saved != null && saved.hasCredentials) {
          lastError = '登录已失效，正在尝试使用保存的账号密码自动登录…';
          _pendingAutoLogin = true;
        } else {
          lastError = '登录已失效，请重新登录';
        }
        notifyListeners();
      }
    } catch (e) {
      addLog('error', '运行异常：$e');
    } finally {
      running = false;
      currentScoid = null;
      currentElapsed = 0;
      gapTotal = 0;
      gapElapsed = 0;
      runFinishedAt = DateTime.now();
      _saveHistory();
      _token = null;
      notifyListeners();
      _pushMobileTask(force: true);
      addLog('info', '本次运行结束');
      if (_pendingAutoLogin) {
        _pendingAutoLogin = false;
        unawaited(_attemptAutoLogin());
      }
    }
  }

  void stopRun() {
    _token?.cancel();
    addLog('warn', '正在停止，当前节不会提交');
    notifyListeners();
  }

  void select(String scoid) {
    selectedScoid = scoid;
    notifyListeners();
  }

  void setFilter(String f) {
    filter = f;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  Lesson? get selectedLesson {
    final scoid = selectedScoid;
    if (scoid == null) return null;
    return lessons.where((l) => l.scoid == scoid).firstOrNull;
  }
}

/// 小节完整位置，统一平台的前缀写法：`U01 > xxx` / `Unit 01 > xxx`
/// / `第 3 单元 > xxx` 都显示为 `Unit N > xxx`。
/// 前缀交给 [parseUnitNumber]，和单元标题共用一套编号规则；解析不出时保留原文。
String displayLocation(Lesson lesson) {
  final raw = lesson.location.trim();
  final separator = raw.indexOf('>');
  if (separator <= 0) return raw;
  final number = parseUnitNumber(raw.substring(0, separator));
  final rest = raw.substring(separator + 1).trim();
  if (number == null || rest.isEmpty) return raw;
  return 'Unit $number > $rest';
}

/// 列表里只显示小节的短名：去掉已经由单元分组头表达的 `Unit N >` 前缀。
/// 先用 [displayLocation] 归一化，`U01 >` 这类写法也不会漏掉。
String shortLocation(Lesson lesson) =>
    displayLocation(lesson)
        .replaceFirst(RegExp(r'^Unit\s+\d+\s*>\s*', caseSensitive: false), '');

/// Cookie 解析：支持 `a=1; b=2` 与 EditThisCookie JSON 数组
List<MapEntry<String, String>> parseCookieInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) throw AppException(AppErrorCode.config, 'Cookie 为空');

  final pairs = <MapEntry<String, String>>[];
  if (text.startsWith('[')) {
    final list = jsonDecode(text);
    if (list is! List) {
      throw AppException(AppErrorCode.config, 'Cookie JSON 必须是数组');
    }
    for (final item in list) {
      if (item is Map && item['name'] is String && item['value'] is String) {
        pairs.add(MapEntry(item['name'] as String, item['value'] as String));
      }
    }
  } else if (text.startsWith('{')) {
    throw AppException(
      AppErrorCode.config,
      'Cookie JSON 必须是数组（EditThisCookie 导出格式）',
    );
  } else {
    for (final segment in text.split(';')) {
      final part = segment.trim();
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      pairs.add(
        MapEntry(part.substring(0, eq).trim(), part.substring(eq + 1).trim()),
      );
    }
  }

  if (pairs.isEmpty) {
    throw AppException(AppErrorCode.config, '无法从输入中解析出任何 Cookie');
  }
  return pairs;
}
