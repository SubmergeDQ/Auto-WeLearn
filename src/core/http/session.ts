import { CookieJar } from 'tough-cookie';
import { AppError } from '../errors.js';
import { ACCEPT_HTML, buildHeaders } from './headers.js';

/**
 * 唯一的网络出口。业务层禁止直接 fetch。
 *
 * 为什么手动处理重定向（redirect: 'manual'）：
 * SSO 流程需要从每一跳的 Location 里提取 ReturnUrl / authorize 地址，
 * 交给 fetch 自动跟随会丢掉中间地址；同时手动模式能逐跳吸收 Set-Cookie。
 */

export type HttpMethod = 'GET' | 'POST';

export interface SessionOptions {
  baseUrl: string;
  userAgent: string;
  timeoutMs: number;
  jar?: CookieJar;
}

export interface RequestOptions {
  method?: HttpMethod;
  /** 表单字段，自动 urlencode 并设置 Content-Type */
  form?: Record<string, string>;
  referer?: string;
  /** 是否附带 Origin，表单 POST 默认附带 */
  withOrigin?: boolean;
  signal?: AbortSignal;
  followRedirects?: boolean;
  accept?: string;
  contentType?: string;
  timeoutMs?: number;
  /** 4xx/5xx 也当作正常响应返回，由调用方判定 */
  allowErrorStatus?: boolean;
}

export interface SessionResponse {
  status: number;
  /** 最终地址（重定向后） */
  url: string;
  text: string;
  /** 经过的重定向地址链 */
  redirects: string[];
}

const MAX_REDIRECTS = 10;

function mapFetchError(err: unknown): AppError {
  if (err instanceof Error) {
    if (err.name === 'TimeoutError') {
      return new AppError({ code: 'TIMEOUT', message: '请求超时（超过设定的单请求时长）' });
    }
    if (err.name === 'AbortError') {
      return new AppError({ code: 'INTERRUPTED', message: '操作已被中断', retryable: false });
    }
    if (err.name === 'TypeError') {
      return new AppError({ code: 'NETWORK_ERROR', message: `网络请求失败：${err.message}` });
    }
  }
  return new AppError({ code: 'NETWORK_ERROR', message: `网络请求失败：${String(err)}` });
}

export class Session {
  readonly baseUrl: string;
  /** 供会话持久化读写；业务层不应直接操作 */
  readonly jar: CookieJar;
  private readonly userAgent: string;
  private readonly timeoutMs: number;

  constructor(opts: SessionOptions) {
    this.baseUrl = opts.baseUrl.replace(/\/+$/, '');
    this.userAgent = opts.userAgent;
    this.timeoutMs = opts.timeoutMs;
    this.jar = opts.jar ?? new CookieJar();
  }

  /** 相对路径 → 绝对 URL；支持 `//host/path` 协议相对写法 */
  resolve(pathOrUrl: string): string {
    if (/^https?:\/\//i.test(pathOrUrl)) return pathOrUrl;
    if (pathOrUrl.startsWith('//')) return `https:${pathOrUrl}`;
    return new URL(pathOrUrl, `${this.baseUrl}/`).toString();
  }

  /** 注入登录态 Cookie（来自粘贴串或浏览器） */
  setCookies(pairs: Array<{ name: string; value: string }>): void {
    for (const { name, value } of pairs) {
      try {
        this.jar.setCookieSync(`${name}=${value}`, `${this.baseUrl}/`, { ignoreError: true });
      } catch {
        // 单个格式异常的 Cookie 不应阻断整体登录
      }
    }
  }

  /** 仅供诊断，返回 Cookie 名列表（不含值） */
  cookieNames(): string[] {
    try {
      return this.jar.getCookiesSync(`${this.baseUrl}/`).map((c) => c.key);
    } catch {
      return [];
    }
  }

  private cookieHeader(url: string): string {
    try {
      return this.jar.getCookieStringSync(url);
    } catch {
      return '';
    }
  }

  private absorbCookies(res: Response, url: string): void {
    const list = typeof res.headers.getSetCookie === 'function' ? res.headers.getSetCookie() : [];
    for (const raw of list) {
      try {
        this.jar.setCookieSync(raw, url, { ignoreError: true });
      } catch {
        // 非法 Set-Cookie 忽略
      }
    }
  }

  private async fetchOnce(
    url: string,
    method: HttpMethod,
    opts: RequestOptions,
    body: URLSearchParams | undefined,
  ): Promise<Response> {
    const headers = buildHeaders({
      userAgent: this.userAgent,
      referer: opts.referer,
      origin: opts.withOrigin === false ? undefined : this.baseUrl,
      contentType: body ? (opts.contentType ?? 'application/x-www-form-urlencoded') : opts.contentType,
      accept: opts.accept ?? ACCEPT_HTML,
      cookie: this.cookieHeader(url),
    });

    const timeout = AbortSignal.timeout(opts.timeoutMs ?? this.timeoutMs);
    const signal = opts.signal ? AbortSignal.any([timeout, opts.signal]) : timeout;

    try {
      const res = await fetch(url, {
        method,
        headers,
        body: body ? body.toString() : undefined,
        redirect: 'manual',
        signal,
      });
      this.absorbCookies(res, url);
      return res;
    } catch (err) {
      throw mapFetchError(err);
    }
  }

  async request(pathOrUrl: string, opts: RequestOptions = {}): Promise<SessionResponse> {
    let method: HttpMethod = opts.method ?? 'GET';
    let body = opts.form ? new URLSearchParams(opts.form) : undefined;
    const maxHops = opts.followRedirects === false ? 0 : MAX_REDIRECTS;

    let current = this.resolve(pathOrUrl);
    const redirects: string[] = [];

    for (let hop = 0; ; hop++) {
      const res = await this.fetchOnce(current, method, opts, body);

      const isRedirect = res.status >= 300 && res.status < 400;
      if (isRedirect && hop < maxHops) {
        const location = res.headers.get('location');
        await res.body?.cancel().catch(() => undefined);
        if (!location) {
          throw new AppError({
            code: 'CONTRACT_CHANGED',
            message: `${res.status} 重定向响应缺少 Location 头`,
          });
        }
        const next = new URL(location, current).toString();
        redirects.push(next);

        // 浏览器语义：302/303 之后 POST 降级为 GET
        if (method === 'POST' && (res.status === 302 || res.status === 303)) {
          method = 'GET';
          body = undefined;
        }

        current = next;
        continue;
      }

      const text = await res.text();

      if (!opts.allowErrorStatus && res.status >= 400) {
        const code = res.status >= 500 ? 'SERVER_ERROR' : 'CLIENT_ERROR';
        throw new AppError({
          code,
          message: `HTTP ${res.status}：${text.slice(0, 120).replace(/\s+/g, ' ')}`,
          status: res.status,
        });
      }

      return { status: res.status, url: current, text, redirects };
    }
  }

  async get(pathOrUrl: string, opts: Omit<RequestOptions, 'method' | 'form'> = {}): Promise<SessionResponse> {
    return this.request(pathOrUrl, { ...opts, method: 'GET' });
  }

  async postForm(
    pathOrUrl: string,
    form: Record<string, string>,
    opts: Omit<RequestOptions, 'method' | 'form'> = {},
  ): Promise<SessionResponse> {
    return this.request(pathOrUrl, { ...opts, method: 'POST', form });
  }
}
