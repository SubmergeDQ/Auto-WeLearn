import { describe, expect, it } from 'vitest';
import { estimateDuration, pickCrate, pickInterval, pickWait, randomInt } from '../src/core/plan/time-plan.js';

describe('randomInt', () => {
  it('下界取 min', () => {
    expect(randomInt(30, 40, () => 0)).toBe(30);
  });

  it('接近 1 时取 max（不会越界）', () => {
    expect(randomInt(30, 40, () => 0.999999)).toBe(40);
  });

  it('min==max 时返回该值', () => {
    expect(randomInt(5, 5, () => 0.5)).toBe(5);
  });

  it('参数颠倒也能工作', () => {
    expect(randomInt(40, 30, () => 0)).toBe(30);
  });
});

describe('pickWait', () => {
  it('固定值直接返回', () => {
    expect(pickWait({ mode: 'fixed', seconds: 60 }, () => 0.9)).toBe(60);
  });

  it('区间在边界内取值', () => {
    expect(pickWait({ mode: 'range', min: 300, max: 480 }, () => 0)).toBe(300);
    expect(pickWait({ mode: 'range', min: 300, max: 480 }, () => 0.999999)).toBe(480);
  });
});

describe('pickCrate', () => {
  it('区间抽样并四舍五入', () => {
    expect(pickCrate({ mode: 'range', min: 90, max: 100 }, () => 0.5)).toBe(95);
  });

  it('固定值原样返回', () => {
    expect(pickCrate({ mode: 'fixed', value: 93 }, () => 0.5)).toBe(93);
  });

  it('超出 0-100 时被夹住', () => {
    expect(pickCrate({ mode: 'fixed', value: 130 }, () => 0)).toBe(100);
    expect(pickCrate({ mode: 'fixed', value: -5 }, () => 0)).toBe(0);
  });
});

describe('pickInterval', () => {
  it('区间内取值', () => {
    expect(pickInterval({ min: 3, max: 8 }, () => 0.5)).toBeCloseTo(5.5, 5);
  });

  it('min==max 时返回 min', () => {
    expect(pickInterval({ min: 4, max: 4 }, () => 0.9)).toBe(4);
  });
});

describe('estimateDuration', () => {
  it('固定等待只受节间间隔影响', () => {
    expect(estimateDuration({ mode: 'fixed', seconds: 300 }, { min: 3, max: 8 }, 10)).toEqual({
      min: 3030,
      max: 3080,
    });
  });

  it('区间等待给出上下界', () => {
    expect(estimateDuration({ mode: 'range', min: 300, max: 480 }, { min: 3, max: 8 }, 2)).toEqual({
      min: 606,
      max: 976,
    });
  });

  it('空队列为 0', () => {
    expect(estimateDuration({ mode: 'range', min: 300, max: 480 }, { min: 3, max: 8 }, 0)).toEqual({
      min: 0,
      max: 0,
    });
  });
});
