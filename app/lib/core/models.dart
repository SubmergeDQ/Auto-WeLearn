/// 领域模型。字段语义与 docs/NODE_CLI_SPEC.md §3 保持一致。
library;

enum QuestionType { blank, tof, choice, match, order }

extension QuestionTypeName on QuestionType {
  String get label => switch (this) {
    QuestionType.blank => '填空',
    QuestionType.tof => '判断',
    QuestionType.choice => '选择',
    QuestionType.match => '匹配',
    QuestionType.order => '排序',
  };

  String get wire => name;
}

class Course {
  const Course({required this.cid, required this.name, required this.percent});
  final String cid;
  final String name;
  final int percent;
}

class CourseUnit {
  const CourseUnit({
    required this.index,
    required this.unitName,
    required this.name,
    required this.visible,
  });
  final int index;
  final String unitName;
  final String name;
  final bool visible;

  /// 平台 `unitname` 的写法不统一：`U01` / `Unit 01` / `第 3 单元` / `1` 都出现过。
  /// 界面统一显示 `Unit 1`；实在解析不出编号时保留平台原文，不猜。
  String get label {
    final n = parseUnitNumber(unitName) ?? parseUnitNumber(name);
    if (n != null) return 'Unit $n';
    final raw = unitName.trim();
    return raw.isEmpty ? 'Unit' : raw;
  }
}

/// 从单元名里取编号。只认开头的编号前缀，中文标题不会被误判成数字。
int? parseUnitNumber(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final pure = RegExp(r'^0*(\d{1,3})$').firstMatch(text);
  if (pure != null) return int.tryParse(pure.group(1)!);
  final prefixed = RegExp(
    r'^(?:[Uu](?:nit)?|第|单元)\s*[:.\-_]?\s*0*(\d{1,3})(?!\d)',
  ).firstMatch(text);
  if (prefixed != null) return int.tryParse(prefixed.group(1)!);
  return null;
}

class Lesson {
  const Lesson({
    required this.unitIndex,
    required this.scoid,
    required this.location,
    required this.visible,
    required this.complete,
    required this.learnTime,
    required this.crateLabel,
  });
  final int unitIndex;
  final String scoid;
  final String location;
  final bool visible;
  final bool complete;
  final String learnTime;
  final String crateLabel;

  Lesson copyWith({bool? complete}) => Lesson(
    unitIndex: unitIndex,
    scoid: scoid,
    location: location,
    visible: visible,
    complete: complete ?? this.complete,
    learnTime: learnTime,
    crateLabel: crateLabel,
  );
}

class Question {
  const Question({required this.type, required this.answer, required this.tag});
  final QuestionType type;
  final String answer;
  final String tag;
}

class Interaction {
  const Interaction({
    required this.id,
    required this.type,
    required this.studentResponse,
    required this.result,
    this.correctResponses,
  });
  final String id;
  final QuestionType type;
  final String studentResponse;
  final String result;
  final List<String>? correctResponses;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.wire,
    'student_response': studentResponse,
    'result': result,
    'weighting': '1',
    if (correctResponses != null)
      'correct_responses': correctResponses!
          .map((p) => {'pattern': p})
          .toList(),
  };
}

enum LessonStatus {
  pending,
  running,
  done,
  partial,
  failed,
  skipped,
  interrupted,
}

extension LessonStatusName on LessonStatus {
  String get label => switch (this) {
    LessonStatus.pending => '待处理',
    LessonStatus.running => '进行中',
    LessonStatus.done => '已完成',
    LessonStatus.partial => '部分成功',
    LessonStatus.failed => '失败',
    LessonStatus.skipped => '已跳过',
    LessonStatus.interrupted => '已中断',
  };

  bool get isFinal =>
      this == LessonStatus.done ||
      this == LessonStatus.partial ||
      this == LessonStatus.failed ||
      this == LessonStatus.skipped;
}

class LessonStat {
  const LessonStat({
    required this.questions,
    required this.oral,
    required this.answered,
  });
  final int questions;
  final int oral;
  final int answered;
  static const empty = LessonStat(questions: 0, oral: 0, answered: 0);
}

class LessonResult {
  const LessonResult({
    required this.scoid,
    required this.status,
    required this.crate,
    required this.waitSec,
    required this.heartbeats,
    required this.stat,
    this.errorCode,
    this.errorMessage,
    this.finishedAt,
  });
  final String scoid;
  final LessonStatus status;
  final int crate;
  final int waitSec;
  final int heartbeats;
  final LessonStat stat;
  final String? errorCode;
  final String? errorMessage;

  /// 该节结束的时间，面板「最近完成」按它显示「n 分钟前」。
  final DateTime? finishedAt;

