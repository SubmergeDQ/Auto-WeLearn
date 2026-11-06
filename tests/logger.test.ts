import { describe, expect, it } from 'vitest';
import { createLogger, formatClock, formatDuration, redact } from '../src/logging/logger.js';

function capture() {
  const lines: string[] = [];
  return {
    lines,
    stream: {
      write(chunk: string) {
        lines.push(chunk);
        return true;
      },
    },
  };
}

const FIXED = new Date(2026, 10, 6, 10, 21, 6);

describe('redact', () => {
  it('脱敏裸值 cookie', () => {
    expect(redact('cookie=abc123')).toBe('cookie=[REDACTED]');
  });

  it('脱敏带引号的 JSON 字段', () => {
    const out = redact('{"pwd":"s3cret"}');
    expect(out).toBe('{"pwd":[REDACTED]}');
    expect(out).not.toContain('s3cret');
  });

  it('脱敏整条 Cookie 串，且不残留任何片段', () => {
    const out = redact('Cookie: ASP.NET_SessionId=abc; .AspNet.Cookies=XYZ');
    expect(out).not.toContain('abc');
    expect(out).not.toContain('XYZ');
    expect(out).toContain('[REDACTED]');
  });

  it('脱敏 Set-Cookie 与 Authorization', () => {
    const out = redact('Set-Cookie: a=1; Path=/  Authorization: Bearer abc.def');
    expect(out).not.toContain('a=1');
    expect(out).not.toContain('abc.def');
  });

  it('不误伤普通文本', () => {
    const text = 'scoid=m-1-3-5 课程 566 正确率 93%';
    expect(redact(text)).toBe(text);
  });

  it('不误伤命令行参数名', () => {
    expect(redact('--password-env WELEARN_PASSWORD')).toBe('--password-env WELEARN_PASSWORD');
  });
});

describe('logger', () => {
  it('输出格式与 §6.3 对齐', () => {
    const { lines, stream } = capture();
    const log = createLogger({ stream, now: () => FIXED });
    log.info('课程「新起点」cid=566');
    expect(lines[0]).toBe('[10:21:06] INFO  课程「新起点」cid=566\n');
  });

  it('阶段标签对齐', () => {
    const { lines, stream } = capture();
    const log = createLogger({ stream, now: () => FIXED });
    log.stage('RUN', '[1/42] Unit 1');
    log.stage('HB', '+32s / 372s');
    expect(lines[0]).toBe('[10:21:06] RUN   [1/42] Unit 1\n');
    expect(lines[1]).toBe('[10:21:06] HB    +32s / 372s\n');
  });

  it('日志本身也脱敏', () => {
    const { lines, stream } = capture();
    const log = createLogger({ stream, now: () => FIXED });
    log.info('cookie=abc');
    expect(lines[0]).toContain('[REDACTED]');
    expect(lines[0]).not.toContain('abc');
  });

  it('按级别过滤', () => {
    const { lines, stream } = capture();
    const log = createLogger({ stream, now: () => FIXED, level: 'warn' });
    log.info('不该出现');
    log.warn('应该出现');
    expect(lines).toHaveLength(1);
    expect(lines[0]).toContain('应该出现');
  });

  it('child 前缀会保留', () => {
    const { lines, stream } = capture();
    const log = createLogger({ stream, now: () => FIXED }).child('[1/42]');
    log.stage('DONE', '提交成功');
    expect(lines[0]).toBe('[10:21:06] DONE  [1/42] 提交成功\n');
  });
});

describe('格式化', () => {
  it('formatDuration', () => {
    expect(formatDuration(372)).toBe('6m12s');
    expect(formatDuration(4712)).toBe('1h18m32s');
    expect(formatDuration(45)).toBe('45s');
  });

  it('formatClock', () => {
    expect(formatClock(372)).toBe('06:12');
    expect(formatClock(59)).toBe('00:59');
  });
});
