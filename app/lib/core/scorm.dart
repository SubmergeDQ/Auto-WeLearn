import 'dart:convert';
import 'dart:math';

import 'models.dart';

/// JavaScript 旧版 escape() 的等价实现：字母数字与 `@*-_+./` 原样，
/// 其余 <256 转 %XX，否则按 UTF-16 码元转 %uXXXX。
String jsEscape(String input) {
  const safe = '@*-_+./';
  final buffer = StringBuffer();
  for (final code in input.codeUnits) {
    final ch = String.fromCharCode(code);
    final isAlnum =
        (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A);
    if (isAlnum || safe.contains(ch)) {
      buffer.write(ch);
    } else if (code < 256) {
      buffer.write('%${code.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    } else {
      buffer.write('%u${code.toRadixString(16).toUpperCase().padLeft(4, '0')}');
    }
  }
  return buffer.toString();
}

class InteractionBundle {
  InteractionBundle(this.interactions, this.interactionInfo);
  final List<Interaction> interactions;
  final String interactionInfo;
}

/// 按目标正确率生成答题记录。区间型正确率由调用方每节抽一次后传入。
InteractionBundle generateInteractions(
  List<Question> questions,
  int crate, {
  Random? random,
}) {
  final rng = random ?? Random();
  final interactions = <Interaction>[];
  final parts = <String>[];

  for (var i = 0; i < questions.length; i++) {
    final q = questions[i];
    final correct = rng.nextDouble() * 100 < crate;
    final response = correct ? q.answer : _wrongAnswer(q, i);
    final result = correct ? 'correct' : 'wrong';

    interactions.add(
      Interaction(
        id: 'interaction_$i',
        type: q.type,
        studentResponse: response,
        result: result,
        correctResponses: correct ? [q.answer] : null,
      ),
    );
    parts.add('$i[]false[]false[]${jsEscape(response)}[]$result');
  }

  return InteractionBundle(interactions, parts.join(r'$$'));
}

String _wrongAnswer(Question q, int index) {
  switch (q.type) {
    case QuestionType.tof:
      return q.answer.trim().toLowerCase() == 't' ? 'f' : 't';
    case QuestionType.choice:
      return q.answer.trim().toUpperCase() == 'A' ? 'B' : 'A';
    default:
      return 'wrong_answer_$index';
  }
}

const interactionMarker = '[INTERACTIONINFO]';

/// setscoinfo 的 data 字段：JSON + 字面量标记 + 答题串。字段顺序不能改。
String buildScoData({
  required List<Interaction> interactions,
  required int crate,
  required int sessionTime,
  required int totalTime,
  required String interactionInfo,
}) {
  final payload = {
    'cmi': {
      'completion_status': 'completed',
      'interactions': interactions.map((e) => e.toJson()).toList(),
      'launch_data': '',
      'progress_measure': '1',
      'score': {'scaled': '$crate', 'raw': '100'},
      'session_time': '$sessionTime',
      'success_status': 'unknown',
      'total_time': '$totalTime',
      'mode': 'normal',
    },
    'adl': {'data': <dynamic>[]},
    'cci': {
      'data': <dynamic>[],
      'service': {
        'dictionary': {'headword': '', 'short_cuts': ''},
        'new_words': <dynamic>[],
        'notes': <dynamic>[],
        'writing_marking': <dynamic>[],
        'record': {'files': <dynamic>[]},
        'play': {'offline_media_id': '9999'},
      },
      'retry_count': '0',
      'submit_time': '',
    },
  };
  return jsonEncode(payload) + interactionMarker + interactionInfo;
}
