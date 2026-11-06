import { Command, CommanderError } from 'commander';
import { loadConfig } from '../config/load.js';
import { exitCodeFor, toAppError } from '../core/errors.js';
import { createLogger } from '../logging/logger.js';
import { createContext, type CliContext } from './context.js';
import { loginCommand, type LoginFlags } from './commands/login.js';
import { scanCommand, type ScanFlags } from './commands/scan.js';
import { inspectCommand, type InspectFlags } from './commands/inspect.js';
import { runCommand, type RunFlags } from './commands/run.js';

const DISCLAIMER = `仅用于个人学习研究与接口自动化练习。
使用前请自行确认符合所在学校与平台的服务条款，后果自负。
本工具不包含验证码识别、设备指纹伪造、代理池或其它风控规避功能。`;

export async function runCli(argv: string[], opts: { signal: AbortSignal }): Promise<number> {
  const program = new Command();
  program
    .name('welearn-cli')
    .description(`WE Learn 命令行工具\n\n${DISCLAIMER}`)
    .version('0.1.0', '-V, --version')
    .option('-v, --verbose', '输出调试日志')
    .option('--json', '结果以 JSON 输出到 stdout')
    .option('--cookie <string>', 'Cookie 字符串，或 EditThisCookie 导出的 JSON 数组')
    .option('--cookie-file <path>', '从文件读取 Cookie')
    .showHelpAfterError('（使用 --help 查看用法）');

  let exitCode = 0;

  program
    .command('login')
    .description('校验登录态并列出课程')
    .option('--account <account>', '账号（实验性，M7 交付）')
    .option('--password-env <var>', '存放密码的环境变量名（实验性，M7 交付）')
    .option('--browser', '用本机浏览器登录并取 Cookie（M7 交付）')
    .action(async (localOpts: Record<string, unknown>, cmd: Command) => {
      exitCode = await loginCommand(localOpts as unknown as LoginFlags, buildContext(cmd, opts.signal));
    });

  program
    .command('scan')
    .description('扫描课程结构与完成进度，输出待处理队列')
    .requiredOption('--course <cid>', '课程 ID（来自 login 输出）')
    .option('--unit <n|all>', '只扫描指定单元（1-based），默认 all', 'all')
    .action(async (localOpts: Record<string, unknown>, cmd: Command) => {
      exitCode = await scanCommand(localOpts as unknown as ScanFlags, buildContext(cmd, opts.signal));
    });

  program
    .command('inspect')
    .description('只读解析某个小节的题目与答案（不发任何写请求）')
    .requiredOption('--course <cid>', '课程 ID')
    .requiredOption('--sco <scoid>', '小节 ID')
    .action(async (localOpts: Record<string, unknown>, cmd: Command) => {
      exitCode = await inspectCommand(localOpts as unknown as InspectFlags, buildContext(cmd, opts.signal));
    });

  program
    .command('run')
    .description('按队列执行学习流程（批次 B 起支持真实提交，当前仅 --dry-run）')
    .requiredOption('--course <cid>', '课程 ID')
    .option('--unit <n|all>', '只处理指定单元（1-based）', 'all')
    .option('--rate <n|a-b>', '目标正确率，如 93 或 90-100', '90-100')
    .option('--wait <n|a-b>', '每节等待秒数，如 60 或 300-480', '300-480')
    .option('--interval <a-b>', '节间间隔秒数', '3-8')
    .option('--concurrency <n>', '并发数，仅允许 1/2/3', '1')
    .option('--no-skip-oral', '不跳过整节口语任务（默认跳过）')
    .option('--keep-oral-questions', '口语类题目也尝试提交（默认跳过）')
    .option('--dry-run', '只扫描与解析，不发任何写请求', false)
    .option('--resume', '断点续跑，跳过已完成小节', false)
    .option('--state <path>', '状态文件路径')
    .option('--max-lessons <n>', '本次最多处理节数')
    .option('--unsafe-fast', '允许低于 30s 的等待（仅测试用）', false)
    .action(async (localOpts: Record<string, unknown>, cmd: Command) => {
      exitCode = await runCommand(localOpts as unknown as RunFlags, buildContext(cmd, opts.signal));
    });

  program.exitOverride();
  program.configureOutput({
    writeErr: (text) => process.stderr.write(text),
    outputError: (text, write) => write(text),
  });

  try {
    await program.parseAsync(argv);
    return exitCode;
  } catch (raw) {
    if (raw instanceof CommanderError) {
      if (raw.code === 'commander.helpDisplayed' || raw.code === 'commander.version') return 0;
      return raw.exitCode === 0 ? 0 : 2;
    }

    const err = toAppError(raw);
    const verbose = argv.some((a) => a === '-v' || a === '--verbose');
    const logger = createLogger({ level: verbose ? 'debug' : 'info' });
    logger.error(`${err.code}: ${err.message}`);
    if (err.cause && verbose) logger.debug(String(err.cause));
    return exitCodeFor(err, false);
  }
}

interface Globals {
  verbose?: boolean;
  json?: boolean;
  cookie?: string;
  cookieFile?: string;
}

function buildContext(cmd: Command, signal: AbortSignal): CliContext {
  const globals = cmd.optsWithGlobals<Globals>();
  return createContext({
    signal,
    json: Boolean(globals.json),
    verbose: Boolean(globals.verbose),
    config: loadConfig(),
    sessionSource: { cookie: globals.cookie, cookieFile: globals.cookieFile },
  });
}
