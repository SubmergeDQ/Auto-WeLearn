import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { emptyState, isFinished, loadState, recordLesson, saveState } from '../src/core/state/store.js';

let dir: string;
let statePath: string;

const course = { cid: '566', name: 'Mock', uid: '123', classid: 'abc' };

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'welearn-state-'));
  statePath = join(dir, 'state.json');
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('状态读写', () => {
  it('写入后可原样读回', () => {
    const state = emptyState(course);
    recordLesson(state, 'sco-1', { status: 'done', crate: 95, waitSec: 372 });
    saveState(statePath, state);

    const loaded = loadState(statePath);
    expect(loaded?.course).toEqual(course);
    expect(loaded?.lessons['sco-1']).toMatchObject({ status: 'done', crate: 95, waitSec: 372 });
  });

  it('不存在的文件返回 null', () => {
    expect(loadState(statePath)).toBeNull();
  });

  it('写入是原子的：不留下临时文件', () => {
    saveState(statePath, emptyState(course));
    const leftovers = existsSync(join(dir, `.state.${process.pid}.tmp`));
    expect(leftovers).toBe(false);
  });

  it('损坏的文件会被备份为 .bak 并重新开始', () => {
    writeFileSync(statePath, '{ not json', 'utf8');
    const loaded = loadState(statePath, undefined);

    expect(loaded).toBeNull();
    expect(existsSync(`${statePath}.bak`)).toBe(true);
    expect(readFileSync(`${statePath}.bak`, 'utf8')).toBe('{ not json');
  });

  it('版本不匹配时同样备份并忽略', () => {
    writeFileSync(statePath, JSON.stringify({ version: 99, course, lessons: {} }), 'utf8');
    expect(loadState(statePath)).toBeNull();
    expect(existsSync(`${statePath}.bak`)).toBe(true);
  });

  it('缺少必要字段按损坏处理', () => {
    writeFileSync(statePath, JSON.stringify({ version: 1, course }), 'utf8');
    expect(loadState(statePath)).toBeNull();
  });
});

describe('统计与续跑判定', () => {
  it('recount 按状态归类', () => {
    const state = emptyState(course);
    recordLesson(state, 'a', { status: 'done' });
    recordLesson(state, 'b', { status: 'partial' });
    recordLesson(state, 'c', { status: 'failed' });
    recordLesson(state, 'd', { status: 'skipped' });
    saveState(statePath, state);

    const loaded = loadState(statePath);
    expect(loaded?.stats).toEqual({ done: 1, partial: 1, failed: 1, skipped: 1 });
  });

  it('isFinished 认为 done / partial / skipped 已处理完', () => {
    const state = emptyState(course);
    recordLesson(state, 'a', { status: 'done' });
    recordLesson(state, 'b', { status: 'partial' });
    recordLesson(state, 'c', { status: 'failed' });
    recordLesson(state, 'd', { status: 'interrupted' });

    expect(isFinished(state, 'a')).toBe(true);
    expect(isFinished(state, 'b')).toBe(true);
    expect(isFinished(state, 'c')).toBe(false);
    expect(isFinished(state, 'd')).toBe(false);
    expect(isFinished(state, 'unknown')).toBe(false);
  });

  it('同一小节重复记录时累加 attempts', () => {
    const state = emptyState(course);
    recordLesson(state, 'a', { status: 'failed' });
    recordLesson(state, 'a', { status: 'done' });

    expect(state.lessons['a']?.attempts).toBe(2);
    expect(state.lessons['a']?.status).toBe('done');
  });

  it('saveState 会刷新 updatedAt', () => {
    const state = emptyState(course);
    state.updatedAt = '2000-01-01T00:00:00.000Z';
    saveState(statePath, state);
    expect(state.updatedAt).not.toBe('2000-01-01T00:00:00.000Z');
  });
});
