import { AppError } from '../errors.js';
import type { Logger } from '../../logging/logger.js';
import type { Session } from '../http/session.js';
import { ACCEPT_JSON } from '../http/headers.js';
import { PATHS, refStudyShort } from './endpoints.js';
import { isLoginWall, isRetOk, parseJsonOrThrow } from './response.js';

/**
 * SCO 相关接口。
 *
 * scoAddr 是理解整个课程内容结构的关键，实测结果与规格假设不同（附录 C-5）：
 *   addr 形如 `//centercourseware.sflep.com/<课程名>/unit_03/main5.html?m-1-3-5|Unit 3 > … > Task 1`
 * - 没有 `#/2/4-3` 这种 hash 路由
 * - 路径里带空格（课程名），需要交给 fetch 自身编码
 * - `|` 后面是小节路径，仅用于展示
 * 也就是说：**addr 去掉 `|` 后缀就是内容页地址本身**，不需要再推导 data/{unit}/{file}.html。
 */

export interface ScoAddress {
  /** 内容页完整地址（含 query） */
  url: string;
  /** `|` 后缀的小节路径，可能为空 */
  location: string;
  raw: string;
}

interface ScoAddrPayload {
  ret?: number;
  addr?: string;
  mess?: string;
}

export async function getScoAddr(
  session: Session,
  params: { cid: string; scoid: string },
  opts: { signal?: AbortSignal; classid?: string; logger?: Logger } = {},
): Promise<ScoAddress | null> {
  const referer = opts.classid
    ? refStudyShort(session.baseUrl, params.cid, params.scoid)
    : `${session.baseUrl}/Student/StudyCourse.aspx?cid=${encodeURIComponent(params.cid)}&sco=${encodeURIComponent(params.scoid)}`;

  const res = await session.postForm(
    PATHS.sco,
    { action: 'scoAddr', cid: params.cid, scoid: params.scoid },
    { referer, accept: ACCEPT_JSON, signal: opts.signal },
  );

  if (isLoginWall(res.text, res.status)) {
    throw new AppError({ code: 'AUTH_EXPIRED', message: '会话已失效：scoAddr 被跳转到登录页', retryable: false });
  }

  const payload = parseJsonOrThrow<ScoAddrPayload>(res.text, 'scoAddr');
  if (payload.ret !== 0 || !payload.addr) {
    opts.logger?.debug(`scoAddr 无内容地址（ret=${String(payload.ret)}）：${params.scoid}`);
    return null;
  }

  const raw = payload.addr;
  const [addrPart = '', location = ''] = raw.split('|');
  if (addrPart.length === 0) return null;

  const url = addrPart.startsWith('//')
    ? `${session.baseUrl.startsWith('http://') ? 'http:' : 'https:'}${addrPart}`
    : addrPart;
  return { url, location: location.trim(), raw };
}

/** 抓取内容页 HTML。404 或空内容返回 null，按「无模板」处理 */
export async function fetchTemplate(
  session: Session,
  url: string,
  opts: { signal?: AbortSignal; logger?: Logger } = {},
): Promise<string | null> {
  try {
    const res = await session.get(url, {
      referer: `${session.baseUrl}/`,
      signal: opts.signal,
      allowErrorStatus: true,
    });
    if (res.status !== 200) {
      opts.logger?.debug(`内容页返回 HTTP ${res.status}：${url.slice(0, 120)}`);
      return null;
    }
    return res.text;
  } catch (err) {
    if (err instanceof AppError && err.code === 'INTERRUPTED') throw err;
    opts.logger?.debug(`内容页抓取失败：${(err as Error).message}`);
    return null;
  }
}

interface ScoWritePayload {
  ret?: number;
  mess?: string;
  comment?: string;
}

/** 读写类调用统一入口，返回原始响应文本供调用方判定 */
export async function postScoAction(
  session: Session,
  form: Record<string, string>,
  opts: { referer: string; signal?: AbortSignal },
): Promise<string> {
  const res = await session.postForm(PATHS.sco, form, {
    referer: opts.referer,
    accept: ACCEPT_JSON,
    signal: opts.signal,
  });

  if (isLoginWall(res.text, res.status)) {
    throw new AppError({ code: 'AUTH_EXPIRED', message: '会话已失效：SCO 写操作被跳转到登录页', retryable: false });
  }
  return res.text;
}

export function scoOk(text: string): boolean {
  return isRetOk(text);
}

/** 解析 getscoinfo_v7 的 comment 双层 JSON */
export function parseCmiComment(text: string): Record<string, unknown> | null {
  try {
    const outer = parseJsonOrThrow<ScoWritePayload>(text, 'getscoinfo_v7');
    if (!outer.comment) return null;
    const inner = JSON.parse(outer.comment) as { cmi?: Record<string, unknown> };
    return inner.cmi ?? null;
  } catch {
    return null;
  }
}
