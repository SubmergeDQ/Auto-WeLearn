import { ConfigError } from '../core/errors.js';
import { runConfigSchema, describeZodError, type ParsedRunConfig } from '../config/schema.js';
import type { RatePlan, WaitPlan } from '../types/domain.js';

export interface RawRunFlags {
  course?: string;
  unit?: string;
  rate?: string;
  wait?: string;
  interval?: string;
  concurrency?: string;
  skipOral?: boolean;
  keepOralQuestions?: boolean;
  dryRun?: boolean;
  resume?: boolean;
  state?: string;
  maxLessons?: string;
  unsafeFast?: boolean;
  cmiTime?: string;
}

export function parseRate(raw: string | undefined): RatePlan {
  if (!raw) return { mode: 'range', min: 90, max: 100 };
  const range = /^(\d{1,3})\s*-\s*(\d{1,3})$/.exec(raw.trim());
  if (range?.[1] && range[2]) {
    return { mode: 'range', min: Number(range[1]), max: Number(range[2]) };
  }
  if (/^\d{1,3}$/.test(raw.trim())) {
    return { mode: 'fixed', value: Number(raw.trim()) };
  }
  throw new ConfigError(`--rate 只接受 90 或 90-100，收到：${raw}`);
}

export function parseWait(raw: string | undefined): WaitPlan {
  if (!raw) return { mode: 'range', min: 300, max: 480 };
  const range = /^(\d{1,5})\s*-\s*(\d{1,5})$/.exec(raw.trim());
  if (range?.[1] && range[2]) {
    return { mode: 'range', min: Number(range[1]), max: Number(range[2]) };
  }
  if (/^\d{1,5}$/.test(raw.trim())) {
    return { mode: 'fixed', seconds: Number(raw.trim()) };
  }
  throw new ConfigError(`--wait 只接受 300 或 300-480，收到：${raw}`);
}

export function parseInterval(raw: string | undefined): { min: number; max: number } {
  if (!raw) return { min: 3, max: 8 };
  const m = /^(\d{1,3})\s*-\s*(\d{1,3})$/.exec(raw.trim());
  if (m?.[1] && m[2]) return { min: Number(m[1]), max: Number(m[2]) };
  if (/^\d{1,3}$/.test(raw.trim())) {
    const v = Number(raw.trim());
    return { min: v, max: v };
  }
  throw new ConfigError(`--interval 只接受 3-8 或 5，收到：${raw}`);
}

export function parseUnit(raw: string | undefined): 'all' | number {
  if (!raw || raw === 'all') return 'all';
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1) throw new ConfigError(`--unit 只接受正整数或 all，收到：${raw}`);
  return n;
}

/**
 * 把命令行原始值收敛成 RunConfig。
 * 下限保护：等待时长 < 30s 只有显式 --unsafe-fast 才允许（测试用）。
 */
export function parseRunFlags(flags: RawRunFlags, defaultStatePath: string): ParsedRunConfig {
  if (!flags.course) throw new ConfigError('缺少 --course <cid>');

  const wait = parseWait(flags.wait);
  const minWait = wait.mode === 'fixed' ? wait.seconds : wait.min;
  if (minWait < 30 && !flags.unsafeFast) {
    throw new ConfigError(
      `等待时长 ${minWait}s 低于安全下限 30s。仅在测试时用 --unsafe-fast 显式放行（平台可能判为无效学习）`,
    );
  }

  const concurrency = flags.concurrency ? Number(flags.concurrency) : 1;

  const parsed = runConfigSchema.safeParse({
    course: flags.course,
    unit: parseUnit(flags.unit),
    rate: parseRate(flags.rate),
    wait,
    concurrency,
    interval: parseInterval(flags.interval),
    skipOralLesson: flags.skipOral !== false,
    skipOralQuestion: flags.keepOralQuestions ? false : true,
    dryRun: Boolean(flags.dryRun),
    resume: Boolean(flags.resume),
    statePath: flags.state ?? defaultStatePath,
    ...(flags.maxLessons ? { maxLessons: Number(flags.maxLessons) } : {}),
    ...(flags.cmiTime === 'session' || flags.cmiTime === 'total' ? { cmiTime: flags.cmiTime } : {}),
  });

  if (!parsed.success) {
    throw new ConfigError(`运行参数不合法：${describeZodError(parsed.error)}`);
  }
  return parsed.data;
}
