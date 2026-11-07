import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'core/api.dart';
import 'core/errors.dart';
import 'core/models.dart';
import 'core/runner.dart';
import 'core/session.dart';

const _defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class LogEntry {
  LogEntry(this.level, this.message) : time = DateTime.now();
  final String level; // info | warn | error | beat | done
  final String message;
  final DateTime time;

  String get clock =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
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
  bool busy = false;
  String? lastError;
  List<Course> courses = const [];
  String? currentCid;

  /// 上次选择/运行的课程，登录后自动回到这门课
  String? lastCid;
  CourseMeta? meta;
  List<CourseUnit> units = const [];
  List<Lesson> lessons = const [];
  String? selectedScoid;

  // 运行
  final Map<String, LessonStatus> statuses = {};
  final Map<String, LessonResult> results = {};
  final List<LogEntry> logs = [];
  bool running = false;
  String? currentScoid;
  int currentElapsed = 0;
  int currentWait = 0;
  int currentHeartbeats = 0;

  /// 本次运行的队列规模与已完成数（移动端「第 n/总 节」用）
  int runTotal = 0;
  int runDone = 0;
  CancelToken? _token;
  RunSettings settings = const RunSettings();
  String filter = 'all'; // all | pending | failed
  String query = '';
  int? selectedUnit;

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

  /// 剩余时间估算（秒）
  int get remainingEstimate {
    final left = candidates.length;
    final avgWait = (settings.waitMin + settings.waitMax) ~/ 2;
    return left * (avgWait + settings.intervalMin);
  }

  void addLog(String level, String message) {
    logs.add(LogEntry(level, message));
    if (logs.length > 400) logs.removeRange(0, logs.length - 400);
    notifyListeners();
  }

  // ── 持久化 ───────────────────────────────────────────
  Future<void> _loadPersisted() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/app_state.json');
      if (!await file.exists()) return;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final cookie = data['cookie'] as String?;
      lastCid = data['lastCid'] as String?;
      final s = data['settings'];
      if (s is Map<String, dynamic>) settings = RunSettings.fromJson(s);
      notifyListeners();
      if (cookie != null && cookie.isNotEmpty) {
        await login(cookie, silent: true);
      }
    } catch (_) {
      // 首次启动或缓存损坏，忽略
    }
  }

  Future<void> _persist(String cookie) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/app_state.json');
      await file.writeAsString(
        jsonEncode({
          'cookie': cookie,
          'settings': settings.toJson(),
          if (lastCid != null) 'lastCid': lastCid,
        }),
      );
    } catch (_) {
      // 写盘失败不影响使用
    }
  }

  Future<void> saveSettings(RunSettings next, {String? cookie}) async {
    settings = next;
    notifyListeners();
    await _persist(cookie ?? _cookie);
  }

  String _cookie = '';

  // ── 登录 ─────────────────────────────────────────────
  Future<bool> login(String cookieText, {bool silent = false}) async {
    if (busy) return false;
    busy = true;
    lastError = null;
    if (!silent) notifyListeners();

    try {
      final pairs = {
        for (final p in parseCookieInput(cookieText)) p.key: p.value,
      };
      _session.setCookies(pairs);
      _cookie = cookieText;
      final list = await _api.listCourses();
      courses = list;
      loggedIn = true;
      addLog('info', '登录成功，共 ${list.length} 门课程');
      await _persist(cookieText);

      if (currentCid == null && list.isNotEmpty) {
        // 优先回到上次跑的那门课；找不到（换号/课程被移除）再退回第一门
        final preferred = list.any((c) => c.cid == lastCid) ? lastCid! : list.first.cid;
        await loadCourse(preferred);
      }
      return true;
    } on AppException catch (e) {
      loggedIn = false;
      lastError = e.message;
      addLog('error', e.message);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 退出登录：停掉运行、清空会话与课程数据，并抹掉本地保存的 Cookie。
  /// 运行设置（等待时长、正确率等）保留，重新登录后不用再调一遍。
  Future<void> logout() async {
    if (running) {
      _token?.cancel();
      _token = null;
      running = false;
    }
    _session.clearCookies();
    _cookie = '';
    loggedIn = false;
    busy = false;
    lastError = null;
    courses = const [];
    units = const [];
    lessons = const [];
    currentCid = null;
    meta = null;
    selectedScoid = null;
    selectedUnit = null;
    currentScoid = null;
    currentElapsed = 0;
    currentWait = 0;
    currentHeartbeats = 0;
    statuses.clear();
    results.clear();
    filter = 'all';
    query = '';
    addLog('info', '已退出登录，本地保存的 Cookie 已清除');
    notifyListeners();
    await _persist('');
  }

  // ── 课程与扫描 ───────────────────────────────────────
  Future<void> loadCourse(String cid, {bool rescan = true}) async {
    currentCid = cid;
    lastCid = cid;
    units = const [];
    lessons = const [];
    statuses.clear();
    results.clear();
    notifyListeners();
    unawaited(_persist(_cookie));

    try {
      final m = await _api.getCourseMeta(cid);
      meta = m;
      if (rescan) {
        addLog('info', '正在扫描课程结构…');
        final scan = await scanCourse(
          _api,
          meta: m,
          skipOralLesson: settings.skipOralLesson,
          onLog: (msg) => addLog('info', msg),
        );
        units = scan.units;
        lessons = scan.lessons;
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
      notifyListeners();
    }
  }

  // ── 运行 ─────────────────────────────────────────────
  /// 本次要跑的队列。默认整条待处理队列；传 [only] 时只跑这一节（可重跑已完成的节）。
  List<Lesson> runQueue({Lesson? only}) => only != null ? <Lesson>[only] : candidates;

  void startRun({Lesson? only}) {
    if (running) return;
    final m = meta;
    if (m == null) {
      addLog('warn', '还没有扫描完成，先重新扫描');
      return;
    }

    final queue = runQueue(only: only);
    if (queue.isEmpty) {
      addLog('warn', '没有待处理的小节');
      return;
    }

    running = true;
    runTotal = queue.length;
    runDone = 0;
    _token = CancelToken();
    notifyListeners();
    addLog(
      'info',
      only == null ? '开始运行 ${queue.length} 节' : '只运行本节：${shortLocation(only)}',
    );
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
        addLog(
          'info',
          '[${i + 1}/${queue.length}] ${shortLocation(lesson)}  rate=${pickCrate(settings.rateMin, settings.rateMax, rng)}%',
        );
        notifyListeners();

        final crate = pickCrate(settings.rateMin, settings.rateMax, rng);
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
          },
        );

        results[lesson.scoid] = result;
        statuses[lesson.scoid] = result.status;
        runDone++;
        addLog(
          result.status == LessonStatus.done
              ? 'done'
              : (result.status == LessonStatus.partial ? 'warn' : 'error'),
          '${result.status.label}  题 ${result.stat.answered}/${result.stat.questions}  '
          '用时 ${result.waitSec}s  心跳 ${result.heartbeats} 次'
          '${result.errorMessage != null ? '  ${result.errorMessage}' : ''}',
        );
        notifyListeners();

        if (result.status == LessonStatus.interrupted) break;
        if (result.status == LessonStatus.failed) {
          // 失败继续下一节，与 CLI 语义一致
        }

        if (i < queue.length - 1) {
          final gap = pickInterval(
            settings.intervalMin,
            settings.intervalMax,
            rng,
          );
          await sleepInterruptible(
            Duration(milliseconds: (gap * 1000).round()),
            token,
          );
        }
      }
    } on AppException catch (e) {
      addLog('error', e.message);
    } catch (e) {
      addLog('error', '运行异常：$e');
    } finally {
      running = false;
      currentScoid = null;
      currentElapsed = 0;
      _token = null;
      notifyListeners();
      addLog('info', '本次运行结束');
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

String shortLocation(Lesson lesson) => lesson.location.replaceFirst(
  RegExp(r'^Unit \d+\s*>\s*', caseSensitive: false),
  '',
);

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
