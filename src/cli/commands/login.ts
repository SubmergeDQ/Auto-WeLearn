import { ConfigError } from '../../core/errors.js';
import { listCourses } from '../../core/api/course.js';
import { saveSessionJar } from '../../core/auth/session-store.js';
import { buildSession } from '../session-factory.js';
import { writeJson, writeResult, type CliContext } from '../context.js';

export interface LoginFlags {
  account?: string;
  passwordEnv?: string;
  browser?: boolean;
}

export async function loginCommand(flags: LoginFlags, ctx: CliContext): Promise<number> {
  if (flags.browser) {
    throw new ConfigError('浏览器登录（--browser）将在 M7 交付，当前请使用 --cookie');
  }
  if (flags.account || flags.passwordEnv) {
    throw new ConfigError('账号密码登录（实验性）将在 M7 交付，当前请使用 --cookie');
  }

  const { session, origin } = buildSession(ctx.config, ctx.sessionSource, ctx.logger);

  const courses = await listCourses(session, { signal: ctx.signal, logger: ctx.logger });
  const savedTo = saveSessionJar(session.jar, ctx.logger);

  if (ctx.json) {
    writeJson({ ok: true, origin, courses });
    return 0;
  }

  writeResult(`登录态有效（来源：${originLabel(origin)}），共 ${courses.length} 门课程`);
  writeResult('');
  for (const c of courses) {
    writeResult(`  cid=${c.cid.padEnd(6)} ${String(c.percent).padStart(3)}%  ${c.name}`);
  }
  writeResult('');
  writeResult(`会话已缓存：${savedTo}`);
  writeResult(`下一步：welearn-cli scan --course ${courses[0]?.cid ?? '<cid>'}`);

  return 0;
}

function originLabel(origin: string): string {
  switch (origin) {
    case 'flag':
      return '--cookie';
    case 'file':
      return '--cookie-file';
    case 'env':
      return 'WELEARN_COOKIE';
    default:
      return '本地会话缓存';
  }
}
