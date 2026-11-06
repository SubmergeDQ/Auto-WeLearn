import { ConfigError, toAppError } from '../../core/errors.js';
import { getCourseMeta } from '../../core/api/study.js';
import { scanCourse } from '../../core/plan/scanner.js';
import { prepareLesson } from '../../core/run/prepare.js';
import { runLesson } from '../../core/run/lesson-runner.js';
import { estimateDuration, pickCrate, pickInterval, pickWait } from '../../core/plan/time-plan.js';
import { emptyState, isFinished, loadState, recordLesson, saveState } from '../../core/state/store.js';
import { interruptibleSleep } from '../../core/sleep.js';
import { formatClock, formatDuration } from '../../logging/logger.js';
import { parseRunFlags, type RawRunFlags } from '../parse-run-flags.js';
import { buildSession } from '../session-factory.js';
import { writeJson, writeResult, type CliContext } from '../context.js';
import type { Lesson, LessonResult } from '../../types/domain.js';

export interface RunFlags extends RawRunFlags {
  course: string;
}

interface DryRunEntry {
  scoid: string;
  location: string;
  strategy: string;
  questions: number;
  oral: number;
  status: 'dry-run' | 'failed';
  warnings: string[];
}

export async function runCommand(flags: RunFlags, ctx: CliContext): Promise<number> {
  const config = parseRunFlags(flags, ctx.config.statePath);
  const { session } = buildSession(ctx.config, ctx.sessionSource, ctx.logger);

  const startedAt = new Date();
  const meta = await getCourseMeta(session, config.course, { signal: ctx.signal, logger: ctx.logger });

  const scan = await scanCourse(
    session,
    {
      cid: config.course,
      uid: meta.uid,
      classid: meta.classid,
      unit: config.unit,
      skipOralLesson: config.skipOralLesson,
    },
    { signal: ctx.signal, logger: ctx.logger },
  );
  for (const warning of scan.warnings) ctx.logger.warn(warning);

  const courseMeta = { cid: config.course, name: `cid=${config.course}`, uid: meta.uid, classid: meta.classid };
  const state = config.resume ? loadState(config.statePath, ctx.logger) : null;
  const runState = state && state.course.cid === config.course ? state : emptyState(courseMeta);

  let queue: Lesson[] = scan.candidates;
  if (config.resume) {
    const before = queue.length;
    queue = queue.filter((l) => !isFinished(runState, l.scoid));
    if (before !== queue.length) {
      ctx.logger.info(`断点续跑：跳过已完成 ${before - queue.length} 节`);
    }
  }
  if (config.maxLessons) queue = queue.slice(0, config.maxLessons);

  ctx.logger.info(
    `扫描完成：${scan.stats.units} 单元 / ${scan.stats.lessons} 小节 / 待处理 ${scan.stats.candidates}`,
  );

  if (queue.length === 0) {
    writeResult('没有需要处理的小节');
    return 0;
  }

  const estimate = estimateDuration(config.wait, config.interval, queue.length);
  ctx.logger.info(
    `队列 ${queue.length} 节，预计耗时 ${formatDuration(estimate.min)} ~ ${formatDuration(estimate.max)}`,
  );

  if (config.dryRun) return dryRun(session, queue, config, meta.classid, ctx);

  return liveRun(session, queue, config, meta.classid, runState, ctx, startedAt);
}

async function dryRun(
  session: ReturnType<typeof buildSession>['session'],
  queue: Lesson[],
  config: ReturnType<typeof parseRunFlags>,
  classid: string,
  ctx: CliContext,
): Promise<number> {
  const entries: DryRunEntry[] = [];
  let totalQuestions = 0;
  let totalOral = 0;
  let failed = 0;

  for (let i = 0; i < queue.length; i++) {
    const lesson = queue[i];
    if (!lesson) continue;

    ctx.logger.stage('RUN', `[${i + 1}/${queue.length}] ${shortLocation(lesson)}  scoid=${lesson.scoid}`);

    try {
      const prep = await prepareLesson(
        session,
        { cid: config.course, scoid: lesson.scoid, classid },
        { signal: ctx.signal, logger: ctx.logger },
      );
      totalQuestions += prep.questions.length;
      totalOral += prep.oral;

      ctx.logger.info(
        `解析 ${prep.questions.length} 题（跳过 ${prep.oral} 道口语题）  策略=${prep.strategy}  等待 ${formatClock(
          pickWait(config.wait),
        )}`,
      );
      for (const warning of prep.warnings.slice(0, 3)) ctx.logger.warn(warning);

      entries.push({
        scoid: lesson.scoid,
        location: lesson.location,
        strategy: prep.strategy,
        questions: prep.questions.length,
        oral: prep.oral,
        status: 'dry-run',
        warnings: prep.warnings,
      });
    } catch (err) {
      failed++;
      const message = err instanceof Error ? err.message : String(err);
      ctx.logger.stage('FAIL', `${lesson.scoid} 解析失败：${message}`);
      entries.push({
        scoid: lesson.scoid,
        location: lesson.location,
        strategy: 'none',
        questions: 0,
        oral: 0,
        status: 'failed',
        warnings: [message],
      });
    }
  }

  if (ctx.json) {
    writeJson({
      ok: failed === 0,
      mode: 'dry-run',
      course: { cid: config.course, classid },
      stats: { lessons: entries.length, questions: totalQuestions, oral: totalOral, failed },
      lessons: entries,
    });
    return failed > 0 ? 1 : 0;
  }

  writeResult('');
  writeResult(
    `dry-run 完成：解析 ${entries.length} 节 / ${totalQuestions} 题（跳过口语 ${totalOral}）${
      failed > 0 ? `，失败 ${failed} 节` : ''
    }`,
  );
  writeResult('未产生任何写请求（startsco / setscoinfo / savescoinfo 均未调用）');
  return failed > 0 ? 1 : 0;
}

