import { join } from 'node:path';
import { AppError, ConfigError } from '../errors.js';
import { interruptibleSleep } from '../sleep.js';
import { APP_DIR } from '../../config/paths.js';
import type { Logger } from '../../logging/logger.js';

/**
 * 浏览器登录（P2，可选能力）。
 *
 * 为什么用持久化上下文（userDataDir）而不是每次全新启动：
 * 学校 SSO 往往有设备校验与二次验证，持久化 profile 相当于「这台机器登录过」，
 * 后续跑命令通常不用重复输账号密码。
 *
 * playwright-core 采用**动态 import**：
 * 不装也能用 Cookie 登录，装了就多一个 --browser 选项，不增加默认安装体积。
 */

interface BrowserCookie {
  name: string;
  value: string;
}

interface PageLike {
  goto(url: string, options?: Record<string, unknown>): Promise<unknown>;
}

interface ContextLike {
  cookies(url?: string): Promise<BrowserCookie[]>;
  newPage(): Promise<PageLike>;
  close(): Promise<void>;
}

interface PlaywrightLike {
  chromium: {
    launchPersistentContext(userDataDir: string, options?: Record<string, unknown>): Promise<ContextLike>;
  };
}

export interface BrowserLoginOptions {
  baseUrl: string;
  /** 等待用户完成登录的总时长，默认 180s */
  timeoutMs?: number;
  signal?: AbortSignal;
  logger?: Logger;
  profileDir?: string;
}

/** 会话 Cookie 名称：只有真正登录成功平台才会下发 */
const AUTH_COOKIE = '.AspNet.Cookies';

async function loadPlaywright(): Promise<PlaywrightLike> {
  // 用变量做说明符，避免未安装时 tsc 报找不到模块
  const specifier = 'playwright-core';
  try {
    return (await import(specifier)) as unknown as PlaywrightLike;
  } catch {
    throw new ConfigError(
      '浏览器登录需要 playwright-core，但当前未安装。请先执行：npm i -D playwright-core\n' +
        '（或直接使用 Cookie 登录：welearn-cli login --cookie "..."）',
    );
  }
}

const CHANNELS = ['chrome', 'msedge'] as const;

async function launch(playwright: PlaywrightLike, profileDir: string): Promise<ContextLike> {
  let lastError: unknown = null;

  for (const channel of CHANNELS) {
    try {
      return await playwright.chromium.launchPersistentContext(profileDir, {
        channel,
        headless: false,
        viewport: null,
        args: ['--start-maximized'],
      });
    } catch (err) {
      lastError = err;
    }
  }

  throw new ConfigError(
    `无法启动本机 Chrome/Edge：${(lastError as Error)?.message ?? '未知原因'}。` +
      '请确认已安装 Chrome 或 Edge，或改用 Cookie 登录',
  );
}

export async function browserLogin(opts: BrowserLoginOptions): Promise<BrowserCookie[]> {
  const playwright = await loadPlaywright();
  const profileDir = opts.profileDir ?? join(APP_DIR(), 'browser-profile');
  const timeoutMs = opts.timeoutMs ?? 180_000;

  opts.logger?.info('正在启动本机浏览器，请在窗口内完成登录…');

  const context = await launch(playwright, profileDir);
  let closed = false;

  const shutdown = async (): Promise<void> => {
    if (closed) return;
    closed = true;
    try {
      await context.close();
    } catch {
      // 关闭失败不影响主流程
    }
  };

  try {
    const page = await context.newPage();
    await page.goto(opts.baseUrl, { waitUntil: 'domcontentloaded' });

    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (opts.signal?.aborted) {
        throw new AppError({ code: 'INTERRUPTED', message: '浏览器登录已被中断', retryable: false });
      }

      const cookies = await context.cookies(opts.baseUrl);
      if (cookies.some((c) => c.name === AUTH_COOKIE && c.value.length > 0)) {
        opts.logger?.info(`已检测到登录态（${cookies.length} 个 Cookie），关闭浏览器`);
        await shutdown();
        return cookies.map(({ name, value }) => ({ name, value }));
      }

      await interruptibleSleep(1000, opts.signal);
    }

    throw new AppError({
      code: 'AUTH_EXPIRED',
      message: `等待 ${Math.round(timeoutMs / 1000)}s 仍未检测到会话 Cookie，登录似乎没有完成`,
      retryable: false,
    });
  } finally {
    await shutdown();
  }
}
