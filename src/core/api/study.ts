import { AppError } from '../errors.js';
import type { Logger } from '../../logging/logger.js';
import type { Lesson, Unit } from '../../types/domain.js';
import type { Session } from '../http/session.js';
import { ACCEPT_JSON } from '../http/headers.js';
import { PATHS, refCourseInfo, refStudentIndex } from './endpoints.js';
import { isLoginWall, parseJsonOrThrow } from './response.js';

/**
 * 课程 / 单元 / 小节读取。
 *
 * 字段坑位（实测，附录 C-3）：
 * - isvisible 是字符串 "true"/"false"，不是布尔；
 * - iscomplete 是中文 "已完成"/"未完成"，必须同时看「已」「未」两个字；
 * - unitidx 是 0-based 数组下标，平台不返回 index 字段；
 * - 小节的 crate 可能是 "-"/"无"/"100"，不能当数字解析。
 */

export interface CourseMeta {
  uid: string;
  classid: string;
}

interface StudyStatPayload {
  ret?: number;
  info?: unknown[];
}

const UID_RE = /"uid"\s*:\s*(\d+)/;
const CLASSID_RE = /"classid"\s*:\s*"([^"]*)"/;

const LESSON_ERROR_HINT = /(异常|出错了)/;

export function isCompleteText(text: string): boolean {
  return text.includes('已') && !text.includes('未');
}

export function isIncompleteText(text: string): boolean {
  return text.includes('未') && !text.includes('已');
}

/** 从课程详情页 HTML 提取 uid / classid */
export async function getCourseMeta(
  session: Session,
  cid: string,
  opts: { signal?: AbortSignal; logger?: Logger } = {},
): Promise<CourseMeta> {
  const res = await session.get(`${PATHS.courseInfo}?cid=${encodeURIComponent(cid)}`, {
    referer: refStudentIndex(session.baseUrl),
    signal: opts.signal,
  });

  if (isLoginWall(res.text, res.status)) {
    throw new AppError({
      code: 'AUTH_EXPIRED',
      message: '会话已失效：打开课程详情页被跳转到登录页',
      retryable: false,
    });
  }

  const uid = UID_RE.exec(res.text)?.[1];
  const classid = CLASSID_RE.exec(res.text)?.[1];

  if (!uid || !classid) {
    throw new AppError({
      code: 'CONTRACT_CHANGED',
      message: `课程详情页解析失败：${uid ? '' : '未找到 uid'}${!uid && !classid ? '、' : ''}${
        classid ? '' : '未找到 classid'
      }（页面结构可能已变更）`,
      retryable: false,
    });
  }

  opts.logger?.debug(`课程元信息：uid=${uid} classid=${classid}`);
  return { uid, classid };
}

/** 单元列表：action=courseunits */
export async function getUnits(
  session: Session,
  params: { cid: string; uid: string },
  opts: { signal?: AbortSignal } = {},
): Promise<Unit[]> {
  const query = new URLSearchParams({ action: 'courseunits', cid: params.cid, uid: params.uid });
  const res = await session.get(`${PATHS.studyStat}?${query.toString()}`, {
    referer: refCourseInfo(session.baseUrl, params.cid),
    accept: ACCEPT_JSON,
    signal: opts.signal,
  });

  if (isLoginWall(res.text, res.status)) {
    throw new AppError({ code: 'AUTH_EXPIRED', message: '会话已失效：单元列表被跳转到登录页', retryable: false });
  }

  const payload = parseJsonOrThrow<StudyStatPayload>(res.text, '单元列表');
  if (typeof payload.ret === 'number' && payload.ret !== 0) {
    throw new AppError({
      code: 'CONTRACT_CHANGED',
      message: `单元列表返回 ret=${payload.ret}`,
      retryable: false,
    });
  }

  const raw = Array.isArray(payload.info) ? payload.info : [];
  return raw.map((item, index) => {
    const obj = (typeof item === 'object' && item !== null ? item : {}) as Record<string, unknown>;
    return {
      index,
      unitName: str(obj.unitname) ?? `Unit ${index + 1}`,
      name: str(obj.name) ?? '',
      visible: str(obj.visible)?.toLowerCase() === 'true',
    } satisfies Unit;
  });
}

/**
 * 小节列表：action=scoLeaves
 * 返回 null 表示接口异常（正文含「异常」「出错了」），调用方必须停止遍历而不是跳过。
 */
export async function getLessons(
  session: Session,
  params: { cid: string; uid: string; classid: string; unitIndex: number },
  opts: { signal?: AbortSignal } = {},
): Promise<Lesson[] | null> {
  const query = new URLSearchParams({
    action: 'scoLeaves',
    cid: params.cid,
    uid: params.uid,
    unitidx: String(params.unitIndex),
    classid: params.classid,
  });

  const res = await session.get(`${PATHS.studyStat}?${query.toString()}`, {
    referer: refCourseInfo(session.baseUrl, params.cid),
    accept: ACCEPT_JSON,
    signal: opts.signal,
  });

  if (isLoginWall(res.text, res.status)) {
    throw new AppError({ code: 'AUTH_EXPIRED', message: '会话已失效：小节列表被跳转到登录页', retryable: false });
  }

  if (LESSON_ERROR_HINT.test(res.text)) {
    return null;
  }

  const payload = parseJsonOrThrow<StudyStatPayload>(res.text, '小节列表');
  if (typeof payload.ret === 'number' && payload.ret !== 0) {
    return null;
  }

  const raw = Array.isArray(payload.info) ? payload.info : [];
  return raw.map((item) => normalizeLesson(item, params.unitIndex)).filter((l): l is Lesson => l !== null);
}

function normalizeLesson(item: unknown, unitIndex: number): Lesson | null {
  if (typeof item !== 'object' || item === null) return null;
  const obj = item as Record<string, unknown>;
  const id = obj.id;
  if (id === undefined || id === null || String(id).length === 0) return null;

  const completeText = str(obj.iscomplete) ?? '';
  return {
    unitIndex,
    scoid: String(id),
    location: str(obj.location) ?? str(obj.name) ?? String(id),
    visible: (str(obj.isvisible) ?? 'true').toLowerCase() === 'true',
    complete: isCompleteText(completeText),
    learnTime: str(obj.learntime) ?? '',
    crateLabel: str(obj.crate) ?? '',
  };
}

function str(value: unknown): string | null {
  if (typeof value === 'string') return value;
  if (typeof value === 'number') return String(value);
  return null;
}
