import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { runLesson } from '../src/core/run/lesson-runner.js';
import { Session } from '../src/core/http/session.js';
import { abortError } from '../src/core/sleep.js';
import { startMockServer, type MockServer } from './helpers/mock-server.js';

const UA = 'Mozilla/5.0 (Test) Chrome/131.0.0.0';

let mock: MockServer;

function makeSession(): Session {
  const session = new Session({ baseUrl: mock.baseUrl, userAgent: UA, timeoutMs: 5000 });
  session.setCookies([{ name: 'area', value: 'dbC' }]);
  return session;
}

const noSleep = async (): Promise<void> => undefined;
const noRandom = (): number => 0;

function baseParams(scoid: string, overrides: Record<string, unknown> = {}) {
  return {
    session: makeSession(),
    ctx: { cid: '900', scoid, uid: '123', classid: 'abc' },
    location: `Unit 1 > ${scoid}`,
    crate: 100,
    waitSec: 60,
    retry: { max: 0, baseDelayMs: 1 },
    cmiTime: 'total' as const,
    ...overrides,
  };
}

beforeAll(async () => {
  mock = await startMockServer();
});

afterAll(async () => {
  await mock.close();
});

beforeEach(() => {
  mock.failActions.clear();
});

describe('成功路径', () => {
  it('三个写操作按顺序执行，最终状态 done', async () => {
    const result = await runLesson(baseParams('sco-ok'), { sleep: noSleep, random: noRandom });

    expect(result.status).toBe('done');
    expect(result.stats).toEqual({ questions: 7, oral: 1, answered: 7 });
    expect(result.heartbeats).toBe(2);
    expect(result.waitSec).toBe(60);

    const actions = mock
      .calls('startsco160928')
      .filter((p) => p.get('scoid') === 'sco-ok')
      .map((p) => p.get('scoid'));
    expect(actions).toHaveLength(1);
    expect(mock.calls('setscoinfo').filter((p) => p.get('scoid') === 'sco-ok')).toHaveLength(1);
    expect(mock.calls('savescoinfo160928').filter((p) => p.get('scoid') === 'sco-ok')).toHaveLength(1);
  });

  it('setscoinfo 的 data 结构符合平台要求', async () => {
    await runLesson(baseParams('sco-payload'), { sleep: noSleep, random: noRandom });

    const call = mock.calls('setscoinfo').find((p) => p.get('scoid') === 'sco-payload');
    const data = call?.get('data') ?? '';

    expect(call?.get('isend')).toBe('False');
    expect(call?.get('uid')).toBe('123');
    expect(call?.get('cid')).toBe('900');
    expect(data).toContain('[INTERACTIONINFO]');

    const [json, info] = data.split('[INTERACTIONINFO]');
    const parsed = JSON.parse(json ?? '{}') as { cmi: Record<string, unknown> };
    expect(parsed.cmi.completion_status).toBe('completed');
    expect(parsed.cmi.session_time).toBe('60');
    // mock 的 CMI 历史累计是 120s
    expect(parsed.cmi.total_time).toBe('180');
    expect((parsed.cmi.score as { scaled: string }).scaled).toBe('100');
    expect(Array.isArray(parsed.cmi.interactions)).toBe(true);
    expect(info?.split('$$')).toHaveLength(7);
  });

  it('savescoinfo 的参数逐项正确', async () => {
    await runLesson(baseParams('sco-save'), { sleep: noSleep, random: noRandom });

    const call = mock.calls('savescoinfo160928').find((p) => p.get('scoid') === 'sco-save');
    expect(call?.get('progress')).toBe('100');
    expect(call?.get('crate')).toBe('100');
    expect(call?.get('status')).toBe('unknown');
    expect(call?.get('cstatus')).toBe('completed');
    expect(call?.get('trycount')).toBe('0');
    expect(call?.get('session_time')).toBe('60');
    expect(call?.get('total_time')).toBe('180');
  });

  it('cmiTime=session 时 total_time 只写本节秒数', async () => {
    await runLesson(baseParams('sco-session', { cmiTime: 'session' }), { sleep: noSleep, random: noRandom });

    const call = mock.calls('savescoinfo160928').find((p) => p.get('scoid') === 'sco-session');
    expect(call?.get('total_time')).toBe('60');
  });

  it('从未学过的小节（CMI 未初始化）不重复 startsco，total_time 只算本节', async () => {
    const result = await runLesson(baseParams('sco-fresh'), { sleep: noSleep, random: noRandom });

    expect(result.status).toBe('done');
    // startsco 只应发生一次：getCmi 读到 -1 时不应再补发
    expect(mock.calls('startsco160928').filter((p) => p.get('scoid') === 'sco-fresh')).toHaveLength(1);

    const call = mock.calls('savescoinfo160928').find((p) => p.get('scoid') === 'sco-fresh');
    expect(call?.get('total_time')).toBe('60');
  });

  it('没有题目的媒体页也照常提交，interactions 为空', async () => {
    const result = await runLesson(baseParams('sco-empty'), { sleep: noSleep, random: noRandom });

    expect(result.status).toBe('done');
    expect(result.stats.questions).toBe(0);

    const call = mock.calls('setscoinfo').find((p) => p.get('scoid') === 'sco-empty');
    const data = call?.get('data') ?? '';
    expect(data.endsWith('[INTERACTIONINFO]')).toBe(true);
    const parsed = JSON.parse(data.split('[INTERACTIONINFO]')[0] ?? '{}') as { cmi: { interactions: unknown[] } };
    expect(parsed.cmi.interactions).toEqual([]);
  });
});

