import { describe, expect, it } from 'vitest';
import { jsEscape } from '../src/core/parse/js-escape.js';
import { generateInteractions, wrongAnswerFor } from '../src/core/parse/interactions.js';
import type { Question } from '../src/types/domain.js';

const q = (type: Question['type'], answer: string): Question => ({ type, answer, tag: 'test' });

/** 固定随机源：always = 0 表示全部判对，1 表示全部判错 */
const always = (value: number) => () => value;

describe('jsEscape', () => {
  it('保留字母数字与白名单符号', () => {
    expect(jsEscape('Abc123@*-_+./')).toBe('Abc123@*-_+./');
  });

  it('空格与标点转 %XX', () => {
    expect(jsEscape('a b,c')).toBe('a%20b%2Cc');
  });

  it('百分号自身也被转义', () => {
    expect(jsEscape('%')).toBe('%25');
  });

  it('中文按码元转 %uXXXX（大写十六进制）', () => {
    expect(jsEscape('中文')).toBe('%u4E2D%u6587');
  });

  it('中文 + 空格 + 符号混合', () => {
    expect(jsEscape('中文 A@')).toBe('%u4E2D%u6587%20A@');
  });

  it('emoji 拆成代理对，与浏览器 escape() 一致', () => {
    expect(jsEscape('😀')).toBe('%uD83D%uDE00');
  });

  it('空串返回空串', () => {
    expect(jsEscape('')).toBe('');
  });
});

describe('wrongAnswerFor', () => {
  it('判断题取反', () => {
    expect(wrongAnswerFor(q('tof', 'T'), 0)).toBe('f');
    expect(wrongAnswerFor(q('tof', 'f'), 0)).toBe('t');
  });

  it('选择题 A→B，其余→A', () => {
    expect(wrongAnswerFor(q('choice', 'A'), 0)).toBe('B');
    expect(wrongAnswerFor(q('choice', 'C'), 0)).toBe('A');
  });

  it('填空与匹配题用占位错答', () => {
    expect(wrongAnswerFor(q('blank', 'Paris'), 3)).toBe('wrong_answer_3');
    expect(wrongAnswerFor(q('match', '1-a'), 4)).toBe('wrong_answer_4');
    expect(wrongAnswerFor(q('order', '3,1,2'), 5)).toBe('wrong_answer_5');
  });
});

describe('generateInteractions', () => {
  const questions = [q('blank', 'Paris'), q('tof', 'T'), q('choice', 'A')];

  it('100% 正确率时全部 correct 且带 correct_responses', () => {
    const { interactions } = generateInteractions(questions, { crate: 100, random: always(0) });
    expect(interactions.map((i) => i.result)).toEqual(['correct', 'correct', 'correct']);
    expect(interactions[0]?.correct_responses).toEqual([{ pattern: 'Paris' }]);
  });

  it('0% 正确率时全部 wrong 且不带 correct_responses', () => {
    const { interactions } = generateInteractions(questions, { crate: 0, random: always(0.999) });
    expect(interactions.map((i) => i.result)).toEqual(['wrong', 'wrong', 'wrong']);
    expect(interactions.every((i) => i.correct_responses === undefined)).toBe(true);
    expect(interactions.map((i) => i.student_response)).toEqual(['wrong_answer_0', 'f', 'B']);
  });

  it('interactionInfo 用 $$ 连接，顺序与 interactions 一致', () => {
    const { interactions, interactionInfo } = generateInteractions(questions, { crate: 100, random: always(0) });
    const parts = interactionInfo.split('$$');
    expect(parts).toHaveLength(3);
    expect(parts[0]).toBe('0[]false[]false[]Paris[]correct');
    expect(parts[1]).toBe('1[]false[]false[]T[]correct');
    expect(parts[2]).toBe('2[]false[]false[]A[]correct');
    expect(interactions).toHaveLength(3);
  });

  it('正确率按题目逐题抽样，同节内允许混合', () => {
    const seq = [0, 0.99, 0];
    let i = 0;
    const { interactions } = generateInteractions(questions, {
      crate: 50,
      random: () => seq[i++] ?? 0,
    });
    expect(interactions.map((x) => x.result)).toEqual(['correct', 'wrong', 'correct']);
  });

  it('id 依据下标生成，weighting 恒为 "1"', () => {
    const { interactions } = generateInteractions(questions, { crate: 100, random: always(0) });
    expect(interactions.map((i) => i.id)).toEqual(['interaction_0', 'interaction_1', 'interaction_2']);
    expect(interactions.every((i) => i.weighting === '1')).toBe(true);
  });

  it('空题目列表产出空结构', () => {
    const bundle = generateInteractions([], { crate: 100, random: always(0) });
    expect(bundle.interactions).toEqual([]);
    expect(bundle.interactionInfo).toBe('');
  });
});
