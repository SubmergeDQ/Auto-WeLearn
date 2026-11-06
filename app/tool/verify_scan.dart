import 'dart:convert';
import 'dart:io';

import 'package:welearn_app/core/api.dart';
import 'package:welearn_app/core/runner.dart';
import 'package:welearn_app/core/session.dart';

/// 只读联调脚本：用 GUI 已保存的 Cookie 跑一遍 登录 → 扫描，确认接口链路可用。
/// 用法：dart run tool/verify_scan.dart
Future<void> main() async {
  final file = File(
    '${Platform.environment['APPDATA']}/cn.autowelearn/welearn_app/app_state.json',
  );
  if (!file.existsSync()) {
    stdout.writeln('找不到 app_state.json');
    exit(1);
  }
  final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final cookie = (data['cookie'] as String?) ?? '';
  if (cookie.isEmpty) {
    stdout.writeln('本地没有保存 Cookie，请先在 GUI 登录');
    exit(1);
  }
  stdout.writeln('读取到本地 Cookie（${cookie.length} 字符，不打印内容）');

  final session = Session(
    baseUrl: 'https://welearn.sflep.com',
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  );

  final cookies = <String, String>{};
  for (final seg in cookie.split(';')) {
    final part = seg.trim();
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    cookies[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
  }
  session.setCookies(cookies);

  final api = Api(session);
  final courses = await api.listCourses();
  stdout.writeln(
    '课程数 ${courses.length}：${courses.map((c) => '${c.cid}/${c.name}/${c.percent}%').join('，')}',
  );

  final cid = courses.first.cid;
  final meta = await api.getCourseMeta(cid);
  stdout.writeln('uid=${meta.uid} classid=${meta.classid}');

  final scan = await scanCourse(
    api,
    meta: meta,
    skipOralLesson: true,
    onLog: (m) => stdout.writeln('  $m'),
  );
  stdout.writeln(
    '单元 ${scan.units.length} / 小节 ${scan.lessons.length} / 待处理 ${scan.candidates.length}',
  );
  for (final w in scan.warnings.take(5)) {
    stdout.writeln('warn: $w');
  }
}
