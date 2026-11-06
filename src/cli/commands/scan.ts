import { ConfigError } from '../../core/errors.js';
import { scanCourse } from '../../core/plan/scanner.js';
import { getCourseMeta } from '../../core/api/study.js';
import { buildSession } from '../session-factory.js';
import { writeJson, writeResult, type CliContext } from '../context.js';

export interface ScanFlags {
  course: string;
  unit?: string;
  /** commander 的 --no-skip-oral 会把 skipOral 默认置 true */
  skipOral?: boolean;
}

export async function scanCommand(flags: ScanFlags, ctx: CliContext): Promise<number> {
  if (!flags.course) throw new ConfigError('缺少 --course <cid>，可先运行 `welearn-cli login` 查看课程 ID');

  const unit = parseUnit(flags.unit);
  const { session } = buildSession(ctx.config, ctx.sessionSource, ctx.logger);

  ctx.logger.info(`课程 cid=${flags.course}`);
  const meta = await getCourseMeta(session, flags.course, { signal: ctx.signal, logger: ctx.logger });

  const result = await scanCourse(
    session,
    {
      cid: flags.course,
      uid: meta.uid,
      classid: meta.classid,
      unit,
      skipOralLesson: flags.skipOral !== false,
    },
    { signal: ctx.signal, logger: ctx.logger },
  );

  for (const warning of result.warnings) ctx.logger.warn(warning);

  if (ctx.json) {
    writeJson({
      ok: true,
      course: { cid: flags.course, uid: meta.uid, classid: meta.classid },
      stats: result.stats,
      warnings: result.warnings,
      units: result.units,
      lessons: result.lessons,
      candidates: result.candidates.map((l) => l.scoid),
    });
    return 0;
  }

  const { stats } = result;
  writeResult(`课程 cid=${flags.course}  uid=${meta.uid}  classid=${meta.classid}`);
  writeResult(
    `共 ${stats.units} 单元 / ${stats.lessons} 小节：已完成 ${stats.completed}，未完成 ${
      stats.lessons - stats.completed - stats.invisible
    }，隐藏 ${stats.invisible}`,
  );
  if (stats.oralSkipped > 0) writeResult(`跳过口语小节：${stats.oralSkipped}`);
  writeResult(`待处理队列：${stats.candidates} 节`);
  writeResult('');

  for (const unit of result.units) {
    const inUnit = result.lessons.filter((l) => l.unitIndex === unit.index);
    if (inUnit.length === 0) continue;
    const done = inUnit.filter((l) => l.complete).length;
    const left = result.candidates.filter((l) => l.unitIndex === unit.index).length;
    writeResult(
      `  ${unit.unitName.padEnd(9)} ${String(inUnit.length).padStart(3)} 节   已完成 ${String(done).padStart(3)}   待处理 ${String(
        left,
      ).padStart(3)}`,
    );
  }

  writeResult('');
  writeResult(`下一步：welearn-cli run --course ${flags.course} --dry-run   # 只解析不提交`);
  return 0;
}

function parseUnit(raw: string | undefined): 'all' | number {
  if (!raw || raw === 'all') return 'all';
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1) {
    throw new ConfigError(`--unit 只接受正整数或 all，收到：${raw}`);
  }
  return n;
}
