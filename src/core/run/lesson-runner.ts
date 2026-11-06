import { AppError, toAppError } from '../errors.js';
import type { Logger } from '../../logging/logger.js';
import type { LessonResult, LessonStats, LessonStatus } from '../../types/domain.js';
import type { Session } from '../http/session.js';
import { withRetry } from '../http/retry.js';
import { getCmi, saveScoInfo, setScoInfo, startSco, type ScoContext } from '../api/sco.js';
import { generateInteractions } from '../parse/interactions.js';
import { prepareLesson } from './prepare.js';
import { buildScoData } from './payload.js';
import { runKeepalive, type KeepaliveDeps } from './keepalive.js';

/**
 * 单节状态机（§4.3）。
 *
 * 关键约定：
 * - 中断时不补发 savescoinfo，避免写入半截成绩；
 * - 两个写请求至少要有一个 ret:0 才算 partial，全失败才 failed；
 * - 心跳失败不中断流程，只降级。
 */

export interface LessonRunParams {
  session: Session;
  ctx: ScoContext;
  location: string;
  /** 本节目标正确率，进入前已按 rate 计划抽好 */
  crate: number;
  /** 本节等待秒数，进入前已按 wait 计划抽好 */
  waitSec: number;
  retry: { max: number; baseDelayMs: number };
  cmiTime: 'session' | 'total';
  signal?: AbortSignal;
  logger?: Logger;
}

export interface LessonRunDeps extends KeepaliveDeps {
  /** 透传给 interactions 生成，测试里固定正确率 */
  random?: () => number;
}

export async function runLesson(params: LessonRunParams, deps: LessonRunDeps = {}): Promise<LessonResult> {
  const { session, ctx, logger, signal } = params;
  const retryOpts = {
    max: params.retry.max,
    baseDelayMs: params.retry.baseDelayMs,
    signal,
    logger,
  };

  const stats: LessonStats = { questions: 0, oral: 0, answered: 0 };
  let heartbeats = 0;
  let elapsed = 0;
  let attempts = 0;

  const base = (): Pick<LessonResult, 'scoid' | 'location' | 'crate' | 'waitSec' | 'stats' | 'attempts'> => ({
    scoid: ctx.scoid,
    location: params.location,
    crate: params.crate,
    waitSec: elapsed,
    stats,
    attempts,
  });

  try {
    // ── 1. 解析题目（失败退化为空 interactions，不阻断提交） ──
    const prep = await prepareLesson(session, ctx, { signal, logger });
    stats.questions = prep.questions.length;
    stats.oral = prep.oral;
    const bundle = generateInteractions(prep.questions, { crate: params.crate, random: deps.random });
    stats.answered = bundle.interactions.length;

    logger?.info(
      `解析 ${stats.questions} 题（跳过 ${stats.oral} 道口语题）  等待 ${Math.floor(params.waitSec / 60)
        .toString()
        .padStart(2, '0')}:${String(params.waitSec % 60).padStart(2, '0')}  rate=${params.crate}%`,
    );
    for (const warning of prep.warnings.slice(0, 3)) logger?.warn(warning);

    // ── 2. 注册学习会话 ──
    attempts++;
    await withRetry(async () => {
      const ok = await startSco(session, ctx, { signal });
      if (!ok) {
        throw new AppError({ code: 'PLATFORM_REJECTED', message: 'startsco 未被平台接受', retryable: false });
      }
    }, { ...retryOpts, label: 'startsco' });

    // ── 3. 读历史累计时长（失败降级为 0） ──
    let totalBefore = 0;
    try {
      const cmi = await getCmi(session, ctx, { signal, logger, alreadyStarted: true });
      if (cmi.ok) {
        totalBefore = cmi.totalBefore;
        logger?.debug(`CMI 历史累计 ${totalBefore}s`);
      } else if (cmi.reason === 'uninitialized') {
        // 从未学过的小节没有 CMI，属于正常状态
        logger?.debug('本节没有历史 CMI，totalBefore=0');
      } else {
        logger?.warn('CMI 读取失败，按 totalBefore=0 继续（cmi_unavailable）');
      }
    } catch (err) {
      const appErr = toAppError(err);
      if (appErr.code === 'INTERRUPTED' || appErr.code === 'AUTH_EXPIRED') throw appErr;
      logger?.warn(`CMI 读取异常，按 totalBefore=0 继续：${appErr.message}`);
    }

    // ── 4. 等待 + 心跳 ──
    const keepalive = await runKeepalive(
      { session, ctx, totalBefore, targetSec: params.waitSec, signal, logger },
      { sleep: deps.sleep, random: deps.random, beatMinSec: deps.beatMinSec, beatMaxSec: deps.beatMaxSec },
    );
    elapsed = keepalive.elapsed;
    heartbeats = keepalive.heartbeats;

    const sessionTime = keepalive.elapsed;
    const totalTime = params.cmiTime === 'session' ? sessionTime : totalBefore + sessionTime;
    const data = buildScoData(
      { interactions: bundle.interactions, crate: params.crate, sessionTime, totalTime },
      bundle.interactionInfo,
    );

    // ── 5. 提交 SCORM 数据 ──
    const setOk = await withRetry(
      () => setScoInfo(session, ctx, data, { signal }),
      { ...retryOpts, label: 'setscoinfo' },
    );

    // ── 6. 保存进度与成绩 ──
    const saveOk = await withRetry(
      () => saveScoInfo(session, ctx, { crate: params.crate, sessionTime, totalTime }, { signal }),
      { ...retryOpts, label: 'savescoinfo' },
    );

    const status: LessonStatus = setOk && saveOk ? 'done' : setOk || saveOk ? 'partial' : 'failed';

    if (status === 'partial') {
      logger?.warn(`仅部分写入成功（setscoinfo=${setOk ? 'ok' : 'fail'} savescoinfo=${saveOk ? 'ok' : 'fail'}）`);
    }

    return {
      ...base(),
      status,
      waitSec: elapsed,
      heartbeats,
      ...(status === 'failed' ? { errorCode: 'PLATFORM_REJECTED' } : {}),
    };
  } catch (raw) {
    const err = toAppError(raw);

    if (err.code === 'INTERRUPTED') {
      return { ...base(), status: 'interrupted', waitSec: elapsed, heartbeats };
    }

    if (err.code === 'AUTH_EXPIRED') throw err;

    return {
      ...base(),
      status: 'failed',
      waitSec: elapsed,
      heartbeats,
      errorCode: err.code,
      errorMessage: err.message,
    };
  }
}
