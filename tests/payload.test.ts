import { describe, expect, it } from 'vitest';
import { buildCmi, buildScoData, INTERACTION_MARKER } from '../src/core/run/payload.js';
import type { Interaction } from '../src/types/domain.js';

const interactions: Interaction[] = [
  {
    id: 'interaction_0',
    type: 'tof',
    student_response: 'F',
    result: 'correct',
    weighting: '1',
    correct_responses: [{ pattern: 'F' }],
  },
];

const baseParams = {
  interactions,
  crate: 93,
  sessionTime: 372,
  totalTime: 1232,
};

describe('buildCmi', () => {
  it('字段与真实请求一致，数字都转成字符串', () => {
    expect(buildCmi(baseParams)).toEqual({
      completion_status: 'completed',
      interactions,
      launch_data: '',
      progress_measure: '1',
      score: { scaled: '93', raw: '100' },
      session_time: '372',
      success_status: 'unknown',
      total_time: '1232',
      mode: 'normal',
    });
  });

  it('crate 四舍五入后写入 scaled', () => {
    expect(buildCmi({ ...baseParams, crate: 92.6 }).score.scaled).toBe('93');
  });

  it('负数时间被夹到 0', () => {
    const cmi = buildCmi({ ...baseParams, sessionTime: -5, totalTime: -1 });
    expect(cmi.session_time).toBe('0');
    expect(cmi.total_time).toBe('0');
  });
});

describe('buildScoData', () => {
  it('以 [INTERACTIONINFO] 分隔 JSON 与答题串', () => {
    const data = buildScoData(baseParams, '0[]false[]false[]F[]correct');
    const [json, info] = data.split(INTERACTION_MARKER);
    expect(info).toBe('0[]false[]false[]F[]correct');
    expect(() => JSON.parse(json ?? '')).not.toThrow();
  });

  it('答题串为空时仍然保留标记', () => {
    const data = buildScoData({ ...baseParams, interactions: [] }, '');
    expect(data.endsWith(INTERACTION_MARKER)).toBe(true);
  });

  it('顶层结构是 cmi / adl / cci 三段', () => {
    const parsed = JSON.parse(buildScoData(baseParams, '').split(INTERACTION_MARKER)[0] ?? '{}') as Record<
      string,
      unknown
    >;
    expect(Object.keys(parsed)).toEqual(['cmi', 'adl', 'cci']);
  });

  it('cci.service 下的固定字段齐全', () => {
    const parsed = JSON.parse(buildScoData(baseParams, '').split(INTERACTION_MARKER)[0] ?? '{}') as {
      cci: { service: Record<string, unknown>; retry_count: string; submit_time: string };
    };
    expect(parsed.cci.service).toMatchObject({
      dictionary: { headword: '', short_cuts: '' },
      new_words: [],
      notes: [],
      writing_marking: [],
      record: { files: [] },
      play: { offline_media_id: '9999' },
    });
    expect(parsed.cci.retry_count).toBe('0');
    expect(parsed.cci.submit_time).toBe('');
  });

  it('key 顺序保持与规格一致（平台按字符串解析，顺序会影响兼容性）', () => {
    const json = buildScoData(baseParams, '').split(INTERACTION_MARKER)[0] ?? '';
    expect(json.startsWith('{"cmi":{"completion_status":"completed","interactions":')).toBe(true);
    expect(json).toContain('"success_status":"unknown","total_time":"1232","mode":"normal"');
  });

  it('中文答案不被转义成 \\u 序列', () => {
    const data = buildScoData(
      {
        ...baseParams,
        interactions: [{ ...interactions[0]!, student_response: '中文' }],
      },
      '',
    );
    expect(data).toContain('中文');
    expect(data).not.toContain('\\u4e2d');
  });
});
