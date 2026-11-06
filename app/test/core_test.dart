import 'package:flutter_test/flutter_test.dart';
import 'package:welearn_app/app_state.dart';
import 'package:welearn_app/core/models.dart';
import 'package:welearn_app/core/parser.dart';
import 'package:welearn_app/core/scorm.dart';

void main() {
  group('parseCookieInput', () {
    test('解析浏览器复制格式', () {
      final pairs = parseCookieInput('a=1; b=2');
      expect(pairs.map((e) => e.key), ['a', 'b']);
      expect(pairs.map((e) => e.value), ['1', '2']);
    });

    test('值里的等号不被切开', () {
      final pairs = parseCookieInput('.AspNet.Cookies=abc=def');
      expect(pairs.single.value, 'abc=def');
    });

    test('解析 EditThisCookie JSON', () {
      final pairs = parseCookieInput('[{"name":"area","value":"dbC"}]');
      expect(pairs.single.key, 'area');
      expect(pairs.single.value, 'dbC');
    });

    test('空输入抛错', () {
      expect(() => parseCookieInput('  '), throwsA(isA<Exception>()));
    });
  });

  group('reconcileBlankAnswer', () {
    test('result 带中文注释时保留 solution', () {
      expect(reconcileBlankAnswer('cello', 'cello（大提琴）'), 'cello');
    });

    test('斜杠多答案按 result 命中', () {
      expect(reconcileBlankAnswer('reaching/for', 'for'), 'for');
      expect(reconcileBlankAnswer('to/reply to', 'to'), 'to');
    });

    test('result 为空时用 solution', () {
      expect(reconcileBlankAnswer('envious', ''), 'envious');
    });
  });

  group('jsEscape', () {
    test('保留字母数字与白名单符号', () {
      expect(jsEscape('Abc123@*-_+./'), 'Abc123@*-_+./');
    });

    test('空格与中文', () {
      expect(jsEscape('中文 A'), '%u4E2D%u6587%20A');
    });

    test('百分号自身被转义', () {
      expect(jsEscape('%'), '%25');
    });
  });

  group('buildScoData', () {
    test('以 [INTERACTIONINFO] 分隔且保留字段顺序', () {
      final data = buildScoData(
        interactions: const [],
        crate: 100,
        sessionTime: 60,
        totalTime: 180,
        interactionInfo: '',
      );
      expect(data.endsWith('[INTERACTIONINFO]'), isTrue);
      final json = data.split('[INTERACTIONINFO]').first;
      expect(json.startsWith('{"cmi":{"completion_status":"completed"'), isTrue);
      expect(json, contains('"total_time":"180"'));
    });
  });

  group('课程模型', () {
    test('isFinal 只对终态为真', () {
      expect(LessonStatus.done.isFinal, isTrue);
      expect(LessonStatus.failed.isFinal, isTrue);
      expect(LessonStatus.running.isFinal, isFalse);
      expect(LessonStatus.pending.isFinal, isFalse);
    });
  });
}
