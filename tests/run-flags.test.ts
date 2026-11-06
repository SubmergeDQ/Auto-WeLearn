import { describe, expect, it } from 'vitest';
import { ConfigError } from '../src/core/errors.js';
import {
  parseInterval,
  parseRate,
  parseRunFlags,
  parseUnit,
  parseWait,
} from '../src/cli/parse-run-flags.js';

const STATE = '~/.welearn-cli/state.json';

describe('--rate', () => {
  it('单值解析为固定模式', () => {
    expect(parseRate('93')).toEqual({ mode: 'fixed', value: 93 });
  });

  it('区间解析为 range 模式', () => {
    expect(parseRate('90-100')).toEqual({ mode: 'range', min: 90, max: 100 });
  });

  it('缺省为 90-100', () => {
    expect(parseRate(undefined)).toEqual({ mode: 'range', min: 90, max: 100 });
  });

  it('非法值抛 ConfigError', () => {
    expect(() => parseRate('abc')).toThrow(ConfigError);
    expect(() => parseRate('90-')).toThrow(ConfigError);
  });
});

describe('--wait', () => {
  it('单值与区间', () => {
    expect(parseWait('60')).toEqual({ mode: 'fixed', seconds: 60 });
    expect(parseWait('300-420')).toEqual({ mode: 'range', min: 300, max: 420 });
  });

  it('缺省为 300-480', () => {
    expect(parseWait(undefined)).toEqual({ mode: 'range', min: 300, max: 480 });
  });
});

describe('--interval', () => {
  it('区间与单值', () => {
    expect(parseInterval('3-8')).toEqual({ min: 3, max: 8 });
    expect(parseInterval('5')).toEqual({ min: 5, max: 5 });
    expect(parseInterval(undefined)).toEqual({ min: 3, max: 8 });
  });
});

describe('--unit', () => {
  it('all 与正整数', () => {
    expect(parseUnit('all')).toBe('all');
    expect(parseUnit(undefined)).toBe('all');
    expect(parseUnit('3')).toBe(3);
  });

  it('0 与负数被拒绝', () => {
    expect(() => parseUnit('0')).toThrow(ConfigError);
    expect(() => parseUnit('-1')).toThrow(ConfigError);
  });
});

describe('安全下限', () => {
  it('等待低于 30s 默认拒绝', () => {
    expect(() => parseRunFlags({ course: '566', wait: '10' }, STATE)).toThrow(/安全下限/);
  });

  it('--unsafe-fast 可放行', () => {
    const config = parseRunFlags({ course: '566', wait: '10', unsafeFast: true }, STATE);
    expect(config.wait).toEqual({ mode: 'fixed', seconds: 10 });
  });

  it('区间下限低于 30 也被拦', () => {
    expect(() => parseRunFlags({ course: '566', wait: '10-300' }, STATE)).toThrow(/安全下限/);
  });
});

describe('组合配置', () => {
  it('缺 --course 抛 ConfigError', () => {
    expect(() => parseRunFlags({}, STATE)).toThrow(/缺少 --course/);
  });

  it('默认值符合规格', () => {
    const config = parseRunFlags({ course: '566' }, STATE);
    expect(config).toMatchObject({
      course: '566',
      unit: 'all',
      concurrency: 1,
      skipOralLesson: true,
      skipOralQuestion: true,
      dryRun: false,
      resume: false,
      cmiTime: 'total',
      statePath: STATE,
    });
  });

  it('--no-skip-oral 关闭整节口语跳过', () => {
    const config = parseRunFlags({ course: '566', skipOral: false }, STATE);
    expect(config.skipOralLesson).toBe(false);
  });

  it('--keep-oral-questions 覆盖题目级跳过', () => {
    const config = parseRunFlags({ course: '566', keepOralQuestions: true }, STATE);
    expect(config.skipOralQuestion).toBe(false);
  });

  it('并发数超出 1/2/3 被拒绝', () => {
    expect(() => parseRunFlags({ course: '566', concurrency: '4' }, STATE)).toThrow(ConfigError);
    expect(parseRunFlags({ course: '566', concurrency: '2' }, STATE).concurrency).toBe(2);
  });

  it('--cmi-time 只接受 session/total', () => {
    expect(parseRunFlags({ course: '566', cmiTime: 'session' }, STATE).cmiTime).toBe('session');
    expect(parseRunFlags({ course: '566', cmiTime: 'weird' }, STATE).cmiTime).toBe('total');
  });
});
