import { describe, expect, it } from 'vitest';
import { ConfigError } from '../src/core/errors.js';
import { parseCookieInput } from '../src/core/auth/cookie.js';

describe('parseCookieInput', () => {
  it('解析浏览器复制格式', () => {
    expect(parseCookieInput('a=1; b=2')).toEqual([
      { name: 'a', value: '1' },
      { name: 'b', value: '2' },
    ]);
  });

  it('值里含等号时只按第一个等号切分', () => {
    expect(parseCookieInput('.AspNet.Cookies=abc=def=')).toEqual([
      { name: '.AspNet.Cookies', value: 'abc=def=' },
    ]);
  });

  it('忽略空段与多余空格', () => {
    expect(parseCookieInput('  a=1 ;; b=2 ; ')).toEqual([
      { name: 'a', value: '1' },
      { name: 'b', value: '2' },
    ]);
  });

  it('解析 EditThisCookie JSON 数组', () => {
    const json = JSON.stringify([
      { name: 'area', value: 'dbC' },
      { name: '.AspNet.Cookies', value: 'XYZ-1_2' },
    ]);
    expect(parseCookieInput(json)).toEqual([
      { name: 'area', value: 'dbC' },
      { name: '.AspNet.Cookies', value: 'XYZ-1_2' },
    ]);
  });

  it('兼容 JSON 里大写 Name/Value 字段', () => {
    expect(parseCookieInput(JSON.stringify([{ Name: 'a', Value: '1' }]))).toEqual([{ name: 'a', value: '1' }]);
  });

  it('同名 Cookie 后者覆盖前者', () => {
    expect(parseCookieInput('a=1; a=2')).toEqual([{ name: 'a', value: '2' }]);
  });

  it('空输入抛 ConfigError', () => {
    expect(() => parseCookieInput('   ')).toThrow(ConfigError);
  });

  it('无法解析出键值对时抛 ConfigError', () => {
    expect(() => parseCookieInput('justtext; also')).toThrow(ConfigError);
  });

  it('非法 JSON 抛 ConfigError 且信息可读', () => {
    expect(() => parseCookieInput('[{"name":')).toThrow(/Cookie JSON 解析失败/);
  });

  it('JSON 不是数组时抛 ConfigError', () => {
    expect(() => parseCookieInput('{"name":"a"}')).toThrow(/必须是数组/);
  });
});
