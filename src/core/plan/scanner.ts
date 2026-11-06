import type { Lesson, Unit } from '../../types/domain.js';
import type { Logger } from '../../logging/logger.js';
import type { Session } from '../http/session.js';
import { getLessons, getUnits } from '../api/study.js';
import { interruptibleSleep } from '../sleep.js';

/**
 * 扫描：把「课程 → 单元 → 小节」拉平成任务队列。
 *
 * 口语识别是这里唯一的启发式规则，也是最容易误伤的地方：
 * 少识别会把录音题当普通题提交（拿不到分，但无害）；
 * 误识别会整节跳过（直接丢分）。因此关键词表刻意偏保守，
 * 不含裸的 "speaking" —— 本课程大量小节叫 "Listening & Speaking"，它们是听力题。
 */

export const ORAL_LESSON_KEYWORDS = [
  '口语',
  'pronunciation',
  'read aloud',
  'readaloud',
  'voicerecord',
  'oral practice',
  'spoken english',
] as const;

export const MAX_UNIT_PROBE = 200;
const POLITE_DELAY_MS = 120;

export function isOralLesson(lesson: Lesson): boolean {
  const text = lesson.location.toLowerCase();
  return ORAL_LESSON_KEYWORDS.some((k) => text.includes(k));
}

export interface ScanParams {
  cid: string;
  uid: string;
  classid: string;
  unit: 'all' | number;
  skipOralLesson: boolean;
}

export interface ScanStats {
  units: number;
  lessons: number;
  completed: number;
  invisible: number;
  oralSkipped: number;
  candidates: number;
}

export interface ScanResult {
  units: Unit[];
  lessons: Lesson[];
  candidates: Lesson[];
  stats: ScanStats;
  warnings: string[];
}

export async function scanCourse(
  session: Session,
  params: ScanParams,
  opts: { signal?: AbortSignal; logger?: Logger } = {},
): Promise<ScanResult> {
  const warnings: string[] = [];
  const units = await getUnits(session, { cid: params.cid, uid: params.uid }, { signal: opts.signal });

  if (params.unit !== 'all' && params.unit > units.length) {
    warnings.push(`指定的 unit=${params.unit} 超出单元总数 ${units.length}，将按空队列处理`);
  }

  const indices =
    params.unit === 'all'
      ? Array.from({ length: Math.min(Math.max(units.length + 1, 1), MAX_UNIT_PROBE) }, (_, i) => i)
      : [params.unit - 1];

  const lessons: Lesson[] = [];

  for (const unitIndex of indices) {
    const batch = await getLessons(
      session,
      { cid: params.cid, uid: params.uid, classid: params.classid, unitIndex },
      { signal: opts.signal },
    );

    if (batch === null) {
      warnings.push(`第 ${unitIndex + 1} 单元小节列表返回异常，停止继续探测`);
      break;
    }

    if (batch.length === 0) {
      opts.logger?.debug(`第 ${unitIndex + 1} 单元无小节，扫描结束`);
      break;
    }

    lessons.push(...batch);
    opts.logger?.debug(`第 ${unitIndex + 1} 单元：${batch.length} 小节`);
    await interruptibleSleep(POLITE_DELAY_MS, opts.signal);
  }

  const completed = lessons.filter((l) => l.complete).length;
  const invisible = lessons.filter((l) => !l.visible).length;
  const oral = lessons.filter((l) => l.visible && !l.complete && isOralLesson(l));
  const candidates = lessons.filter(
    (l) => l.visible && !l.complete && !(params.skipOralLesson && isOralLesson(l)),
  );

  return {
    units,
    lessons,
    candidates,
    stats: {
      units: units.length,
      lessons: lessons.length,
      completed,
      invisible,
      oralSkipped: params.skipOralLesson ? oral.length : 0,
      candidates: candidates.length,
    },
    warnings,
  };
}
