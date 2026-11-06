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
  });
  final String scoid;
  final LessonStatus status;
  final int crate;
  final int waitSec;
  final int heartbeats;
  final LessonStat stat;
  final String? errorCode;
  final String? errorMessage;
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
    waitMin: (json['waitMin'] as num?)?.toInt() ?? 300,
    waitMax: (json['waitMax'] as num?)?.toInt() ?? 480,
    rateMin: (json['rateMin'] as num?)?.toInt() ?? 90,
    rateMax: (json['rateMax'] as num?)?.toInt() ?? 100,
    intervalMin: (json['intervalMin'] as num?)?.toInt() ?? 3,
    intervalMax: (json['intervalMax'] as num?)?.toInt() ?? 8,
    skipOralLesson: json['skipOralLesson'] as bool? ?? true,
    cmiTime: json['cmiTime'] as String? ?? 'total',
  );
}
