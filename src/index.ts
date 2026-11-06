#!/usr/bin/env node
import { runCli } from './cli/program.js';

/**
 * 进程入口：负责信号处理与退出码。
 * 命令实现只返回退出码，不自行 process.exit，便于测试直接调用。
 *
 * 注意：这里刻意不用顶层 await —— 打包成 exe（Node SEA）时主脚本必须是
 * CommonJS，而 CommonJS 不支持 TLA，所以统一包进 main() 里。
 */

async function main(): Promise<void> {
  const controller = new AbortController();
  let stopping = false;

  const onSignal = (signal: string): void => {
    if (stopping) {
      process.stderr.write(`\n再次收到 ${signal}，强制退出\n`);
      process.exit(130);
    }
    stopping = true;
    process.stderr.write(`\n收到 ${signal}，正在安全停止…\n`);
    controller.abort();
    // 兜底：5 秒内没有正常退出就强杀，避免卡在不可中断的请求上
    setTimeout(() => process.exit(4), 5000).unref();
  };

  process.on('SIGINT', () => onSignal('SIGINT'));
  process.on('SIGTERM', () => onSignal('SIGTERM'));

  const code = await runCli(process.argv, { signal: controller.signal });
  process.exit(code);
}

process.on('unhandledRejection', (reason) => {
  process.stderr.write(`未处理的 Promise 拒绝：${String(reason)}\n`);
  process.exit(1);
});

void main();
