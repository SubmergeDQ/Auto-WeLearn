import 'dart:convert';
import 'dart:io';

import 'package:welearn_app/core/api.dart';
import 'package:welearn_app/core/models.dart';
import 'package:welearn_app/core/runner.dart';
import 'package:welearn_app/core/session.dart';

/// 真实单节联调：用本地 Cookie 扫描后，挑第一节未完成的小节完整跑一遍
/// （解析 → startsco → 心跳 → setscoinfo → savescoinfo）。
/// 用法：dart run tool/verify_run.dart [等待秒数]
Future<void> main(List<String> args) async {
  final waitSec = args.isNotEmpty ? int.parse(args.first) : 60;

  final file = File('${Platform.environment['APPDATA']}/cn.autowelearn/welearn_app/app_state.json');
  final cookie = (jsonDecode(await file.readAsString()) as Map<String, dynamic>)['cookie'] as String? ?? '';
  if (cookie.isEmpty) {
    stdout.writeln('本地没有 Cookie');
    exit(1);
  }

  final session = Session(
    baseUrl: 'https://welearn.sflep.com',
    userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
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
  final cid = courses.first.cid;
  final meta = await api.getCourseMeta(cid);
  final scan = await scanCourse(api, meta: meta, skipOralLesson: true, onLog: (m) => stdout.writeln('  $m'));
  stdout.writeln('扫描：单元 ${scan.units.length} / 小节 ${scan.lessons.length} / 待处理 ${scan.candidates.length}');
  if (scan.candidates.isEmpty) {
    stdout.writeln('没有待处理小节');
    exit(0);
  }

  final lesson = scan.candidates.first;
  stdout.writeln('目标：${lesson.scoid}  ${lesson.location}');
  stdout.writeln('等待 ${waitSec}s 后提交…');

  final result = await runLesson(
    api: api,
    meta: meta,
    lesson: lesson,
    crate: 100,
    waitSec: waitSec,
    settings: const RunSettings(),
    token: CancelToken(),
    onLog: (level, message) => stdout.writeln('  [$level] $message'),
    onTick: (elapsed, beats) {
      if (elapsed % 20 == 0) stdout.writeln('  tick ${elapsed}s / ${waitSec}s  心跳 $beats');
    },
  );

  stdout.writeln('结果：${result.status.name}  题 ${result.stat.answered}/${result.stat.questions}  '
      '用时 ${result.waitSec}s  心跳 ${result.heartbeats} 次  ${result.errorMessage ?? ''}');
  exit(result.status == LessonStatus.done ? 0 : 1);
}
