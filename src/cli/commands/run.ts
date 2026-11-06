import { ConfigError } from '../../core/errors.js';
import { getCourseMeta } from '../../core/api/study.js';
import { scanCourse } from '../../core/plan/scanner.js';
import { prepareLesson } from '../../core/run/prepare.js';
import { formatClock, formatDuration } from '../../logging/logger.js';
import { parseRunFlags, type RawRunFlags } from '../parse-run-flags.js';
import { buildSession } from '../session-factory.js';
import { writeJson, writeResult, type CliContext } from '../context.js';
import type { Lesson } from '../../types/domain.js';

export interface RunFlags extends RawRunFlags {
  course: string;
}

/**
 * 主流程入口。批次 A 只交付 dry-run 分支：
 * 完整走一遍扫描 + 解析，但不发任何写请求，也不等待。
 */
export async function runCommand(flags: RunFlags, ctx: CliContext): Promise<number> {
  const config = parseRunFlags(flags, ctx.config.statePath);

  if (!config.dryRun) {
    throw new ConfigError(
      '真实提交将在批次 B（M4/M5）交付。当前请先加 --dry-run 验证解析结果，确认无误后再等待提交能力',
    );
  }

  const { session } = buildSession(ctx.config, ctx.sessionSource, ctx.logger);
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

  const queue = config.maxLessons ? scan.candidates.slice(0, config.maxLessons) : scan.candidates;

  ctx.logger.info(
    `扫描完成：${scan.stats.units} 单元 / ${scan.stats.lessons} 小节 / 待处理 ${scan.stats.candidates}`,
  );
  ctx.logger.info(`dry-run：本次只解析 ${queue.length} 节，预计总等待 ${estimate(config, queue.length)}（不实际等待）`);

  const results: Array<{
    scoid: string;
    location: string;
    strategy: string;
    questions: number;
    oral: number;
    status: 'dry-run' | 'failed';
    warnings: string[];
  }> = [];

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
        { cid: config.course, scoid: lesson.scoid, classid: meta.classid },
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

      results.push({
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
      results.push({
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
      course: { cid: config.course, uid: meta.uid, classid: meta.classid },
      stats: { lessons: results.length, questions: totalQuestions, oral: totalOral, failed },
      lessons: results,
    });
    return failed > 0 ? 1 : 0;
  }

  writeResult('');
  writeResult(
    `dry-run 完成：解析 ${results.length} 节 / ${totalQuestions} 题（跳过口语 ${totalOral}）${
      failed > 0 ? `，失败 ${failed} 节` : ''
    }`,
  );
  writeResult('未产生任何写请求（startsco / setscoinfo / savescoinfo 均未调用）');
  if (failed > 0) writeResult('存在解析失败的小节，请用 `inspect --sco <id>` 单独排查');

  return failed > 0 ? 1 : 0;
}

function shortLocation(lesson: Lesson): string {
  return lesson.location.replace(/^Unit \d+\s*>\s*/i, '');
}

function pickWait(wait: { mode: 'fixed'; seconds: number } | { mode: 'range'; min: number; max: number }): number {
  return wait.mode === 'fixed' ? wait.seconds : Math.round((wait.min + wait.max) / 2);
}

function estimate(config: ReturnType<typeof parseRunFlags>, count: number): string {
  const avg = pickWait(config.wait);
  return formatDuration(avg * count);
}