  Map<String, dynamic> toJson() => {
    'scoid': scoid,
    'status': status.name,
    'crate': crate,
    'waitSec': waitSec,
    'heartbeats': heartbeats,
    'questions': stat.questions,
    'oral': stat.oral,
    'answered': stat.answered,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
  };

  /// 读回历史记录时对未知/损坏的状态回退为失败，不让整个历史失效。
  static LessonResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final scoid = raw['scoid'];
    if (scoid is! String || scoid.isEmpty) return null;
    final status = LessonStatus.values.firstWhere(
      (s) => s.name == raw['status'],
      orElse: () => LessonStatus.failed,
    );
    return LessonResult(
      scoid: scoid,
      status: status,
      crate: (raw['crate'] as num?)?.toInt() ?? 0,
      waitSec: (raw['waitSec'] as num?)?.toInt() ?? 0,
      heartbeats: (raw['heartbeats'] as num?)?.toInt() ?? 0,
      stat: LessonStat(
        questions: (raw['questions'] as num?)?.toInt() ?? 0,
        oral: (raw['oral'] as num?)?.toInt() ?? 0,
        answered: (raw['answered'] as num?)?.toInt() ?? 0,
      ),
      errorCode: raw['errorCode'] as String?,
      errorMessage: raw['errorMessage'] as String?,
      finishedAt: DateTime.tryParse('${raw['finishedAt']}'),
    );
  }
}

class ScannedCourse {
  const ScannedCourse({
    required this.meta,
    required this.units,
    required this.lessons,
    required this.candidates,
    required this.warnings,
  });
  final CourseMeta meta;
  final List<CourseUnit> units;
  final List<Lesson> lessons;
  final List<Lesson> candidates;
  final List<String> warnings;
}

class CourseMeta {
  const CourseMeta({
    required this.cid,
    required this.uid,
    required this.classid,
  });
  final String cid;
  final String uid;
  final String classid;
}

/// 等待时长按 10 秒一档（30–900）。
/// 旧版本可能保存任意偶数，读取时归一化到最近的 10 秒，避免界面显示与运行值不一致。
int normalizeWaitSeconds(int value) {
  const min = 30;
  const max = 900;
  const step = 10;
  final clamped = value < min ? min : (value > max ? max : value);
  final snapped = ((clamped - min) / step).round() * step + min;
  return snapped.clamp(min, max);
}

/// 运行参数（GUI 里由设置面板产出）
class RunSettings {
  const RunSettings({
    this.waitMin = 300,
    this.waitMax = 480,
    this.rateMin = 90,
    this.rateMax = 100,
    this.intervalMin = 3,
    this.intervalMax = 8,
    this.skipOralLesson = true,
    this.cmiTime = 'total',
  });

  final int waitMin;
  final int waitMax;
  final int rateMin;
  final int rateMax;
  final int intervalMin;
  final int intervalMax;
  final bool skipOralLesson;
  final String cmiTime;

  RunSettings copyWith({
    int? waitMin,
    int? waitMax,
    int? rateMin,
    int? rateMax,
    int? intervalMin,
    int? intervalMax,
    bool? skipOralLesson,
    String? cmiTime,
  }) => RunSettings(
    waitMin: waitMin ?? this.waitMin,
    waitMax: waitMax ?? this.waitMax,
    rateMin: rateMin ?? this.rateMin,
    rateMax: rateMax ?? this.rateMax,
    intervalMin: intervalMin ?? this.intervalMin,
    intervalMax: intervalMax ?? this.intervalMax,
    skipOralLesson: skipOralLesson ?? this.skipOralLesson,
    cmiTime: cmiTime ?? this.cmiTime,
  );

  Map<String, dynamic> toJson() => {
    'waitMin': waitMin,
    'waitMax': waitMax,
    'rateMin': rateMin,
    'rateMax': rateMax,
    'intervalMin': intervalMin,
    'intervalMax': intervalMax,
    'skipOralLesson': skipOralLesson,
    'cmiTime': cmiTime,
  };

  static RunSettings fromJson(Map<String, dynamic> json) => RunSettings(
    waitMin: normalizeWaitSeconds((json['waitMin'] as num?)?.toInt() ?? 300),
    waitMax: normalizeWaitSeconds((json['waitMax'] as num?)?.toInt() ?? 480),
    rateMin: (json['rateMin'] as num?)?.toInt() ?? 90,
    rateMax: (json['rateMax'] as num?)?.toInt() ?? 100,
    intervalMin: (json['intervalMin'] as num?)?.toInt() ?? 3,
    intervalMax: (json['intervalMax'] as num?)?.toInt() ?? 8,
    skipOralLesson: json['skipOralLesson'] as bool? ?? true,
    cmiTime: json['cmiTime'] as String? ?? 'total',
  );
}
