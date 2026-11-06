import 'dart:convert';

import 'errors.dart';
import 'models.dart';
import 'session.dart';

/// 平台接口封装。字段坑位见 docs/NODE_CLI_SPEC.md 附录 C。
class Api {
  Api(this.session);
  final Session session;

  String get _base => session.baseUrl;

  String get _refIndex => '$_base/student/index.aspx';
  String _refCourse(String cid) => '$_base/student/course_info.aspx?cid=$cid';
  String _refStudy(String cid, String classid, String scoid) =>
      '$_base/Student/StudyCourse.aspx?cid=$cid&classid=$classid&sco=$scoid';

  // ── 课程 ─────────────────────────────────────────────
  Future<List<Course>> listCourses() async {
    final res = await session.get(
      '/ajax/authCourse.aspx?action=gmc',
      referer: _refIndex,
    );
    _guardLogin(res);
    final payload = _json(res.text, '课程列表');
    final ret = payload['ret'];
    if (ret is int && ret != 0) {
      throw AppException(
        AppErrorCode.contractChanged,
        '课程列表返回 ret=$ret${payload['mess'] != null ? '（${payload['mess']}）' : ''}',
      );
    }
    final raw = payload['clist'];
    if (raw is! List || raw.isEmpty) {
      throw AppException(AppErrorCode.badCredentials, 'Cookie 无效或该账号下没有课程');
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(
          (e) => Course(
            cid: '${e['cid']}',
            name: e['name'] as String? ?? '课程 ${e['cid']}',
            percent: (e['per'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  // ── 课程结构 ──────────────────────────────────────────
  Future<CourseMeta> getCourseMeta(String cid) async {
    final res = await session.get(
      '/student/course_info.aspx?cid=$cid',
      referer: _refIndex,
    );
    _guardLogin(res);
    final uid = RegExp(r'"uid"\s*:\s*(\d+)').firstMatch(res.text)?.group(1);
    final classid = RegExp(r'"classid"\s*:\s*"([^"]*)"')
        .firstMatch(res.text)
        ?.group(1);
    if (uid == null || classid == null) {
      throw AppException(
        AppErrorCode.contractChanged,
        '课程详情页解析失败：未找到 uid 或 classid',
      );
    }
    return CourseMeta(cid: cid, uid: uid, classid: classid);
  }

  Future<List<CourseUnit>> getUnits(String cid, String uid) async {
    final res = await session.get(
      '/ajax/StudyStat.aspx?action=courseunits&cid=$cid&uid=$uid',
      referer: _refCourse(cid),
    );
    _guardLogin(res);
    final payload = _json(res.text, '单元列表');
    final info = payload['info'];
    if (info is! List) return const [];
    var index = 0;
    return info.whereType<Map<String, dynamic>>().map((e) {
      final unit = CourseUnit(
        index: index++,
        unitName: e['unitname'] as String? ?? 'Unit',
        name: e['name'] as String? ?? '',
        visible: '${e['visible']}'.toLowerCase() == 'true',
      );
      return unit;
    }).toList();
  }

  /// 返回 null 表示接口异常（正文含「异常」「出错了」），调用方必须停止遍历
  Future<List<Lesson>?> getLessons({
    required String cid,
    required String uid,
    required String classid,
    required int unitIndex,
  }) async {
    final res = await session.get(
      '/ajax/StudyStat.aspx?action=scoLeaves&cid=$cid&uid=$uid&unitidx=$unitIndex&classid=$classid',
      referer: _refCourse(cid),
    );
    _guardLogin(res);
    if (res.text.contains('异常') || res.text.contains('出错了')) return null;

    final payload = _json(res.text, '小节列表');
    final ret = payload['ret'];
    if (ret is int && ret != 0) return null;

    final info = payload['info'];
    if (info is! List) return const [];
    return info.whereType<Map<String, dynamic>>().map((e) {
      final completeText = '${e['iscomplete'] ?? ''}';
      return Lesson(
        unitIndex: unitIndex,
        scoid: '${e['id']}',
        location:
            e['location'] as String? ?? e['name'] as String? ?? '${e['id']}',
        visible: '${e['isvisible'] ?? 'true'}'.toLowerCase() == 'true',
        complete: completeText.contains('已') && !completeText.contains('未'),
        learnTime: e['learntime'] as String? ?? '',
        crateLabel: '${e['crate'] ?? ''}',
      );
    }).toList();
  }

  // ── SCO 读 ────────────────────────────────────────────
  Future<ScoAddress?> getScoAddr({
    required String cid,
    required String scoid,
    required String classid,
  }) async {
    final text = await postScoAction({
      'action': 'scoAddr',
      'cid': cid,
      'scoid': scoid,
    }, referer: _refStudy(cid, classid, scoid));
    final payload = _json(text, 'scoAddr');
    final addr = payload['addr'] as String?;
    if (addr == null || payload['ret'] != 0) return null;
    final parts = addr.split('|');
    final part = parts.first;
    if (part.isEmpty) return null;
    final url = part.startsWith('//')
        ? '${_base.startsWith('http://') ? 'http:' : 'https:'}$part'
        : part;
    return ScoAddress(
      url: url,
      location: parts.length > 1 ? parts[1].trim() : '',
    );
  }

  Future<String?> fetchTemplate(String url) async {
    try {
      final res = await session.get(url, referer: '$_base/');
      if (res.status != 200) return null;
      return res.text;
    } on AppException catch (e) {
      if (e.isInterrupted) rethrow;
      return null;
    }
  }

  // ── SCO 写 ────────────────────────────────────────────
  Future<String> postScoAction(
    Map<String, String> form, {
    required String referer,
  }) async {
    final res = await session.postForm(
      '/Ajax/SCO.aspx',
      form,
      referer: referer,
    );
    _guardLogin(res);
    return res.text;
  }

  Future<bool> startSco(CourseMeta meta, String scoid) async {
    final text = await postScoAction({
      'action': 'startsco160928',
      'cid': meta.cid,
      'scoid': scoid,
      'uid': meta.uid,
    }, referer: _refStudy(meta.cid, meta.classid, scoid));
    return isRetOk(text);
  }

  Future<bool> setScoInfo(CourseMeta meta, String scoid, String data) async {
    final text = await postScoAction({
      'action': 'setscoinfo',
      'cid': meta.cid,
      'scoid': scoid,
      'uid': meta.uid,
      'data': data,
      'isend': 'False',
    }, referer: _refStudy(meta.cid, meta.classid, scoid));
    return isRetOk(text);
  }

  Future<bool> saveScoInfo(
    CourseMeta meta,
    String scoid, {
    required int crate,
    required int sessionTime,
    required int totalTime,
  }) async {
    final text = await postScoAction({
      'action': 'savescoinfo160928',
      'cid': meta.cid,
      'scoid': scoid,
      'uid': meta.uid,
      'progress': '100',
      'crate': '$crate',
      'status': 'unknown',
      'cstatus': 'completed',
      'trycount': '0',
      'session_time': '$sessionTime',
      'total_time': '$totalTime',
    }, referer: _refStudy(meta.cid, meta.classid, scoid));
    return isRetOk(text);
  }

  Future<bool> keepSco(
    CourseMeta meta,
    String scoid, {
    required int sessionTime,
    required int totalTime,
  }) async {
    final text = await postScoAction({
      'action': 'keepsco_with_getticket_with_updatecmitime',
      'uid': meta.uid,
      'cid': meta.cid,
      'scoid': scoid,
      'session_time': '$sessionTime',
      'total_time': '$totalTime',
    }, referer: _refStudy(meta.cid, meta.classid, scoid));
    return isRetOk(text);
  }

  /// 读 CMI 历史累计。未学过的小节返回 `ret:-1 / 学习数据不正确`，属于正常状态。
  Future<CmiRead> readCmi(CourseMeta meta, String scoid) async {
    final text = await postScoAction({
      'action': 'getscoinfo_v7',
      'uid': meta.uid,
      'cid': meta.cid,
      'scoid': scoid,
    }, referer: _refStudy(meta.cid, meta.classid, scoid));
    final uninitialized = text.contains('学习数据不正确');
    try {
      final outer = jsonDecode(text) as Map<String, dynamic>;
      final comment = outer['comment'];
      if (comment is String) {
        final inner = jsonDecode(comment) as Map<String, dynamic>;
        final cmi = inner['cmi'];
        if (cmi is Map<String, dynamic>) {
          return CmiRead.ok(parseScormTime(cmi['total_time']));
        }
      }
    } catch (_) {
      // 落到下面的分类
    }
    return CmiRead.fail(uninitialized ? 'uninitialized' : 'unavailable');
  }

  // ── 工具 ──────────────────────────────────────────────
  /// 登录墙特征。
  static final RegExp _loginWall = RegExp(
    "/user/prelogin\\.aspx|/Account/Login|name=[\"']Account[\"']",
    caseSensitive: false,
  );

  /// 只看正文前 4000 字符。
  ///
  /// 课程详情页（course_info.aspx）是一整页 HTML，页面靠后的脚本/页脚里也会出现
  /// `/Account/Login` 这类字符串。全文扫描会把正常页面误判成"会话失效"——
  /// 这正是 GUI 版登录成功却扫不出任何小节的原因。CLI 版用 4000 字符窗口，所以没踩到。
  void _guardLogin(SessionResponse res) {
    if (res.status == 401 || res.status == 403) {
      throw AppException(AppErrorCode.authExpired, '登录态已失效，请重新登录');
    }
    final head = res.text.length > 4000
        ? res.text.substring(0, 4000)
        : res.text;
    if (_loginWall.hasMatch(head)) {
      throw AppException(AppErrorCode.authExpired, '登录态已失效，请重新登录');
    }
  }

  Map<String, dynamic> _json(String text, String context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw AppException(AppErrorCode.contractChanged, '$context：响应为空');
    }
    try {
      final value = jsonDecode(trimmed);
      if (value is Map<String, dynamic>) return value;
      throw AppException(AppErrorCode.contractChanged, '$context：响应不是 JSON 对象');
    } on FormatException {
      throw AppException(
        AppErrorCode.contractChanged,
        '$context：响应不是合法 JSON，前 120 字符为 ${trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed}',
      );
    }
  }
}

class ScoAddress {
  ScoAddress({required this.url, required this.location});
  final String url;
  final String location;
}

class CmiRead {
  CmiRead._(this.ok, this.totalBefore, this.reason);
  factory CmiRead.ok(int totalBefore) => CmiRead._(true, totalBefore, null);
  factory CmiRead.fail(String reason) => CmiRead._(false, 0, reason);
  final bool ok;
  final int totalBefore;
  final String? reason;
}

bool isRetOk(String text) => RegExp(r'"ret"\s*:\s*0').hasMatch(text);

int parseScormTime(Object? value) {
  if (value is num) return value.round().clamp(0, 1 << 31);
  if (value is! String) return 0;
  final text = value.trim();
  if (text.isEmpty) return 0;
  if (RegExp(r'^\d+$').hasMatch(text)) return int.parse(text);
  final clock = RegExp(r'^(\d+):([0-5]?\d):([0-5]?\d)$').firstMatch(text);
  if (clock != null) {
    return int.parse(clock.group(1)!) * 3600 +
        int.parse(clock.group(2)!) * 60 +
        int.parse(clock.group(3)!);
  }
  return 0;
}
