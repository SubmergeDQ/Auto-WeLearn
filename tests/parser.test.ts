import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parseSco, reconcileBlankAnswer } from '../src/core/parse/sco-parser.js';

const fixture = (name: string): string => readFileSync(join(process.cwd(), 'fixtures', name), 'utf8');

describe('courseware 解析（data-controltype / data-itemtype）', () => {
  const result = parseSco(fixture('sco-courseware.html'));

  it('识别为 courseware 策略', () => {
    expect(result.strategy).toBe('courseware');
  });

  it('解析出 7 道题，跳过 1 道口语题', () => {
    expect(result.questions).toHaveLength(7);
    expect(result.oral).toBe(1);
  });

  it('填空题取 data-solution 而不是带中文注释的 result', () => {
    expect(result.questions[0]).toEqual({ type: 'blank', answer: 'cello', tag: 'filling' });
  });

  it('斜杠分隔的多个答案，取与 result 一致的那一段', () => {
    expect(result.questions[1]?.answer).toBe('for');
  });

  it('罗马数字前缀原样透传，不做清洗', () => {
    expect(result.questions[2]?.answer).toBe('i. wanting sth. that sb. else has');
  });

  it('长填空 result 为空时退回 data-solution', () => {
    expect(result.questions[3]).toEqual({
      type: 'blank',
      answer: 'Because he wanted to stay independent.',
      tag: 'fillinglong',
    });
  });

  it('两个选项为 T/F 时归一成判断题，答案取选项字母', () => {
    expect(result.questions[4]).toEqual({ type: 'tof', answer: 'F', tag: 'choice' });
  });

  it('单选题取字母前缀而不是整行文本', () => {
    expect(result.questions[5]).toEqual({ type: 'choice', answer: 'C', tag: 'choice' });
  });

  it('多选题把多个正确项用逗号连接', () => {
    expect(result.questions[6]).toEqual({ type: 'choice', answer: 'A,C', tag: 'choice' });
  });

  it('无答案的块产生 warning 而不是空答案', () => {
    expect(result.warnings.some((w) => w.includes('t1_9'))).toBe(true);
  });

  it('原样保留题目顺序（平台按顺序判分）', () => {
    expect(result.questions.map((q) => q.answer)).toEqual([
      'cello',
      'for',
      'i. wanting sth. that sb. else has',
      'Because he wanted to stay independent.',
      'F',
      'C',
      'A,C',
    ]);
  });
});

describe('legacy 解析（et-* 标签）', () => {
  const result = parseSco(fixture('sco-legacy.html'));

  it('识别为 legacy 策略', () => {
    expect(result.strategy).toBe('legacy');
  });

  it('按 §9.2 期望解析出 7 道题 + 1 道口语', () => {
    expect(result.questions).toHaveLength(7);
    expect(result.oral).toBe(1);
  });

  it('题型与答案正确', () => {
    const byAnswer = Object.fromEntries(result.questions.map((q) => [q.answer, q.type]));
    expect(byAnswer['hello']).toBe('blank');
    expect(byAnswer['world']).toBe('blank');
    expect(byAnswer['A']).toBe('choice');
    expect(byAnswer['B,C']).toBe('choice');
    expect(byAnswer['T']).toBe('tof');
    expect(byAnswer['1-a,2-b']).toBe('match');
    expect(byAnswer['3,1,2']).toBe('order');
  });
});

describe('空模板与异常输入', () => {
  it('空字符串 → none 策略且不抛错', () => {
    const r = parseSco('');
    expect(r.strategy).toBe('none');
    expect(r.questions).toHaveLength(0);
  });

  it('无题目的合法 HTML → none 策略', () => {
    const r = parseSco('<html><body><p>hello</p></body></html>');
    expect(r.strategy).toBe('none');
    expect(r.questions).toHaveLength(0);
  });
});

describe('reconcileBlankAnswer', () => {
  it('result 带注释时保留 solution', () => {
    expect(reconcileBlankAnswer('cello', 'cello（大提琴）')).toBe('cello');
  });

  it('result 与 solution 一致时直接返回', () => {
    expect(reconcileBlankAnswer('forest', 'forest')).toBe('forest');
  });

  it('斜杠多答案按 result 命中', () => {
    expect(reconcileBlankAnswer('to/reply to', 'to')).toBe('to');
    expect(reconcileBlankAnswer('at/stared at', 'at')).toBe('at');
  });

  it('result 为空时用 solution', () => {
    expect(reconcileBlankAnswer('envious', '')).toBe('envious');
  });

  it('两字段都空时返回空串', () => {
    expect(reconcileBlankAnswer('', '')).toBe('');
  });

  it('括号出现在中间时不被误删', () => {
    expect(reconcileBlankAnswer('a (b) c', 'a (b) c')).toBe('a (b) c');
  });
});
