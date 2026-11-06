import { createLogger, type Logger } from '../logging/logger.js';
import type { AppConfig } from '../config/schema.js';

export interface SessionSourceFlags {
  cookie?: string;
  cookieFile?: string;
}

export interface CliContext {
  signal: AbortSignal;
  json: boolean;
  verbose: boolean;
  logger: Logger;
  config: AppConfig;
  /** 全局登录态来源（--cookie / --cookie-file） */
  sessionSource: SessionSourceFlags;
}

export interface ContextOptions {
  signal: AbortSignal;
  json: boolean;
  verbose: boolean;
  config: AppConfig;
  sessionSource: SessionSourceFlags;
}

export function createContext(opts: ContextOptions): CliContext {
  return {
    signal: opts.signal,
    json: opts.json,
    verbose: opts.verbose,
    config: opts.config,
    sessionSource: opts.sessionSource,
    logger: createLogger({ level: opts.verbose ? 'debug' : 'info' }),
  };
}

/** 结果写 stdout，日志写 stderr —— 保证 --json 可被管道消费 */
export function writeResult(text: string): void {
  process.stdout.write(text.endsWith('\n') ? text : `${text}\n`);
}

export function writeJson(payload: unknown): void {
  writeResult(JSON.stringify(payload, null, 2));
}
