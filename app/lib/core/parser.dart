import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'models.dart';

/// SCO 模板解析。两套课件并存：
/// 1. courseware：`data-controltype` / `data-itemtype`（本账号课程用的就是这套）
/// 2. legacy：`<et-blank answer="...">` 这类自定义标签
/// 规则与 CLI 版 `src/core/parse/sco-parser.ts` 一一对应。
class ParseResult {
  ParseResult({
    required this.questions,
    required this.oral,
    required this.strategy,
    required this.warnings,
  });
  final List<Question> questions;
  final int oral;
  final String strategy;
  final List<String> warnings;
}

const _controlTypeMap = <String, QuestionType>{
  'filling': QuestionType.blank,
  'fillinglong': QuestionType.blank,
  'fill': QuestionType.blank,
  'fillin': QuestionType.blank,
  'blank': QuestionType.blank,
  'choice': QuestionType.choice,
  'select': QuestionType.choice,
  'radio': QuestionType.choice,
  'checkbox': QuestionType.choice,
  'multi': QuestionType.choice,
  'multiple': QuestionType.choice,
  'tof': QuestionType.tof,
  'truefalse': QuestionType.tof,
  'matching': QuestionType.match,
  'match': QuestionType.match,
  'ordering': QuestionType.order,
  'order': QuestionType.order,
  'sort': QuestionType.order,
  'sequence': QuestionType.order,
};

const _legacyTypeMap = <String, QuestionType>{
  'blank': QuestionType.blank,
  'fill': QuestionType.blank,
  'fillin': QuestionType.blank,
  'tof': QuestionType.tof,
  'truefalse': QuestionType.tof,
  'choice': QuestionType.choice,
  'select': QuestionType.choice,
  'multi': QuestionType.choice,
  'multiple': QuestionType.choice,
  'checkbox': QuestionType.choice,
  'match': QuestionType.match,
  'matching': QuestionType.match,
  'order': QuestionType.order,
  'sort': QuestionType.order,
  'sequence': QuestionType.order,
};

/// 口语关键词。刻意不含 audio：听力题通常带答案，仍需提交
const _oralKeywords = ['speak', 'voice', 'record', 'oral', 'pron', 'repeat', 'readaloud'];

bool _looksOral(String text) {
  final lower = text.toLowerCase();
  return _oralKeywords.any(lower.contains);
}

String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

ParseResult parseSco(String html, {bool skipOral = true}) {
  if (html.trim().isEmpty) {
    return ParseResult(questions: const [], oral: 0, strategy: 'none', warnings: const ['模板为空']);
  }
  final doc = html_parser.parse(html);
  final courseware = _parseCourseware(doc, skipOral);
  final legacy = _parseLegacy(doc);

  if (courseware.questions.isEmpty && legacy.questions.isEmpty) {
    return ParseResult(
      questions: const [],
      oral: courseware.oral + legacy.oral,
      strategy: 'none',
      warnings: [...courseware.warnings, ...legacy.warnings],
    );
  }

  return courseware.questions.length >= legacy.questions.length
      ? ParseResult(
          questions: courseware.questions,
          oral: courseware.oral,
          strategy: 'courseware',
          warnings: courseware.warnings,
        )
      : ParseResult(
          questions: legacy.questions,
          oral: legacy.oral,
          strategy: 'legacy',
          warnings: legacy.warnings,
        );
}

ParseResult _parseCourseware(Document doc, bool skipOral) {
  final questions = <Question>[];
  final warnings = <String>[];
  var oral = 0;

  for (final block in doc.querySelectorAll('[data-controltype]')) {
    final rawType = (block.attributes['data-controltype'] ?? '').trim().toLowerCase();
    final type = _controlTypeMap[rawType];
    final isOral = _looksOral(rawType) ||
        (type != null && _looksOral(block.attributes['class'] ?? ''));

    if (isOral) {
      final recovered = skipOral ? null : _recoverOralAnswer(block, type);
      if (recovered != null) {
        questions.add(recovered);
      } else {
        oral++;
      }
      continue;
    }

    if (type == null) continue;

    if (type == QuestionType.blank) {
      final answer = _blankAnswer(block);
      if (answer == null || answer.isEmpty) {
        warnings.add('填空块 ${block.attributes['data-id'] ?? '(无 id)'} 没有解析到答案');
        continue;
      }
      questions.add(Question(type: QuestionType.blank, answer: answer, tag: rawType));
      continue;
    }

    final labels = _choiceAnswers(block);
    if (labels.isEmpty) {
      warnings.add('选择块 ${block.attributes['data-id'] ?? '(无 id)'} 没有 data-solution 选项');
      continue;
    }

    final isTof = labels.length == 1 &&
        labels.every((l) => l == 'T' || l == 'F') &&
        _isBinaryOptions(block);
    questions.add(Question(
      type: isTof ? QuestionType.tof : type,
      answer: labels.join(','),
      tag: rawType,
    ));
  }

  return ParseResult(questions: questions, oral: oral, strategy: 'courseware', warnings: warnings);
}

