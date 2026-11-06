import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { CookieJar } from 'tough-cookie';
import { APP_DIR, SESSION_PATH, expandHome } from '../../config/paths.js';
import type { Logger } from '../../logging/logger.js';

/**
 * 会话缓存。登录成功后把 CookieJar 序列化到本地，
 * 后续 scan / run 不必重复粘贴 Cookie。
 *
 * 安全：文件权限尽力设为 0600（Windows 上 chmod 语义有限，失败只告警）；
 * 内容含会话 Cookie，已在 .gitignore 中排除 `.welearn-cli/`。
 */

interface StoredSession {
  version: 1;
  savedAt: string;
  jar: unknown;
}

function resolveSessionPath(): string {
  return expandHome(SESSION_PATH);
}

export function loadSessionJar(logger?: Logger): CookieJar | null {
  const path = resolveSessionPath();
  if (!existsSync(path)) return null;

  try {
    const raw = readFileSync(path, 'utf8');
    const parsed = JSON.parse(raw) as StoredSession;
    if (parsed.version !== 1 || !parsed.jar) {
      logger?.warn('会话缓存版本不匹配，已忽略');
      return null;
    }
    return CookieJar.deserializeSync(parsed.jar as Parameters<typeof CookieJar.deserializeSync>[0]);
  } catch (err) {
    logger?.warn(`会话缓存读取失败，已忽略：${(err as Error).message}`);
    return null;
  }
}

export function saveSessionJar(jar: CookieJar, logger?: Logger): string {
  const path = resolveSessionPath();
  const dir = dirname(path);

  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  const payload: StoredSession = {
    version: 1,
    savedAt: new Date().toISOString(),
    jar: jar.serializeSync(),
  };

  const tmp = join(dir, `.session.${process.pid}.tmp`);
  writeFileSync(tmp, JSON.stringify(payload), { encoding: 'utf8', mode: 0o600 });
  renameSync(tmp, path);

  try {
    chmodSync(path, 0o600);
  } catch {
    logger?.debug('无法将会话文件权限设为 0600（Windows 上属正常）');
  }

  return path;
}

export function clearSession(): void {
  const path = resolveSessionPath();
  if (existsSync(path)) rmSync(path, { force: true });
}

export function sessionFilePath(): string {
  return resolveSessionPath();
}

export function appDir(): string {
  return APP_DIR();
}
