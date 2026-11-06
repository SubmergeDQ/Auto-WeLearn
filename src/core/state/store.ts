import { copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { expandHome } from '../../config/paths.js';
import type { LessonStatus, RunState } from '../../types/domain.js';
import type { Logger } from '../../logging/logger.js';

/**
 * 断点续跑状态。写入采用「临时文件 + rename」保证原子性，
 * 避免 Ctrl+C 落在写盘中途留下半个 JSON。
 */

export const STATE_VERSION = 1;

export function emptyState(course: RunState['course']): RunState {
  return {
    version: STATE_VERSION,
    updatedAt: new Date().toISOString(),
    course,
    lessons: {},
    stats: { done: 0, partial: 0, failed: 0, skipped: 0 },
  };
}

function resolvePath(path: string): string {
  return expandHome(path);
}

export function loadState(path: string, logger?: Logger): RunState | null {
  const file = resolvePath(path);
  if (!existsSync(file)) return null;

  try {
    const parsed = JSON.parse(readFileSync(file, 'utf8')) as RunState;
    if (parsed.version !== STATE_VERSION) {
      throw new Error(`状态文件版本 ${String(parsed.version)} 与当前 ${STATE_VERSION} 不匹配`);
    }
    if (!parsed.lessons || !parsed.course) {
      throw new Error('状态文件缺少必要字段');
    }
    return parsed;
  } catch (err) {
    const backup = `${file}.bak`;
    try {
      copyFileSync(file, backup);
      logger?.warn(`状态文件损坏，已备份为 ${backup}，本次将重新开始`);
    } catch {
      logger?.warn(`状态文件损坏且无法备份，本次将重新开始`);
    }
    return null;
  }
}

export function saveState(path: string, state: RunState): void {
  const file = resolvePath(path);
  const dir = dirname(file);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  state.updatedAt = new Date().toISOString();
  recount(state);

  const tmp = join(dir, `.state.${process.pid}.tmp`);
  writeFileSync(tmp, JSON.stringify(state, null, 2), 'utf8');
  renameSync(tmp, file);
}

export function recordLesson(
  state: RunState,
  scoid: string,
  patch: {
    status: LessonStatus;
    attempts?: number;
    crate?: number;
    waitSec?: number;
    errorCode?: string;
  },
): void {
  const prev = state.lessons[scoid];
  state.lessons[scoid] = {
    status: patch.status,
    attempts: patch.attempts ?? (prev?.attempts ?? 0) + 1,
    ...(patch.crate !== undefined ? { crate: patch.crate } : {}),
    ...(patch.waitSec !== undefined ? { waitSec: patch.waitSec } : {}),
    finishedAt: new Date().toISOString(),
    ...(patch.errorCode ? { errorCode: patch.errorCode } : {}),
  };
}

export function recount(state: RunState): void {
  const stats = { done: 0, partial: 0, failed: 0, skipped: 0 };
  for (const item of Object.values(state.lessons)) {
    if (item.status === 'done') stats.done++;
    else if (item.status === 'partial') stats.partial++;
    else if (item.status === 'failed') stats.failed++;
    else if (item.status === 'skipped' || item.status === 'dry-run') stats.skipped++;
  }
  state.stats = stats;
}

/** 该小节是否已经处理过（成功或部分成功），用于 --resume 跳过 */
export function isFinished(state: RunState, scoid: string): boolean {
  const item = state.lessons[scoid];
  if (!item) return false;
  return item.status === 'done' || item.status === 'partial' || item.status === 'skipped';
}
