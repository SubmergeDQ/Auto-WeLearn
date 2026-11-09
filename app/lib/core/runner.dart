import 'dart:async';
import 'dart:math';

import 'api.dart';
import 'errors.dart';
import 'models.dart';
import 'parser.dart';
import 'scorm.dart';

/// 可取消标记。整个运行链路的每个 await 点都会检查它。
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw AppException(AppErrorCode.interrupted, '已取消');
  }
}

Future<void> sleepInterruptible(
  Duration total,
  CancelToken token, {
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(total);
  while (true) {
    token.throwIfCancelled();
    final remain = end.difference(DateTime.now());
    if (remain <= Duration.zero) return;
    await Future<void>.delayed(remain < step ? remain : step);
  }
}

int randomInt(int min, int max, Random rng) {
  final lo = min.ceil();
  final hi = max.floor();
  if (hi <= lo) return lo;
  return lo + rng.nextInt(hi - lo + 1);
}

int pickWait(int min, int max, Random rng) => randomInt(min, max, rng);
int pickCrate(int min, int max, Random rng) =>
    randomInt(min, max, rng).clamp(0, 100);
double pickInterval(int min, int max, Random rng) =>
    max <= min ? min.toDouble() : min + rng.nextDouble() * (max - min);

/// 扫描：单元 → 小节，落成任务队列
Future<ScannedCourse> scanCourse(
  Api api, {
  required CourseMeta meta,
  required bool skipOralLesson,
  int? onlyUnit,
  CancelToken? token,
  void Function(String message)? onLog,
}) async {
  final warnings = <String>[];
  final units = await api.getUnits(meta.cid, meta.uid);

  final indices = <int>[];
  if (onlyUnit != null) {
    indices.add(onlyUnit - 1);
  } else {
    final upper = (units.length + 1).clamp(1, 200);
    for (var i = 0; i < upper; i++) {
      indices.add(i);
    }
  }

  final lessons = <Lesson>[];
  for (final unitIndex in indices) {
    token?.throwIfCancelled();
    final batch = await api.getLessons(
      cid: meta.cid,
      uid: meta.uid,
      classid: meta.classid,
      unitIndex: unitIndex,
    );
    if (batch == null) {
      warnings.add('第 ${unitIndex + 1} 单元小节列表返回异常，停止继续探测');
      break;
    }
    if (batch.isEmpty) break;
    lessons.addAll(batch);
    onLog?.call('第 ${unitIndex + 1} 单元：${batch.length} 小节');
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  final candidates = lessons
      .where(
        (l) => l.visible && !l.complete && !(skipOralLesson && isOralLesson(l)),
      )
      .toList();

  return ScannedCourse(
    meta: meta,
    units: units,
    lessons: lessons,
    candidates: candidates,
    warnings: warnings,
  );
}

/// 口语小节关键词。`Listening & Speaking` 是听说课，用户明确希望整节跳过；
/// 但只匹配完整短语或科目名，避免把单独的「Listening」听力课误判。
const oralLessonKeywords = [
  '口语',
  'listening & speaking',
  'listening and speaking',
  'speaking',
  'pronunciation',
  'read aloud',
  'readaloud',
  'voicerecord',
  'oral practice',
  'spoken english',
];

bool isOralLesson(Lesson lesson) {
  final text = lesson.location.toLowerCase();
  return oralLessonKeywords.any(text.contains);
}

class KeepaliveOutcome {
  KeepaliveOutcome({
    required this.elapsed,
    required this.heartbeats,
    required this.supported,
  });
  final int elapsed;
  final int heartbeats;
  final bool supported;
}

/// 等待 + 心跳。30–40s 上报一次，结束时补一次。
///
/// [startElapsed] / [startHeartbeats] 用于登录失效重试：从断点继续等待，
/// 已经上报过的秒数不再重复计入 total_time。
Future<KeepaliveOutcome> runKeepalive({
  required Api api,
  required CourseMeta meta,
  required String scoid,
  required int totalBefore,
  required int targetSec,
  required CancelToken token,
  Random? random,
  int startElapsed = 0,
  int startHeartbeats = 0,
  void Function(int elapsed)? onTick,
  void Function(bool ok, int elapsed)? onBeat,
  void Function(String message)? onLog,
}) async {
  final rng = random ?? Random();
  var elapsed = startElapsed.clamp(0, targetSec);
  var heartbeats = startHeartbeats;
  var supported = true;
  var nextBeat = elapsed + randomInt(30, 40, rng);
  var waited = false;

  Future<void> beat() async {
    try {
      final ok = await api.keepSco(
        meta,
        scoid,
        sessionTime: elapsed,
        // 本节真正新增的秒数；重登续跑时扣掉断点前已经上报的部分
        totalTime: totalBefore + elapsed - startElapsed,
      );
      if (ok) {
        heartbeats++;
        onBeat?.call(true, elapsed);
      } else if (supported) {
        supported = false;
        onLog?.call('平台不接受心跳，本节降级为纯等待');
      }
    } on AppException catch (e) {
      if (e.isInterrupted || e.isAuthExpired) rethrow;
      onLog?.call('心跳失败（${e.code.code}），继续等待');
    }
  }

  while (elapsed < targetSec) {
    token.throwIfCancelled();
    await sleepInterruptible(
      const Duration(seconds: 1),
      token,
      step: const Duration(milliseconds: 250),
    );
    elapsed++;
    waited = true;
    onTick?.call(elapsed);

    if (elapsed >= nextBeat && elapsed < targetSec) {
      await beat();
      nextBeat = elapsed + randomInt(30, 40, rng);
    }
  }
  // 已经等满（重登后从断点续跑）时不再补心跳，避免重复上报
  if (targetSec > 0 && waited) await beat();
  onTick?.call(elapsed);

  return KeepaliveOutcome(
    elapsed: elapsed,
    heartbeats: heartbeats,
    supported: supported,
  );
}

/// 单节状态机：解析 → startsco → 等待保活 → setscoinfo → savescoinfo
///
/// [startElapsed] / [startHeartbeats] 供登录失效后重试使用：调用方把上一次
/// 已经等待的秒数传进来，本节从断点继续，而不是从头再等一遍。
Future<LessonResult> runLesson({
  required Api api,
  required CourseMeta meta,
  required Lesson lesson,
  required int crate,
  required int waitSec,
  required RunSettings settings,
  required CancelToken token,
  Random? random,
  int startElapsed = 0,
  int startHeartbeats = 0,
  void Function(String level, String message)? onLog,
  void Function(int elapsed, int heartbeats)? onTick,
}) async {
  final rng = random ?? Random();
  var heartbeats = startHeartbeats;
  var elapsed = startElapsed;

  try {
    final address = await api.getScoAddr(
      cid: meta.cid,
      scoid: lesson.scoid,
      classid: meta.classid,
    );
    final html = address == null ? null : await api.fetchTemplate(address.url);
    final parsed = html == null
        ? ParseResult(
            questions: const [],
            oral: 0,
            strategy: 'none',
            warnings: const [],
          )
        : parseSco(html);
    final bundle = generateInteractions(parsed.questions, crate, random: rng);

    onLog?.call(
      'info',
      '解析 ${parsed.questions.length} 题（跳过 ${parsed.oral} 道口语题）  '
          '等待 ${(waitSec ~/ 60).toString().padLeft(2, '0')}:${(waitSec % 60).toString().padLeft(2, '0')}',
    );

    // 判为口语课的情况直接跳过，不做整节等待：
    // 1. 标题命中口语关键词（旧队列没重新扫描时也能生效）
    // 2. 没有任何可提交题目（纯口语 / 录音 / 语音评测页）
    // 3. 口语题数量不少于可提交题（听说课里只夹杂少量听力题）
    final oralTitle = isOralLesson(lesson);
    final noSubmittable = parsed.questions.isEmpty;
    final mostlyOral =
        parsed.oral > 0 && parsed.oral >= parsed.questions.length;
    if (settings.skipOralLesson && (oralTitle || noSubmittable || mostlyOral)) {
      final reason = oralTitle
          ? '标题识别为口语小节，已跳过等待'
          : (noSubmittable
                ? (parsed.oralPage
                      ? '识别为口语小节（页面含录音/语音特征），已跳过等待'
                      : '未解析到可提交题目，已跳过等待')
                : '口语题多于可提交题，按口语小节跳过等待');
      onLog?.call('info', reason);
      return LessonResult(
        scoid: lesson.scoid,
        status: LessonStatus.skipped,
        crate: crate,
        waitSec: 0,
        heartbeats: 0,
        stat: LessonStat(questions: 0, oral: parsed.oral, answered: 0),
        finishedAt: DateTime.now(),
      );
    }

    if (!await api.startSco(meta, lesson.scoid)) {
      throw AppException(AppErrorCode.platformRejected, 'startsco 未被平台接受');
    }

    var totalBefore = 0;
    try {
      final cmi = await api.readCmi(meta, lesson.scoid);
      if (cmi.ok) totalBefore = cmi.totalBefore;
    } on AppException catch (e) {
      if (e.isInterrupted || e.isAuthExpired) rethrow;
      onLog?.call('warn', 'CMI 读取失败，按 totalBefore=0 继续');
    }

    // 两次心跳之间的增量：日志里前面写本次加了多少，后面写本节累计
    var lastBeatAt = startElapsed;
    final ka = await runKeepalive(
      api: api,
      meta: meta,
      scoid: lesson.scoid,
      totalBefore: totalBefore,
      targetSec: waitSec,
      token: token,
      random: rng,
      startElapsed: startElapsed,
      startHeartbeats: startHeartbeats,
      onTick: (e) {
        elapsed = e;
        onTick?.call(e, heartbeats);
      },
      onBeat: (ok, e) {
        if (ok) heartbeats++;
        final delta = e - lastBeatAt;
        lastBeatAt = e;
        onLog?.call('beat', '+${delta}s 心跳 ok（本节总计 ${totalBefore + e}s）');
      },
      onLog: (m) => onLog?.call('warn', m),
    );
    elapsed = ka.elapsed;
    heartbeats = ka.heartbeats;

    final sessionTime = ka.elapsed;
    // 重登续跑时本次真正新增的秒数，避免 total_time 把断点前的时长算两遍
    final learned = ka.elapsed - startElapsed;
    final totalTime = settings.cmiTime == 'session'
        ? learned
        : totalBefore + learned;
    final data = buildScoData(
      interactions: bundle.interactions,
      crate: crate,
      sessionTime: sessionTime,
      totalTime: totalTime,
      interactionInfo: bundle.interactionInfo,
    );

    final setOk = await api.setScoInfo(meta, lesson.scoid, data);
    final saveOk = await api.saveScoInfo(
      meta,
      lesson.scoid,
      crate: crate,
      sessionTime: sessionTime,
      totalTime: totalTime,
    );

    final status = setOk && saveOk
        ? LessonStatus.done
        : (setOk || saveOk ? LessonStatus.partial : LessonStatus.failed);

    return LessonResult(
      scoid: lesson.scoid,
      status: status,
      crate: crate,
      waitSec: elapsed,
      heartbeats: heartbeats,
      stat: LessonStat(
        questions: parsed.questions.length,
        oral: parsed.oral,
        answered: bundle.interactions.length,
      ),
      errorCode: status == LessonStatus.failed
          ? AppErrorCode.platformRejected.code
          : null,
      finishedAt: DateTime.now(),
    );
  } on AppException catch (e) {
    if (e.isInterrupted) {
      return LessonResult(
        scoid: lesson.scoid,
        status: LessonStatus.interrupted,
        crate: crate,
        waitSec: elapsed,
        heartbeats: heartbeats,
        stat: LessonStat.empty,
        finishedAt: DateTime.now(),
      );
    }
    if (e.isAuthExpired) rethrow;
    return LessonResult(
      scoid: lesson.scoid,
      status: LessonStatus.failed,
      crate: crate,
      waitSec: elapsed,
      heartbeats: heartbeats,
      stat: LessonStat.empty,
      errorCode: e.code.code,
      errorMessage: e.message,
      finishedAt: DateTime.now(),
    );
  }
}
