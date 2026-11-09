import 'dart:convert';
import 'dart:math';

import 'package:flutter_inappwebview/flutter_inappwebview.dart' show Cookie;
import 'package:flutter_test/flutter_test.dart';
import 'package:welearn_app/app_state.dart';
import 'package:welearn_app/core/api.dart';
import 'package:welearn_app/core/auto_login.dart';
import 'package:welearn_app/core/browser_login.dart';
import 'package:welearn_app/core/models.dart';
import 'package:welearn_app/core/parser.dart';
import 'package:welearn_app/core/release_notes.dart';
import 'package:welearn_app/core/runner.dart';
import 'package:welearn_app/core/scorm.dart';
import 'package:welearn_app/core/session.dart';
import 'package:welearn_app/core/updater.dart';
import 'package:welearn_app/ui/components.dart' show snapToStep;
import 'package:welearn_app/ui/widgets.dart' show relativeTimeText;

void main() {
  group('browser_login', () {
    test('学生主页算已登录', () {
      expect(
        isLoggedInUrl('https://welearn.sflep.com/student/index.aspx'),
        isTrue,
      );
      expect(
        isLoggedInUrl(
          'https://welearn.sflep.com/Student/StudyCourse.aspx?cid=566',
        ),
        isTrue,
      );
    });

    test('prelogin 与 SSO 登录页不算已登录', () {
      expect(
        isLoggedInUrl(
          'https://welearn.sflep.com/user/prelogin.aspx?loginret=1',
        ),
        isFalse,
      );
      expect(
        isLoggedInUrl('https://welearn.sflep.com/Account/Login?ReturnUrl=xyz'),
        isFalse,
      );
    });

    test('其它域不算已登录', () {
      expect(isLoggedInUrl('https://login.sflep.com/Account/Login'), isFalse);
      expect(isLoggedInUrl('https://example.com/student/'), isFalse);
      expect(isLoggedInUrl('about:blank'), isFalse);
    });

    test('只有拿到 .AspNet.Cookies 才算会话有效', () {
      expect(
        hasSessionCookie([
          Cookie(name: 'acw_tc', value: 'abc'),
          Cookie(name: 'area', value: 'dbC'),
        ]),
        isFalse,
      );
      expect(
        hasSessionCookie([
          Cookie(name: 'acw_tc', value: 'abc'),
          Cookie(name: '.AspNet.Cookies', value: 'ticket'),
        ]),
        isTrue,
      );
      // 空值的票据不算
      expect(
        hasSessionCookie([Cookie(name: '.AspNet.Cookies', value: ' ')]),
        isFalse,
      );
    });

    test('拼装 Cookie 头并过滤其它域', () {
      final cookies = [
        Cookie(name: 'acw_tc', value: 'abc'),
        Cookie(name: '.AspNet.Cookies', value: 'tick=et'),
        Cookie(name: 'other', value: 'x', domain: '.google.com'),
      ];
      final relevant = relevantCookies(cookies);
      expect(relevant.length, 2);
      expect(
        buildCookieHeader(relevant),
        'acw_tc=abc; .AspNet.Cookies=tick=et',
      );
    });
  });

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
      expect(
        json.startsWith('{"cmi":{"completion_status":"completed"'),
        isTrue,
      );
      expect(json, contains('"total_time":"180"'));
    });
  });

  group('更新检查', () {
    test('仓库链接解析成 owner/repo', () {
      expect(
        parseRepoSlug('https://github.com/SubmergeDQ/Auto-WeLearn'),
        'SubmergeDQ/Auto-WeLearn',
      );
      expect(
        parseRepoSlug('github.com/SubmergeDQ/Auto-WeLearn/releases'),
        'SubmergeDQ/Auto-WeLearn',
      );
      expect(
        parseRepoSlug('https://github.com/SubmergeDQ/Auto-WeLearn.git'),
        'SubmergeDQ/Auto-WeLearn',
      );
      expect(
        parseRepoSlug('SubmergeDQ/Auto-WeLearn'),
        'SubmergeDQ/Auto-WeLearn',
      );
      expect(parseRepoSlug('https://gitee.com/a/b'), isNull);
      expect(parseRepoSlug('not a link'), isNull);
      expect(parseRepoSlug(''), isNull);
    });

    test('版本比较：带 v 前缀与不同段数', () {
      expect(compareVersions('v1.1.0', '1.0.2'), 1);
      expect(compareVersions('1.0.2', 'v1.1.0'), -1);
      expect(compareVersions('1.1.0', '1.1'), 0);
      expect(isNewerVersion('1.1.0', '1.0.2'), isTrue);
      expect(isNewerVersion('1.0.2', '1.1.0'), isFalse);
    });

    test('按平台挑选更新包', () {
      const release = ReleaseInfo(
        version: '1.1.0',
        tagName: 'v1.1.0',
        notes: '',
        htmlUrl: '',
        assets: [
          ReleaseAsset(
            name: 'WeLearn-1.1.0-portable.zip',
            downloadUrl: 'https://example.com/a.zip',
            size: 1,
          ),
          ReleaseAsset(
            name: 'WeLearn-Setup-1.1.0.exe',
            downloadUrl: 'https://example.com/a.exe',
            size: 1,
          ),
          ReleaseAsset(
            name: 'welearn-app-1.1.0.apk',
            downloadUrl: 'https://example.com/a.apk',
            size: 1,
          ),
        ],
      );
      expect(
        selectUpdateAsset(release, UpdateTarget.windows)?.name,
        'WeLearn-Setup-1.1.0.exe',
      );
      expect(
        selectUpdateAsset(release, UpdateTarget.android)?.name,
        'welearn-app-1.1.0.apk',
      );
    });
  });

  group('等待滑条', () {
    test('吸附到 10 秒档位', () {
      expect(snapToStep(301, min: 30, max: 900, step: 10), 300);
      expect(snapToStep(305, min: 30, max: 900, step: 10), 310);
      expect(snapToStep(299, min: 30, max: 900, step: 10), 300);
      expect(snapToStep(30, min: 30, max: 900, step: 10), 30);
      expect(snapToStep(900, min: 30, max: 900, step: 10), 900);
      expect(snapToStep(5000, min: 30, max: 900, step: 10), 900);
    });

    test('旧设置里的等待时长归一化为 10 秒档', () {
      expect(normalizeWaitSeconds(301), 300);
      expect(normalizeWaitSeconds(899), 900);
      expect(normalizeWaitSeconds(300), 300);
      expect(normalizeWaitSeconds(0), 0);
      expect(normalizeWaitSeconds(1200), 1200);
      expect(normalizeWaitSeconds(5000), 1200);
    });

    test('区间两端相等时取固定值，不再随机', () {
      final rng = Random(7);
      expect(pickWait(300, 300, rng), 300);
      expect(pickCrate(100, 100, rng), 100);
      expect(pickInterval(0, 0, rng), 0);
    });
  });

  group('断点续等', () {
    test('登录失效重试从断点继续，不重复累计 total_time', () async {
      final api = _KeepScoApi();
      final outcome = await runKeepalive(
        api: api,
        meta: const CourseMeta(cid: '1', uid: '2', classid: '3'),
        scoid: 's1',
        totalBefore: 100,
        targetSec: 2,
        token: CancelToken(),
        startElapsed: 1,
        startHeartbeats: 1,
      );

      expect(outcome.elapsed, 2);
      expect(outcome.heartbeats, 2, reason: '断点前的心跳次数保留');
      expect(api.totalTimes, [101], reason: '只加断点之后新增的 1 秒');
    });

    test('重试时已经等满，不再补心跳', () async {
      final api = _KeepScoApi();
      final outcome = await runKeepalive(
        api: api,
        meta: const CourseMeta(cid: '1', uid: '2', classid: '3'),
        scoid: 's1',
        totalBefore: 100,
        targetSec: 1,
        token: CancelToken(),
        startElapsed: 1,
        startHeartbeats: 1,
      );

      expect(outcome.elapsed, 1);
      expect(api.totalTimes, isEmpty);
    });
  });

  group('口语题识别', () {
    test('Listening & Speaking 标题识别为口语小节', () {
      const lesson = Lesson(
        unitIndex: 2,
        scoid: 'x',
        location: 'Unit 3 > Text A: Listening & Speaking > Task 4',
        visible: true,
        complete: false,
        learnTime: '',
        crateLabel: '-',
      );
      expect(isOralLesson(lesson), isTrue);
    });

    test('普通阅读小节不会被口语关键词误判', () {
      const lesson = Lesson(
        unitIndex: 2,
        scoid: 'y',
        location: 'Unit 3 > Text B: Reading',
        visible: true,
        complete: false,
        learnTime: '',
        crateLabel: '-',
      );
      expect(isOralLesson(lesson), isFalse);
    });

    test('页面含录音控件时标记为口语页', () {
      final parsed = parseSco(
        '<html><body><div class="record-button">按住录音</div></body></html>',
      );
      expect(parsed.oralPage, isTrue);
      expect(parsed.questions, isEmpty);
    });

    test('普通阅读页不会被误判为口语', () {
      final parsed = parseSco(
        '<html><body><div data-controltype="filling">'
        '<input data-solution="hello"></div></body></html>',
      );
      expect(parsed.oralPage, isFalse);
      expect(parsed.questions.length, 1);
    });
  });

  group('最近完成时间', () {
    test('相对时间在一天内用分钟 / 小时', () {
      final now = DateTime(2026, 11, 7, 12, 30);
      expect(
        relativeTimeText(now.subtract(const Duration(seconds: 20)), now: now),
        '刚刚',
      );
      expect(
        relativeTimeText(now.subtract(const Duration(minutes: 5)), now: now),
        '5 分钟前',
      );
      expect(
        relativeTimeText(now.subtract(const Duration(hours: 3)), now: now),
        '3 小时前',
      );
    });

    test('超过一天显示具体时间，跨年带年份', () {
      final now = DateTime(2026, 11, 7, 12, 30);
      expect(
        relativeTimeText(now.subtract(const Duration(days: 2)), now: now),
        '11 月 5 日 12:30',
      );
      expect(
        relativeTimeText(DateTime(2025, 12, 31, 20, 15), now: now),
        '2025-12-31 20:15',
      );
    });
  });

  group('自动重登密码编码', () {
    test('按平台格式拼出时间戳与密码 hex', () {
      final encoded = encodeLoginPassword(
        'abc',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(encoded.timestamp, 1700000000033);
      expect(
        utf8.decode(base64Decode(encoded.pwd)),
        '1700000000033*616263',
      );
    });

    test('非 ASCII 密码按 UTF-8 字节编码', () {
      final encoded = encodeLoginPassword(
        '密',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final decoded = utf8.decode(base64Decode(encoded.pwd));
      expect(decoded.split('*').last, 'e5af86');
    });
  });

  group('账号凭据序列化', () {
    test('含账号密码的保存账号可往返', () {
      final account = SavedAccount(
        id: 'u1',
        cookie: '.AspNet.Cookies=ticket',
        savedAt: DateTime(2026, 11, 8, 10, 30),
        uid: '10000001',
        username: 'alice',
        password: 'secret',
      );
      final back = SavedAccount.fromJson(account.toJson());
      expect(back, isNotNull);
      expect(back!.id, 'u1');
      expect(back.cookie, '.AspNet.Cookies=ticket');
      expect(back.uid, '10000001');
      expect(back.username, 'alice');
      expect(back.password, 'secret');
      expect(back.hasCredentials, isTrue);
    });

    test('withoutCredentials 清空密码但保留 Cookie 与 UID', () {
      final account = SavedAccount(
        id: 'u1',
        cookie: 'c=1',
        savedAt: DateTime(2026, 11, 8),
        uid: '10000001',
        username: 'alice',
        password: 'secret',
      );
      final stripped = account.withoutCredentials();
      expect(stripped.cookie, 'c=1');
      expect(stripped.uid, '10000001');
      expect(stripped.username, isNull);
      expect(stripped.password, isNull);
      expect(stripped.hasCredentials, isFalse);
    });

    test('只有 Cookie 时不算已记录账号密码', () {
      final account = SavedAccount(
        id: 'u1',
        cookie: 'c=1',
        savedAt: DateTime(2026, 11, 8),
      );
      expect(account.hasCredentials, isFalse);
      expect(SavedAccount.fromJson(account.toJson())?.hasCredentials, isFalse);
    });
  });

  group('运行历史序列化', () {
    test('LessonResult 往返保留完成时间与统计', () {
      final result = LessonResult(
        scoid: 'x',
        status: LessonStatus.done,
        crate: 100,
        waitSec: 300,
        heartbeats: 5,
        stat: const LessonStat(questions: 12, oral: 3, answered: 10),
        finishedAt: DateTime(2026, 11, 8, 9, 30),
      );
      final back = LessonResult.fromJson(result.toJson());
      expect(back, isNotNull);
      expect(back!.scoid, 'x');
      expect(back.status, LessonStatus.done);
      expect(back.stat.questions, 12);
      expect(back.finishedAt, DateTime(2026, 11, 8, 9, 30));
    });

    test('损坏的历史记录返回 null', () {
      expect(LessonResult.fromJson(null), isNull);
      expect(LessonResult.fromJson({'scoid': ''}), isNull);
    });

    test('LogEntry 往返保留等级、内容与时间', () {
      final entry = LogEntry(
        'warn',
        '登录态失效',
        time: DateTime(2026, 11, 8, 9, 30, 5),
      );
      final back = LogEntry.fromJson(entry.toJson());
      expect(back, isNotNull);
      expect(back!.level, 'warn');
      expect(back.message, '登录态失效');
      expect(back.time, DateTime(2026, 11, 8, 9, 30, 5));
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

  group('单元名', () {
    test('U01 / U02 解析成 Unit 1 / Unit 2', () {
      expect(parseUnitNumber('U01'), 1);
      expect(parseUnitNumber('U02'), 2);
      expect(parseUnitNumber('Unit 03'), 3);
      expect(parseUnitNumber('Unit 12'), 12);
      expect(parseUnitNumber('第 3 单元'), 3);
      expect(parseUnitNumber('1'), 1);
      expect(parseUnitNumber('听说教程'), isNull);

      CourseUnit unit(String name) =>
          CourseUnit(index: 0, unitName: name, name: '', visible: true);
      expect(unit('U01').label, 'Unit 1');
      expect(unit('U02').label, 'Unit 2');
      expect(unit('Unit 3 > Warm-up').label, 'Unit 3');
      expect(unit('听说教程').label, '听说教程');
    });

    test('小节 location 的 U01 前缀也能去掉', () {
      const lesson = Lesson(
        unitIndex: 0,
        scoid: 'x',
        location: 'U01 > Warm-up Activities',
        visible: true,
        complete: false,
        learnTime: '',
        crateLabel: '-',
      );
      expect(displayLocation(lesson), 'Unit 1 > Warm-up Activities');
      expect(shortLocation(lesson), 'Warm-up Activities');
    });

    test('完整位置会把各种单元前缀统一成 Unit N', () {
      const cases = [
        ('Unit 01 > Reading', 'Unit 1 > Reading'),
        ('U02> Listening', 'Unit 2 > Listening'),
        ('第 3 单元 > Speaking', 'Unit 3 > Speaking'),
        ('Unit 12 > Writing', 'Unit 12 > Writing'),
      ];
      for (final (raw, expected) in cases) {
        final lesson = Lesson(
          unitIndex: 0,
          scoid: 'x',
          location: raw,
          visible: true,
          complete: false,
          learnTime: '',
          crateLabel: '-',
        );
        expect(displayLocation(lesson), expected, reason: raw);
      }
      const noPrefix = Lesson(
        unitIndex: 0,
        scoid: 'x',
        location: 'Listening & Speaking',
        visible: true,
        complete: false,
        learnTime: '',
        crateLabel: '-',
      );
      expect(displayLocation(noPrefix), 'Listening & Speaking');
    });
  });

  group('头像地址解析', () {
    const base = 'https://welearn.sflep.com';
    test('img 带头像 class 时优先取它', () {
      expect(
        findAvatarUrl(
          '<img class="logo" src="/img/logo.png">'
          '<img class="user-avatar" src="/Upload/UserPhoto/a.jpg">',
          base,
        ),
        'https://welearn.sflep.com/Upload/UserPhoto/a.jpg',
      );
    });
    test('脚本里的 JSON 字段', () {
      expect(
        findAvatarUrl(
          '<script>var u={"headimg":"/upload/p/2.png"}</script>',
          base,
        ),
        'https://welearn.sflep.com/upload/p/2.png',
      );
    });
    test('只有 logo 时不当头像', () {
      expect(
        findAvatarUrl('<img class="logo" src="/img/logo.png">', base),
        isNull,
      );
    });
    test('协议相对地址', () {
      expect(
        findAvatarUrl('<img id="avatar" src="//cdn.example.com/a.jpg">', base),
        'https://cdn.example.com/a.jpg',
      );
    });
    test('CSS background-image 形式的头像', () {
      expect(
        findAvatarUrl(
          '<div class="user-photo" '
          'style="background-image:url(/Upload/UserPhoto/b.jpg)"></div>',
          base,
        ),
        'https://welearn.sflep.com/Upload/UserPhoto/b.jpg',
      );
    });
    test('懒加载头像', () {
      expect(
        findAvatarUrl(
          '<img class="avatar" src="/img/blank.png" '
          'data-original="/Upload/UserPhoto/c.jpg">',
          base,
        ),
        'https://welearn.sflep.com/Upload/UserPhoto/c.jpg',
      );
    });
  });

  group('更新说明 Markdown', () {
    test('标题与列表被拆成可排版的块', () {
      final blocks = parseReleaseNotes(
        '## WeLearn 助手 1.1.6\n\n### 本次更新\n\n- 任务页单元组头吸顶\n- 面板字号调大\n',
      );
      expect(blocks.map((b) => b.type).toList(), [
        NoteBlockType.heading,
        NoteBlockType.heading,
        NoteBlockType.bullet,
        NoteBlockType.bullet,
      ]);
      expect(blocks[0].text, 'WeLearn 助手 1.1.6');
      expect(blocks[0].level, 2);
      expect(blocks[1].level, 3);
      expect(blocks[2].text, '任务页单元组头吸顶');
    });

    test('表格跳过表头与分隔行，数据行拼成一行', () {
      final blocks = parseReleaseNotes(
        '| 平台 | 文件 | 说明 |\n| --- | --- | --- |\n| Windows | `Setup.exe` | 安装版 |\n',
      );
      expect(blocks.length, 1);
      expect(blocks.single.text, 'Windows · Setup.exe · 安装版');
    });

    test('去掉行内标记但保留可读文字', () {
      final blocks = parseReleaseNotes(
        '**重点**说明与 [链接](https://example.com) 保留\n',
      );
      expect(blocks.single.text, '重点说明与 链接 保留');
    });

    test('空内容不产生块', () {
      expect(parseReleaseNotes('  \n\n'), isEmpty);
    });
  });
}

/// 只记录心跳上报的 total_time，用来验证登录失效后的断点续等累计口径。
class _KeepScoApi extends Api {
  _KeepScoApi()
      : super(
          Session(
            baseUrl: 'https://welearn.sflep.com',
            userAgent: 'test-agent',
          ),
        );

  final List<int> totalTimes = [];

  @override
  Future<bool> keepSco(
    CourseMeta meta,
    String scoid, {
    required int sessionTime,
    required int totalTime,
  }) async {
    totalTimes.add(totalTime);
    return true;
  }
}
