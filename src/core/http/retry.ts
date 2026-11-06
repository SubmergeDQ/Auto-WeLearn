import { AppError, toAppError } from '../errors.js';
import { interruptibleSleep } from '../sleep.js';
import type { Logger } from '../../logging/logger.js';

export interface RetryOptions {
  /** 重试次数（不含首次尝试） */
  max: number;
  baseDelayMs: number;
  signal?: AbortSignal;
  logger?: Logger;
  /** 抖动比例，0-1，默认 0.3 */
  jitter?: number;
  /** 注入随机源，测试用 */
  random?: () => number;
  /** 自定义可重试判定 */
  shouldRetry?: (err: AppError) => boolean;
  label?: string;
}

/** 2s → 4s → 8s，叠加 0~30% 抖动 */
export function backoffDelay(attempt: number, baseDelayMs: number, jitter: number, random: () => number): number {
  const raw = baseDelayMs * 2 ** attempt;
  const jitterAmount = raw * jitter * random();
  return Math.round(raw + jitterAmount);
}

export async function withRetry<T>(fn: () => Promise<T>, opts: RetryOptions): Promise<T> {
  const jitter = opts.jitter ?? 0.3;
  const random = opts.random ?? Math.random;
  const shouldRetry = opts.shouldRetry ?? ((err: AppError) => err.retryable);
  const label = opts.label ?? '请求';

  let lastError: AppError | null = null;

  for (let attempt = 0; attempt <= opts.max; attempt++) {
    try {
      return await fn();
    } catch (raw) {
      const err = toAppError(raw);
      lastError = err;

      if (err.code === 'INTERRUPTED') throw err;
      if (!shouldRetry(err) || attempt === opts.max) throw err;

      const delay = backoffDelay(attempt, opts.baseDelayMs, jitter, random);
      opts.logger?.warn(
        `${label}失败（${err.code}: ${err.message}），${(delay / 1000).toFixed(1)}s 后第 ${attempt + 1}/${opts.max} 次重试`,
      );
      await interruptibleSleep(delay, opts.signal);
    }
  }

  throw lastError ?? new AppError({ code: 'UNKNOWN', message: `${label}失败` });
}
