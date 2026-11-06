import { ConfigError } from '../../core/errors.js';
import { getCourseMeta } from '../../core/api/study.js';
import { fetchTemplate, getScoAddr } from '../../core/api/sco.js';
import { parseSco } from '../../core/parse/sco-parser.js';
import { buildSession } from '../session-factory.js';
import { writeJson, writeResult, type CliContext } from '../context.js';

export interface InspectFlags {
  course: string;
  sco: string;
}

/**
 * 只读诊断命令：把某小节的答案解析结果打出来，不做任何写操作。
 * 用于验收解析器、核对 match/order 这类未知格式的答案。
 */
export async function inspectCommand(flags: InspectFlags, ctx: CliContext): Promise<number> {
  if (!flags.course) throw new ConfigError('缺少 --course <cid>');
  if (!flags.sco) throw new ConfigError('缺少 --sco <scoid>，可从 `scan --json` 的 candidates 取');

  const { session } = buildSession(ctx.config, ctx.sessionSource, ctx.logger);
  const meta = await getCourseMeta(session, flags.course, { signal: ctx.signal, logger: ctx.logger });

  const address = await getScoAddr(
    session,
    { cid: flags.course, scoid: flags.sco },
    { signal: ctx.signal, classid: meta.classid, logger: ctx.logger },
  );

  if (!address) {
    if (ctx.json) {
      writeJson({ ok: false, scoid: flags.sco, error: 'NO_TEMPLATE', questions: [] });
    } else {
      writeResult(`scoid=${flags.sco} 没有内容地址（scoAddr 未返回 addr），该节可能是纯媒体页`);
    }
    return 0;
  }

  const html = await fetchTemplate(session, address.url, { signal: ctx.signal, logger: ctx.logger });
  const parsed = html === null ? null : parseSco(html);

  if (ctx.json) {
    writeJson({
      ok: html !== null,
      scoid: flags.sco,
      location: address.location,
      url: address.url,
      strategy: parsed?.strategy ?? 'none',
      oral: parsed?.oral ?? 0,
      questions: parsed?.questions ?? [],
      warnings: parsed?.warnings ?? ['内容页抓取失败'],
    });
    return 0;
  }

  writeResult(`scoid=${flags.sco}`);
  if (address.location) writeResult(`小节：${address.location}`);
  writeResult(`内容地址：${address.url}`);

  if (html === null) {
    writeResult('内容页抓取失败（404 或网络异常）');
    return 0;
  }

  if (!parsed) return 0;
  writeResult(`解析策略：${parsed.strategy}  题数：${parsed.questions.length}  口语题：${parsed.oral}`);
  writeResult('');

  const width = String(parsed.questions.length).length;
  parsed.questions.forEach((q, i) => {
    const idx = String(i + 1).padStart(width, ' ');
    writeResult(`  #${idx}  ${q.type.padEnd(6)}  ${q.answer}`);
  });

  for (const warning of parsed.warnings.slice(0, 10)) writeResult(`  ! ${warning}`);
  if (parsed.questions.length === 0) writeResult('  （本节没有可提交的题目，提交时将使用空 interactions）');

  return 0;
}
