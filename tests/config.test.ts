import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config/load.js';
import { ConfigError } from '../src/core/errors.js';

let dir: string;
let file: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'welearn-config-'));
  file = join(dir, 'config.json');
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('loadConfig', () => {
  it('无配置文件时使用默认值', () => {
    const config = loadConfig({ env: {} });
    expect(config).toMatchObject({
      baseUrl: 'https://welearn.sflep.com',
      timeoutMs: 15_000,
      statePath: '~/.welearn-cli/state.json',
      retry: { max: 3, baseDelayMs: 2000 },
    });
  });

  it('读取配置文件', () => {
    writeFileSync(file, JSON.stringify({ timeoutMs: 30_000, baseUrl: 'https://example.com' }), 'utf8');
    const config = loadConfig({ env: {}, filePath: file });
    expect(config.timeoutMs).toBe(30_000);
    expect(config.baseUrl).toBe('https://example.com');
  });

  it('环境变量覆盖配置文件', () => {
    writeFileSync(file, JSON.stringify({ baseUrl: 'https://from-file.example' }), 'utf8');
    const config = loadConfig({
      env: { WELEARN_BASE_URL: 'https://from-env.example' },
      filePath: file,
    });
    expect(config.baseUrl).toBe('https://from-env.example');
  });

  it('配置文件不存在时静默回退到默认值', () => {
    const config = loadConfig({ env: {}, filePath: join(dir, 'missing.json') });
    expect(config.timeoutMs).toBe(15_000);
  });

  it('配置文件不是合法 JSON 时抛 ConfigError', () => {
    writeFileSync(file, '{ oops', 'utf8');
    expect(() => loadConfig({ env: {}, filePath: file })).toThrow(ConfigError);
  });

  it('配置值越界时抛 ConfigError 且信息可读', () => {
    writeFileSync(file, JSON.stringify({ timeoutMs: 999_999 }), 'utf8');
    expect(() => loadConfig({ env: {}, filePath: file })).toThrow(/timeoutMs/);
  });
});
