import { readFileSync } from 'node:fs';
import { ConfigError } from '../core/errors.js';
import { parseCookieInput } from '../core/auth/cookie.js';
import { loadSessionJar } from '../core/auth/session-store.js';
import { Session } from '../core/http/session.js';
import type { AppConfig } from '../config/schema.js';
import type { Logger } from '../logging/logger.js';

export type SessionOrigin = 'flag' | 'env' | 'file' | 'cache';

export interface SessionSource {
  cookie?: string;
  cookieFile?: string;
  /** 是否允许回退到本地会话缓存，默认 true */
  allowCache?: boolean;
}

export interface BuiltSession {
  session: Session;
  origin: SessionOrigin;
}

/**
 * 按优先级取登录态：--cookie > --cookie-file > WELEARN_COOKIE > 本地会话缓存。
 * 优先级与 §6.2 一致（命令行高于环境变量）。
 */
export function buildSession(
  config: AppConfig,
  source: SessionSource,
  logger: Logger,
  signal?: AbortSignal,
): BuiltSession {
  void signal;
  const jar = loadSessionJar(logger);
  const session = new Session({
    baseUrl: config.baseUrl,
    userAgent: config.userAgent,
    timeoutMs: config.timeoutMs,
    jar: jar ?? undefined,
  });

  let cookieText: string | undefined;
  let origin: SessionOrigin = 'cache';

  if (source.cookie && source.cookie.trim().length > 0) {
    cookieText = source.cookie;
    origin = 'flag';
  } else if (source.cookieFile) {
    try {
      cookieText = readFileSync(source.cookieFile, 'utf8');
    } catch (err) {
      throw new ConfigError(`读取 Cookie 文件失败：${(err as Error).message}`);
    }
    origin = 'file';
  } else if (process.env.WELEARN_COOKIE && process.env.WELEARN_COOKIE.trim().length > 0) {
    cookieText = process.env.WELEARN_COOKIE;
    origin = 'env';
  }

  if (cookieText) {
    const pairs = parseCookieInput(cookieText);
    session.setCookies(pairs);
    logger.debug(`已注入 ${pairs.length} 个 Cookie（来源：${origin}）`);
    return { session, origin };
  }

  if (source.allowCache === false || !jar) {
    throw new ConfigError(
      '未提供登录态。请用 --cookie、WELEARN_COOKIE 环境变量，或先执行 `welearn-cli login` 建立会话缓存',
    );
  }

  logger.debug(`复用本地会话缓存（包含 ${session.cookieNames().length} 个 Cookie）`);
  return { session, origin };
}
