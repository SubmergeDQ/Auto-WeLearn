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

Future<void> sleepInterruptible(Duration total, CancelToken token,
    {Duration step = const Duration(milliseconds: 200)}) async {
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
int pickCrate(int min, int max, Random rng) => randomInt(min, max, rng).clamp(0, 100);
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
      .where((l) =>
          l.visible &&
          !l.complete &&
          !(skipOralLesson && isOralLesson(l)))
      .toList();

  return ScannedCourse(
    meta: meta,
    units: units,
    lessons: lessons,
    candidates: candidates,
    warnings: warnings,
  );
}

/// 口语小节关键词。刻意不含裸 speaking ——「Listening & Speaking」是听力题。
const oralLessonKeywords = [
  '口语',
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
Future<KeepaliveOutcome> runKeepalive({
  required Api api,
  required CourseMeta meta,
  required String scoid,
  required int totalBefore,
  required int targetSec,
  required CancelToken token,
  Random? random,
  void Function(int elapsed)? onTick,
  void Function(bool ok, int elapsed)? onBeat,
  void Function(String message)? onLog,
}) async {
  final rng = random ?? Random();
  var elapsed = 0;
  var heartbeats = 0;
  var supported = true;
  var nextBeat = randomInt(30, 40, rng);

  Future<void> beat() async {
    try {
      final ok = await api.keepSco(meta, scoid,
          sessionTime: elapsed, totalTime: totalBefore + elapsed);
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
    await sleepInterruptible(const Duration(seconds: 1), token,
        step: const Duration(milliseconds: 250));
    elapsed++;
    onTick?.call(elapsed);

    if (elapsed >= nextBeat && elapsed < targetSec) {
      await beat();
      nextBeat = elapsed + randomInt(30, 40, rng);
    }
  }
  if (targetSec > 0) await beat();
  onTick?.call(elapsed);

  return KeepaliveOutcome(elapsed: elapsed, heartbeats: heartbeats, supported: supported);
}

/// 单节状态机：解析 → startsco → 等待保活 → setscoinfo → savescoinfo
Future<LessonResult> runLesson({
  required Api api,
  required CourseMeta meta,
  required Lesson lesson,
  required int crate,
  required int waitSec,
  required RunSettings settings,
  required CancelToken token,
  Random? random,
  void Function(String level, String message)? onLog,
  void Function(int elapsed, int heartbeats)? onTick,
}) async {
  final rng = random ?? Random();
  var heartbeats = 0;
  var elapsed = 0;

  try {
    final address = await api.getScoAddr(
      cid: meta.cid,
      scoid: lesson.scoid,
      classid: meta.classid,
    );
    final html = address == null ? null : await api.fetchTemplate(address.url);
    final parsed = html == null
        ? ParseResult(questions: const [], oral: 0, strategy: 'none', warnings: const [])
        : parseSco(html);
    final bundle = generateInteractions(parsed.questions, crate, random: rng);

    onLog?.call(
        'info',
        '解析 ${parsed.questions.length} 题（跳过 ${parsed.oral} 道口语题）  '
        '等待 ${(waitSec ~/ 60).toString().padLeft(2, '0')}:${(waitSec % 60).toString().padLeft(2, '0')}');

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

    final ka = await runKeepalive(
      api: api,
      meta: meta,
      scoid: lesson.scoid,
      totalBefore: totalBefore,
      targetSec: waitSec,
      token: token,
      random: rng,
      onTick: (e) {
        elapsed = e;
        onTick?.call(e, heartbeats);
      },
      onBeat: (ok, e) {
        if (ok) heartbeats++;
        onLog?.call('beat', '+${e}s 心跳 ok（total=${totalBefore + e}s）');
      },
      onLog: (m) => onLog?.call('warn', m),
    );
    elapsed = ka.elapsed;
    heartbeats = ka.heartbeats;

    final sessionTime = ka.elapsed;
    final totalTime = settings.cmiTime == 'session' ? sessionTime : totalBefore + sessionTime;
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
      errorCode: status == LessonStatus.failed ? AppErrorCode.platformRejected.code : null,
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
    );
  }
}
