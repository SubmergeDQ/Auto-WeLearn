import { homedir } from 'node:os';
import { join } from 'node:path';

/** `~/.welearn-cli/state.json` → 绝对路径，Windows 下也能正确展开 */
export function expandHome(p: string): string {
  if (p === '~') return homedir();
  if (p.startsWith('~/') || p.startsWith('~\\')) return join(homedir(), p.slice(2));
  return p;
}

export const APP_DIR = (): string => join(homedir(), '.welearn-cli');

export const DEFAULT_STATE_PATH = '~/.welearn-cli/state.json';
export const SESSION_PATH = '~/.welearn-cli/session.json';
