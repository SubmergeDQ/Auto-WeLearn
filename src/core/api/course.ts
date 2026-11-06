import { AppError } from '../errors.js';
import type { Logger } from '../../logging/logger.js';
import type { Course } from '../../types/domain.js';
import type { Session } from '../http/session.js';
import { ACCEPT_JSON } from '../http/headers.js';
import { PATHS, refStudentIndex } from './endpoints.js';
import { isLoginWall, parseJsonOrThrow } from './response.js';

interface CourseListPayload {
  ret?: number;
  mess?: string;
  clist?: unknown[];
}

/**
 * 课程列表：GET /ajax/authCourse.aspx?action=gmc
 * 这个接口同时承担「会话校验」职责——能拿到非空 clist 就说明 Cookie 有效。
 */
export async function listCourses(
  session: Session,
  opts: { signal?: AbortSignal; logger?: Logger } = {},
): Promise<Course[]> {
  const res = await session.get(`${PATHS.authCourse}?action=gmc`, {
    referer: refStudentIndex(session.baseUrl),
    accept: ACCEPT_JSON,
    signal: opts.signal,
  });

  if (isLoginWall(res.text, res.status)) {
    throw new AppError({
      code: 'AUTH_EXPIRED',
      message: '会话已失效：课程列表接口被重定向到登录页，请重新获取 Cookie',
      retryable: false,
    });
  }

  const payload = parseJsonOrThrow<CourseListPayload>(res.text, '课程列表');

  if (typeof payload.ret === 'number' && payload.ret !== 0) {
    throw new AppError({
      code: 'CONTRACT_CHANGED',
      message: `课程列表返回 ret=${payload.ret}${payload.mess ? `（${payload.mess}）` : ''}，通常是请求头不完整`,
      retryable: false,
    });
  }

  const raw = Array.isArray(payload.clist) ? payload.clist : [];
  if (raw.length === 0) {
    throw new AppError({
      code: 'BAD_CREDENTIALS',
      message: 'Cookie 无效或该账号下没有课程',
      retryable: false,
    });
  }

  const courses = raw
    .map((item) => normalizeCourse(item))
    .filter((c): c is Course => c !== null);

  if (courses.length === 0) {
    throw new AppError({
      code: 'CONTRACT_CHANGED',
      message: '课程列表结构不符合预期：clist 中没有任何可识别的课程对象',
    });
  }

  opts.logger?.debug(`课程列表解析完成，共 ${courses.length} 门`);
  return courses;
}

function normalizeCourse(item: unknown): Course | null {
  if (typeof item !== 'object' || item === null) return null;
  const obj = item as Record<string, unknown>;
  const cid = obj.cid;
  if (cid === undefined || cid === null) return null;

  const percent = Number(obj.per);
  return {
    cid: String(cid),
    name: typeof obj.name === 'string' ? obj.name : `课程 ${String(cid)}`,
    percent: Number.isFinite(percent) ? Math.trunc(percent) : 0,
  };
}
