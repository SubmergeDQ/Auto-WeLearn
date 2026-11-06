import { existsSync, readFileSync } from 'node:fs';
import { appConfigSchema, describeZodError, type AppConfig } from './schema.js';
import { ConfigError } from '../core/errors.js';

/**
 * 配置装载：内置默认值 → config.json（可选）→ 环境变量（覆盖）。
 * 命令行参数在各自命令里再覆盖运行期字段。
 *
 * 安全约束：配置文件里不允许出现 cookie / password，这里也不读取它们。
 */
export interface LoadConfigOptions {
  env?: NodeJS.ProcessEnv;
  filePath?: string;
}

export function loadConfig(opts: LoadConfigOptions = {}): AppConfig {
  const env = opts.env ?? process.env;

  let fromFile: Record<string, unknown> = {};
  if (opts.filePath && existsSync(opts.filePath)) {
    try {
      fromFile = JSON.parse(readFileSync(opts.filePath, 'utf8')) as Record<string, unknown>;
    } catch (err) {
      throw new ConfigError(`配置文件解析失败：${(err as Error).message}`);
    }
  }

  const merged: Record<string, unknown> = {
    ...fromFile,
    ...(env.WELEARN_BASE_URL ? { baseUrl: env.WELEARN_BASE_URL } : {}),
    ...(env.WELEARN_STATE_PATH ? { statePath: env.WELEARN_STATE_PATH } : {}),
    ...(env.WELEARN_TIMEOUT_MS ? { timeoutMs: Number(env.WELEARN_TIMEOUT_MS) } : {}),
  };

  const parsed = appConfigSchema.safeParse(merged);
  if (!parsed.success) {
    throw new ConfigError(`配置不合法：${describeZodError(parsed.error)}`);
  }
  return parsed.data;
}
