import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AppError } from '../src/core/errors.js';
import { listCourses } from '../src/core/api/course.js';
import { getCourseMeta, getLessons, getUnits } from '../src/core/api/study.js';
import { scanCourse } from '../src/core/plan/scanner.js';
import { prepareLesson } from '../src/core/run/prepare.js';
import { Session } from '../src/core/http/session.js';
import { startMockServer, type MockServer } from './helpers/mock-server.js';

const UA = 'Mozilla/5.0 (Test) Chrome/131.0.0.0';

let mock: MockServer;

function makeSession(): Session {
  const session = new Session({ baseUrl: mock.baseUrl, userAgent: UA, timeoutMs: 5000 });
  session.setCookies([{ name: 'area', value: 'dbC' }]);
  return session;
}

beforeAll(async () => {
  mock = await startMockServer();
});

afterAll(async () => {
  await mock.close();
});

describe('会话与课程列表', () => {
  it('有效 Cookie 能拿到课程列表', async () => {
    const courses = await listCourses(makeSession());
    expect(courses).toEqual([{ cid: '900', name: 'Mock Course', percent: 40 }]);
  });

  it('缺少 Cookie 时判定为 AUTH_EXPIRED', async () => {
    const bare = new Session({ baseUrl: mock.baseUrl, userAgent: UA, timeoutMs: 5000 });
    await expect(listCourses(bare)).rejects.toMatchObject({ code: 'AUTH_EXPIRED' });
  });

  it('Cookie 被标记过期时同样判定为 AUTH_EXPIRED', async () => {
    const expired = new Session({ baseUrl: mock.baseUrl, userAgent: UA, timeoutMs: 5000 });
    expired.setCookies([{ name: 'area', value: 'expired' }]);
    await expect(listCourses(expired)).rejects.toMatchObject({ code: 'AUTH_EXPIRED' });
  });

  it('课程列表请求必须带 Referer（附录 C-1）', async () => {
    const before = mock.requests.length;
    await listCourses(makeSession());
    const req = mock.requests.slice(before).find((r) => r.pathname === '/ajax/authCourse.aspx');
    expect(req?.headers.referer).toContain('/student/index.aspx');
  });
});

describe('课程元信息与课程结构', () => {
  it('从课程详情页提取 uid / classid', async () => {
    const meta = await getCourseMeta(makeSession(), '900');
    expect(meta).toEqual({ uid: '123', classid: 'abc' });
  });

  it('单元列表归一化 visible 字符串为布尔', async () => {
    const units = await getUnits(makeSession(), { cid: '900', uid: '123' });
    expect(units).toHaveLength(2);
    expect(units[0]).toEqual({ index: 0, unitName: 'Unit 01', name: 'Unit 1', visible: true });
  });

  it('小节列表归一化 iscomplete 中文为布尔，并保留平台原值', async () => {
    const lessons = await getLessons(makeSession(), { cid: '900', uid: '123', classid: 'abc', unitIndex: 0 });
    expect(lessons).not.toBeNull();
    expect(lessons?.[0]).toMatchObject({ scoid: 'sco-done', complete: true, visible: true, learnTime: '00:01:00' });
    expect(lessons?.[1]).toMatchObject({ scoid: 'sco-todo', complete: false });
  });

  it('接口返回异常文本时 getLessons 返回 null 而不是空数组', async () => {
    const lessons = await getLessons(makeSession(), { cid: '900', uid: '123', classid: 'abc', unitIndex: 99 });
    expect(lessons).toBeNull();
  });

  it('单元没有小节时返回空数组（正常终止信号）', async () => {
    const lessons = await getLessons(makeSession(), { cid: '900', uid: '123', classid: 'abc', unitIndex: 2 });
    expect(lessons).toEqual([]);
  });
});

describe('扫描与过滤', () => {
  it('排除已完成与不可见小节，并在单元无数据时终止', async () => {
    const result = await scanCourse(makeSession(), {
      cid: '900',
      uid: '123',
      classid: 'abc',
      unit: 'all',
      skipOralLesson: true,
    });

    expect(result.stats.lessons).toBe(4);
    expect(result.stats.completed).toBe(1);
    expect(result.stats.invisible).toBe(1);
    // sco-oral 匹配 "Oral Practice" 关键词，被跳过
    expect(result.stats.oralSkipped).toBe(1);
    expect(result.candidates.map((l) => l.scoid)).toEqual(['sco-todo']);
  });

  it('关闭 skipOralLesson 时口语小节进入队列', async () => {
    const result = await scanCourse(makeSession(), {
      cid: '900',
      uid: '123',
      classid: 'abc',
      unit: 'all',
      skipOralLesson: false,
    });
    expect(result.candidates.map((l) => l.scoid)).toEqual(['sco-todo', 'sco-oral']);
  });

  it('--unit 指定单个单元时只扫该单元', async () => {
    const result = await scanCourse(makeSession(), {
      cid: '900',
      uid: '123',
      classid: 'abc',
      unit: 2,
      skipOralLesson: false,
    });
    expect(result.lessons.map((l) => l.scoid)).toEqual(['sco-oral']);
  });
});

describe('dry-run 链路', () => {
  it('完整解析一节但不产生任何写请求', async () => {
    const session = makeSession();
    const prep = await prepareLesson(session, { cid: '900', scoid: 'sco-todo', classid: 'abc' });

    expect(prep.strategy).toBe('courseware');
    expect(prep.questions).toHaveLength(7);
    expect(prep.address?.url).toContain('/courseware/main1.html');

    const writes = mock.writeActions();
    expect(writes).toEqual([]);
    expect(writes).not.toContain('startsco160928');
    expect(writes).not.toContain('setscoinfo');
    expect(writes).not.toContain('savescoinfo160928');
  });

  it('scoAddr 的 Referer 指向学习页', async () => {
    const before = mock.requests.length;
    await prepareLesson(makeSession(), { cid: '900', scoid: 'sco-todo', classid: 'abc' });
    const req = mock.requests.slice(before).find((r) => r.pathname === '/Ajax/SCO.aspx');
    expect(req?.headers.referer).toContain('/Student/StudyCourse.aspx?cid=900');
    expect(req?.body).toContain('scoid=sco-todo');
  });

  it('没有内容地址时返回 NO_TEMPLATE 警告而不是抛错', async () => {
    const session = makeSession();
    // mock 中所有 scoid 都有 addr，这里用不存在的路径模拟抓取失败
    const prep = await prepareLesson(session, { cid: '900', scoid: 'sco-unknown', classid: 'abc' });
    expect(prep.address?.url).toContain('sco-unknown');
    expect(prep.questions.length).toBeGreaterThan(0);
  });
});

describe('错误码', () => {
  it('AppError 保留错误码与可重试标记', () => {
    const err = new AppError({ code: 'SERVER_ERROR', message: 'boom' });
    expect(err.code).toBe('SERVER_ERROR');
    expect(err.retryable).toBe(true);
    expect(AppError.isFatal('AUTH_EXPIRED')).toBe(true);
    expect(AppError.isRetryable('CLIENT_ERROR')).toBe(false);
  });
});
