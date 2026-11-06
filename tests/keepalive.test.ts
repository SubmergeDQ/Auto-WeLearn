import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { runKeepalive } from '../src/core/run/keepalive.js';
import { abortError } from '../src/core/sleep.js';
import { Session } from '../src/core/http/session.js';
import { startMockServer, type MockServer } from './helpers/mock-server.js';

const UA = 'Mozilla/5.0 (Test) Chrome/131.0.0.0';
const BEAT_ACTION = 'keepsco_with_getticket_with_updatecmitime';

let mock: MockServer;

function makeSession(): Session {
  const session = new Session({ baseUrl: mock.baseUrl, userAgent: UA, timeoutMs: 5000 });
  session.setCookies([{ name: 'area', value: 'dbC' }]);
  return session;
}

const ctx = { cid: '900', scoid: 'sco-keepalive', uid: '123', classid: 'abc' };

beforeAll(async () => {
  mock = await startMockServer();
});

afterAll(async () => {
  await mock.close();
});

beforeEach(() => {
  mock.failActions.clear();
});

const noSleep = async (): Promise<void> => undefined;

describe('心跳节奏', () => {
  it('60s 等待产生 2 次心跳（30s 一次 + 结束补一次）', async () => {
    const result = await runKeepalive(
      { session: makeSession(), ctx: { ...ctx, scoid: 'sco-beats' }, totalBefore: 120, targetSec: 60 },
      { sleep: noSleep, random: () => 0 },
    );

    expect(result.elapsed).toBe(60);
    expect(result.heartbeats).toBe(2);
    expect(result.supported).toBe(true);
  });

  it('心跳里的 session_time 单调递增，total_time = 历史 + 本节', async () => {
    const session = makeSession();
    await runKeepalive(
      { session, ctx: { ...ctx, scoid: 'sco-monotonic' }, totalBefore: 120, targetSec: 60 },
      { sleep: noSleep, random: () => 0 },
    );

    const beats = mock.calls(BEAT_ACTION).filter((p) => p.get('scoid') === 'sco-monotonic');
    expect(beats.map((b) => b.get('session_time'))).toEqual(['30', '60']);
    expect(beats.map((b) => b.get('total_time'))).toEqual(['150', '180']);
  });

  it('等待时长为 0 时不发心跳', async () => {
    const result = await runKeepalive(
      { session: makeSession(), ctx: { ...ctx, scoid: 'sco-zero' }, totalBefore: 0, targetSec: 0 },
      { sleep: noSleep, random: () => 0 },
    );
    expect(result.elapsed).toBe(0);
    expect(result.heartbeats).toBe(0);
  });

  it('每 1 秒醒来一次，共 target 次', async () => {
    let ticks = 0;
    const counting = async (): Promise<void> => {
      ticks++;
    };
    await runKeepalive(
      { session: makeSession(), ctx: { ...ctx, scoid: 'sco-ticks' }, totalBefore: 0, targetSec: 10 },
      { sleep: counting, random: () => 0 },
    );
    expect(ticks).toBe(10);
  });
});

describe('心跳异常处理', () => {
  it('平台拒绝心跳时降级为纯等待，不抛错', async () => {
    mock.failActions.add(BEAT_ACTION);
    const result = await runKeepalive(
      { session: makeSession(), ctx: { ...ctx, scoid: 'sco-rejected' }, totalBefore: 0, targetSec: 60 },
      { sleep: noSleep, random: () => 0 },
    );

    expect(result.supported).toBe(false);
    expect(result.heartbeats).toBe(0);
    expect(result.elapsed).toBe(60);
  });

  it('abort 后立即中断等待', async () => {
    const controller = new AbortController();
    let ticks = 0;
    const abortAt5 = async (): Promise<void> => {
      if (controller.signal.aborted) throw abortError();
      ticks++;
      if (ticks >= 5) controller.abort();
    };

    await expect(
      runKeepalive(
        {
          session: makeSession(),
          ctx: { ...ctx, scoid: 'sco-abort' },
          totalBefore: 0,
          targetSec: 60,
          signal: controller.signal,
        },
        { sleep: abortAt5, random: () => 0 },
      ),
    ).rejects.toThrow('操作已被中断');

    expect(ticks).toBe(5);
  });
});