describe('部分失败与异常', () => {
  it('savescoinfo 被拒时状态为 partial', async () => {
    mock.failActions.add('savescoinfo160928');
    const result = await runLesson(baseParams('sco-partial'), { sleep: noSleep, random: noRandom });

    expect(result.status).toBe('partial');
    expect(mock.calls('setscoinfo').some((p) => p.get('scoid') === 'sco-partial')).toBe(true);
  });

  it('startsco 被拒时不发后续写请求，状态 failed', async () => {
    mock.failActions.add('startsco160928');
    const result = await runLesson(baseParams('sco-startfail'), { sleep: noSleep, random: noRandom });

    expect(result.status).toBe('failed');
    expect(result.errorCode).toBe('PLATFORM_REJECTED');
    expect(mock.calls('setscoinfo').some((p) => p.get('scoid') === 'sco-startfail')).toBe(false);
    expect(mock.calls('savescoinfo160928').some((p) => p.get('scoid') === 'sco-startfail')).toBe(false);
  });
});

describe('中断语义', () => {
  it('等待期间中断：状态 interrupted，且不提交半截数据', async () => {
    const controller = new AbortController();
    let ticks = 0;
    const abortAt3 = async (): Promise<void> => {
      if (controller.signal.aborted) throw abortError();
      ticks++;
      if (ticks >= 3) controller.abort();
    };

    const result = await runLesson(baseParams('sco-abort', { signal: controller.signal }), {
      sleep: abortAt3,
      random: noRandom,
    });

    expect(result.status).toBe('interrupted');
    expect(mock.calls('startsco160928').some((p) => p.get('scoid') === 'sco-abort')).toBe(true);
    expect(mock.calls('setscoinfo').some((p) => p.get('scoid') === 'sco-abort')).toBe(false);
    expect(mock.calls('savescoinfo160928').some((p) => p.get('scoid') === 'sco-abort')).toBe(false);
  });

  it('开始前已中断：不产生任何写请求', async () => {
    const controller = new AbortController();
    controller.abort();

    const result = await runLesson(baseParams('sco-preabort', { signal: controller.signal }), {
      sleep: noSleep,
      random: noRandom,
    });

    expect(result.status).toBe('interrupted');
    // 预中断时连 scoAddr 都不该发出
    const related = mock.requests.filter((r) => r.pathname === '/Ajax/SCO.aspx' && r.body.includes('sco-preabort'));
    expect(related).toHaveLength(0);
  });
});
