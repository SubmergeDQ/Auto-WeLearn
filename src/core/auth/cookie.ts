import { ConfigError } from '../errors.js';

/**
 * Cookie 解析。支持两种真实来源：
 * 1. 浏览器 DevTools 里复制的 `a=1; b=2` 串
 * 2. EditThisCookie / Cookie-Editor 导出的 JSON 数组
 *
 * 坑位：`.AspNet.Cookies` 的值里含 `-`、`_`，甚至可能出现 `=`，
 * 所以每段只能按「第一个等号」切分，不能用 split('=')。
 */

export interface CookiePair {
  name: string;
  value: string;
}

interface RawJsonCookie {
  name?: unknown;
  value?: unknown;
  Name?: unknown;
  Value?: unknown;
}

function parseJsonArray(text: string): CookiePair[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    throw new ConfigError(`Cookie JSON 解析失败：${(err as Error).message}`);
  }
  if (!Array.isArray(parsed)) {
    throw new ConfigError('Cookie JSON 必须是数组（EditThisCookie 导出格式）');
  }

  const pairs: CookiePair[] = [];
  for (const item of parsed as RawJsonCookie[]) {
    const name = typeof item.name === 'string' ? item.name : typeof item.Name === 'string' ? item.Name : null;
    const value = typeof item.value === 'string' ? item.value : typeof item.Value === 'string' ? item.Value : null;
    if (name && value !== null) pairs.push({ name, value });
  }
  return pairs;
}

function parseRawString(text: string): CookiePair[] {
  const pairs: CookiePair[] = [];
  for (const segment of text.split(';')) {
    const part = segment.trim();
    if (!part) continue;
    const eq = part.indexOf('=');
    if (eq <= 0) continue;
    const name = part.slice(0, eq).trim();
    const value = part.slice(eq + 1).trim();
    if (name) pairs.push({ name, value });
  }
  return pairs;
}

/** 同名 Cookie 保留最后一个（浏览器行为：后写覆盖先写） */
function dedupe(pairs: CookiePair[]): CookiePair[] {
  const map = new Map<string, string>();
  for (const { name, value } of pairs) map.set(name, value);
  return [...map.entries()].map(([name, value]) => ({ name, value }));
}

export function parseCookieInput(raw: string): CookiePair[] {
  const text = raw.trim();
  if (!text) throw new ConfigError('Cookie 为空');

  // `{` 开头的输入几乎必然是「误传了 JSON 对象」，给出更具体的提示
  if (text.startsWith('{')) {
    throw new ConfigError('Cookie JSON 必须是数组（EditThisCookie 导出格式），不能是单个对象');
  }

  const pairs = text.startsWith('[') ? parseJsonArray(text) : parseRawString(text);
  const result = dedupe(pairs);
  if (result.length === 0) {
    throw new ConfigError('无法从输入中解析出任何 Cookie（需要 name=value 形式）');
  }
  return result;
}
