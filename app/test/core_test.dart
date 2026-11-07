import 'package:flutter_inappwebview/flutter_inappwebview.dart' show Cookie;
import 'package:flutter_test/flutter_test.dart';
import 'package:welearn_app/app_state.dart';
import 'package:welearn_app/core/api.dart';
import 'package:welearn_app/core/browser_login.dart';
import 'package:welearn_app/core/models.dart';
import 'package:welearn_app/core/parser.dart';
import 'package:welearn_app/core/scorm.dart';
import 'package:welearn_app/core/updater.dart';
import 'package:welearn_app/ui/components.dart' show snapToStep;

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
    test('只吸附到偶数档位', () {
      expect(snapToStep(301, min: 30, max: 900, step: 2), 302);
      expect(snapToStep(303, min: 30, max: 900, step: 2), 304);
      expect(snapToStep(299, min: 30, max: 900, step: 2), 300);
      expect(snapToStep(30, min: 30, max: 900, step: 2), 30);
      expect(snapToStep(900, min: 30, max: 900, step: 2), 900);
      expect(snapToStep(5000, min: 30, max: 900, step: 2), 900);
    });

    test('旧设置里的奇数等待时长归一化为偶数', () {
      expect(normalizeWaitSeconds(301), 302);
      expect(normalizeWaitSeconds(899), 900);
      expect(normalizeWaitSeconds(300), 300);
      expect(normalizeWaitSeconds(0), 30);
      expect(normalizeWaitSeconds(1200), 900);
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
}