Question? _recoverOralAnswer(Element block, QuestionType? type) {
  final rawType = (block.attributes['data-controltype'] ?? '').trim().toLowerCase();
  final blank = _blankAnswer(block);
  if (blank != null && blank.isNotEmpty) {
    return Question(type: QuestionType.blank, answer: blank, tag: rawType);
  }
  final labels = _choiceAnswers(block);
  if (labels.isNotEmpty) {
    return Question(type: type ?? QuestionType.choice, answer: labels.join(','), tag: rawType);
  }
  return null;
}

/// 填空答案：result 文本与 data-solution 的三种关系（附录 C-6）
String? _blankAnswer(Element block) {
  final input = block.querySelector('input[data-solution], textarea[data-solution]');
  final solution = _clean(input?.attributes['data-solution'] ?? '');
  final resultEl = block.querySelector('[data-itemtype="result"]');
  final result = _clean(resultEl?.text ?? '');
  final answer = reconcileBlankAnswer(solution, result);
  return answer.isEmpty ? null : answer;
}

String reconcileBlankAnswer(String solution, String result) {
  final sol = _clean(solution);
  final res = _clean(result);
  if (sol.isEmpty) return res;
  if (res.isEmpty) return sol;

  final stripped = res.replaceAll(RegExp(r'\s*[（(][^（）()]*[）)]\s*$'), '').trim();
  final segments =
      sol.contains('/') ? sol.split('/').map(_clean).where((s) => s.isNotEmpty).toList() : <String>[];

  if (segments.isNotEmpty) {
    for (final s in segments) {
      if (_sameText(s, res)) return s;
    }
    for (final s in segments) {
      if (_sameText(s, stripped)) return s;
    }
  }
  if (_sameText(sol, stripped)) return stripped;
  if (_sameText(sol, res)) return res;
  return res;
}

bool _sameText(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

/// 取选项字母：兼容 `<li><span>T</span></li>` 与 `<li><span><span>A.</span></span><span>…</span></li>`
String _optionLabel(Element li) {
  final spans = li.children.where((e) => e.localName == 'span').toList();
  if (spans.length >= 2) {
    final head = _clean(spans.first.text);
    final m = RegExp(r'^([A-Za-z])[.、)．]?$').firstMatch(head);
    if (m != null) return m.group(1)!.toUpperCase();
  }
  final full = _clean(li.text);
  final single = RegExp(r'^([A-Za-z])[.、)．]?$').firstMatch(full);
  if (single != null) return single.group(1)!.toUpperCase();
  return full;
}

List<String> _choiceAnswers(Element block) {
  final labels = <String>[];
  for (final el in block.querySelectorAll('[data-solution]')) {
    if (!identical(_closestControl(el), block)) continue;
    final label = el.localName == 'li' ? _optionLabel(el) : _clean(el.text);
    if (label.isNotEmpty) labels.add(label);
  }
  return labels;
}

Element? _closestControl(Element el) {
  Element? current = el.parent;
  while (current != null) {
    if (current.attributes.containsKey('data-controltype')) return current;
    current = current.parent;
  }
  return null;
}

bool _isBinaryOptions(Element block) {
  final options = block.querySelectorAll('li');
  if (options.length != 2) return false;
  return options.every((el) {
    final t = _clean(el.text).toUpperCase();
    return t == 'T' || t == 'F' || t == 'TRUE' || t == 'FALSE';
  });
}

ParseResult _parseLegacy(Document doc) {
  final questions = <Question>[];
  final warnings = <String>[];
  var oral = 0;

  for (final el in doc.querySelectorAll('*')) {
    final tag = el.localName ?? '';
    if (!tag.startsWith('et-')) continue;
    final short = tag.substring(3);
    final attrs = el.attributes;

    if (_looksOral(short) || _looksOral(attrs.values.join(' '))) {
      oral++;
      continue;
    }

    var type = _legacyTypeMap[short];
    String attr(String name) => _clean(attrs[name] ?? '');
    var answer = type == QuestionType.blank
        ? (attr('answer').isNotEmpty ? attr('answer') : (attr('data-answer').isNotEmpty ? attr('data-answer') : _clean(el.text)))
        : (attr('key').isNotEmpty
            ? attr('key')
            : (attr('answer').isNotEmpty
                ? attr('answer')
                : (attr('data-answer').isNotEmpty ? attr('data-answer') : attr('value'))));

    if (answer.isEmpty) continue;
    if (type == null) {
      type = QuestionType.choice;
      warnings.add('未知题型 <$tag> 有答案，按 choice 透传');
    }
    if (type == QuestionType.choice && RegExp(r'^[A-Z]{2,8}$').hasMatch(answer)) {
      answer = answer.split('').join(',');
    }
    questions.add(Question(type: type, answer: answer, tag: short));
  }

  return ParseResult(questions: questions, oral: oral, strategy: 'legacy', warnings: warnings);
}
