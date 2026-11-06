/**
 * 极简分级日志器。
 *
 * 设计取舍：不引入 pino。理由是输出格式需要与 §6.3 逐字符对齐
 * （`[10:21:03] INFO  ...`），pino 的 transport/formatter 反而增加间接层；
 * 本项目日志量小、无并发写日志场景，手写实现更可控也更好测。
 *
 * 硬性要求：所有输出经过 redact()，Cookie / 密码 / Authorization 一律 [REDACTED]。
 */

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
};

/** 阶段标签，用于让长流程输出可扫读 */
export type StageTag = 'RUN' | 'DONE' | 'FAIL' | 'SKIP' | 'HB' | 'NEXT' | 'SCAN' | 'PLAN';

const TAG_LABEL: Record<StageTag, string> = {
  RUN: 'RUN ',
  DONE: 'DONE',
  FAIL: 'FAIL',
  SKIP: 'SKIP',
  HB: 'HB  ',
  NEXT: 'NEXT',
  SCAN: 'SCAN',
  PLAN: 'PLAN',
};

const LEVEL_LABEL: Record<LogLevel, string> = {
  debug: 'DBG ',
  info: 'INFO',
  warn: 'WARN',
  error: 'ERR ',
};

/**
 * 需要脱敏的键名。匹配 `key=value` / `key: value` 两种形态，
 * 不区分大小写；value 允许带引号或裸值。
 */
const SECRET_PAIR =
  /("?)(set-cookie|cookie|pwd|passwd|password|authorization|acw_tc|\.aspnet\.cookies|access_token|refresh_token)("?)(\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s;,}]+)/gi;

const BEARER = /Bearer\s+[A-Za-z0-9._~+/=-]+/g;

/**
 * 对一行文本做脱敏。纯函数，便于单测。
 * 只处理「键 = 值」形态（含 JSON 的 `"pwd":"..."`），不会误伤普通叙述里的单词。
 * 先抹 Bearer，再抹键值对，保证 Authorization 头不会残留 token 片段。
 */
export function redact(text: string): string {
  return text
    .replace(BEARER, 'Bearer [REDACTED]')
    .replace(
      SECRET_PAIR,
      (_m, q1: string, key: string, q2: string, sep: string) => `${q1}${key}${q2}${sep}[REDACTED]`,
    );
}

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

function timestamp(d: Date): string {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

export interface WriteStreamLike {
  write(chunk: string): unknown;
}

export interface LoggerOptions {
  level?: LogLevel;
  stream?: WriteStreamLike;
  now?: () => Date;
}

export interface Logger {
  readonly level: LogLevel;
  debug(message: string): void;
  info(message: string): void;
  warn(message: string): void;
  error(message: string): void;
  /** 阶段行，形如 `[10:21:06] RUN   [1/42] ...` */
  stage(tag: StageTag, message: string): void;
  /** 派生带固定前缀的 logger，前缀同样会被脱敏 */
  child(prefix: string): Logger;
}

function build(level: LogLevel, stream: WriteStreamLike, now: () => Date, prefix: string[]): Logger {
  const enabled = (l: LogLevel): boolean => LEVEL_ORDER[level] <= LEVEL_ORDER[l];

  const emit = (label: string, message: string): void => {
    const parts = [...prefix, message].filter((p) => p.length > 0).join(' ');
    stream.write(`[${timestamp(now())}] ${label}  ${redact(parts)}\n`);
  };

  return {
    level,
    debug: (m) => {
      if (enabled('debug')) emit(LEVEL_LABEL.debug, m);
    },
    info: (m) => {
      if (enabled('info')) emit(LEVEL_LABEL.info, m);
    },
    warn: (m) => {
      if (enabled('warn')) emit(LEVEL_LABEL.warn, m);
    },
    error: (m) => {
      if (enabled('error')) emit(LEVEL_LABEL.error, m);
    },
    stage: (tag, m) => {
      if (enabled('info')) emit(TAG_LABEL[tag], m);
    },
    child: (p) => build(level, stream, now, [...prefix, p]),
  };
}

export function createLogger(opts: LoggerOptions = {}): Logger {
  return build(opts.level ?? 'info', opts.stream ?? process.stderr, opts.now ?? (() => new Date()), []);
}

/** 秒 → `78m32s` / `372s` */
export function formatDuration(totalSeconds: number): string {
  const s = Math.max(0, Math.round(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}h${pad2(m)}m${pad2(sec)}s`;
  if (m > 0) return `${m}m${pad2(sec)}s`;
  return `${sec}s`;
}

/** 秒 → `06:12`，用于「等待」提示 */
export function formatClock(totalSeconds: number): string {
  const s = Math.max(0, Math.round(totalSeconds));
  return `${pad2(Math.floor(s / 60))}:${pad2(s % 60)}`;
}