async function liveRun(
  session: ReturnType<typeof buildSession>['session'],
  queue: Lesson[],
  config: ReturnType<typeof parseRunFlags>,
  classid: string,
  runState: ReturnType<typeof emptyState>,
  ctx: CliContext,
  startedAt: Date,
): Promise<number> {
  const results: LessonResult[] = [];

  for (let i = 0; i < queue.length; i++) {
    const lesson = queue[i];
    if (!lesson) continue;

    if (ctx.signal.aborted) break;

    const crate = pickCrate(config.rate);
    const waitSec = pickWait(config.wait);

    ctx.logger.stage(
      'RUN',
      `[${i + 1}/${queue.length}] ${shortLocation(lesson)}  scoid=${lesson.scoid}  rate=${crate}%`,
    );

    let result: LessonResult;
    try {
      result = await runLesson({
        session,
        ctx: { cid: config.course, scoid: lesson.scoid, uid: runState.course.uid, classid },
        location: lesson.location,
        crate,
        waitSec,
        retry: { max: ctx.config.retry.max, baseDelayMs: ctx.config.retry.baseDelayMs },
        cmiTime: config.cmiTime,
        signal: ctx.signal,
        logger: ctx.logger,
      });
    } catch (raw) {
      const err = toAppError(raw);
      if (err.code === 'AUTH_EXPIRED') throw err;
      result = {
        scoid: lesson.scoid,
        location: lesson.location,
        status: 'failed',
        crate,
        waitSec: 0,
        heartbeats: 0,
        stats: { questions: 0, oral: 0, answered: 0 },
        attempts: 1,
        errorCode: err.code,
        errorMessage: err.message,
      };
    }

    results.push(result);
    recordLesson(runState, lesson.scoid, {
      status: result.status,
      crate: result.crate,
      waitSec: result.waitSec,
      ...(result.errorCode ? { errorCode: result.errorCode } : {}),
    });
    saveState(config.statePath, runState);

    logResult(ctx, result);

    if (result.status === 'interrupted') break;

    if (i < queue.length - 1 && !ctx.signal.aborted) {
      const gap = pickInterval(config.interval);
      ctx.logger.stage('NEXT', `↳ ${(gap).toFixed(1)}s 后进入下一节`);
      try {
        await interruptibleSleep(gap * 1000, ctx.signal);
      } catch {
        break;
      }
    }
  }

  const finishedAt = new Date();
  const summary = summarize(results);
  const totalSeconds = (finishedAt.getTime() - startedAt.getTime()) / 1000;

  if (ctx.json) {
    writeJson({
      ok: summary.failed === 0 && summary.partial === 0 && summary.interrupted === 0,
      mode: 'run',
      course: { cid: config.course, uid: runState.course.uid, classid },
      startedAt: startedAt.toISOString(),
      finishedAt: finishedAt.toISOString(),
      stats: summary,
      lessons: results,
    });
  } else {
    writeResult('');
    writeResult(
      `完成：成功 ${summary.done} / 部分 ${summary.partial} / 失败 ${summary.failed} / 跳过 ${summary.skipped}  总用时 ${formatDuration(
        totalSeconds,
      )}`,
    );
    if (summary.interrupted > 0) writeResult('已被中断：当前节未提交，下次可用 --resume 续跑');
    if (summary.failed > 0 || summary.partial > 0) {
      for (const r of results.filter((x) => x.status === 'failed' || x.status === 'partial').slice(0, 10)) {
        writeResult(`  ${r.scoid}  ${r.status}  ${r.errorCode ?? ''} ${r.errorMessage ?? ''}`);
      }
    }
  }

  if (summary.interrupted > 0 || ctx.signal.aborted) return 4;
  if (summary.failed > 0 || summary.partial > 0) return 1;
  return 0;
}

function logResult(ctx: CliContext, result: LessonResult): void {
  const stat = `题 ${result.stats.answered}/${result.stats.questions}  用时 ${result.waitSec}s  心跳 ${result.heartbeats} 次`;
  switch (result.status) {
    case 'done':
      ctx.logger.stage('DONE', `提交成功  setscoinfo=ok  savescoinfo=ok  ${stat}`);
      break;
    case 'partial':
      ctx.logger.stage('DONE', `部分成功  ${stat}`);
      break;
    case 'failed':
      ctx.logger.stage('FAIL', `提交失败  ${result.errorCode ?? ''} ${result.errorMessage ?? ''}  ${stat}`);
      break;
    case 'interrupted':
      ctx.logger.stage('SKIP', `已中断，本节未提交  ${stat}`);
      break;
    default:
      ctx.logger.stage('SKIP', `${result.status}  ${stat}`);
  }
}

function summarize(results: LessonResult[]) {
  return {
    done: results.filter((r) => r.status === 'done').length,
    partial: results.filter((r) => r.status === 'partial').length,
    failed: results.filter((r) => r.status === 'failed').length,
    skipped: results.filter((r) => r.status === 'skipped' || r.status === 'dry-run').length,
    interrupted: results.filter((r) => r.status === 'interrupted').length,
  };
}

function shortLocation(lesson: Lesson): string {
  return lesson.location.replace(/^Unit \d+\s*>\s*/i, '');
}

/** 保留给上层统一处理：命令行没给 --course 时给出可读错误 */
export function assertCourse(course: string | undefined): asserts course is string {
  if (!course) throw new ConfigError('缺少 --course <cid>');
}
