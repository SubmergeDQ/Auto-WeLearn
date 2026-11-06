#!/usr/bin/env node
import { runCli } from './cli/program.js';

/**
 * 进程入口：负责信号处理与退出码。
 * 命令实现只返回退出码，不自行 process.exit，便于测试直接调用。
 */

const controller = new AbortController();
let stopping = false;

function onSignal(signal: string): void {
  if (stopping) {
    process.stderr.write(`\n再次收到 ${signal}，强制退出\n`);
    process.exit(130);
  }
  stopping = true;
  process.stderr.write(`\n收到 ${signal}，正在安全停止…\n`);
  controller.abort();
  // 兜底：5 秒内没有正常退出就强杀，避免卡在不可中断的请求上
  setTimeout(() => process.exit(4), 5000).unref();
}

process.on('SIGINT', () => onSignal('SIGINT'));
process.on('SIGTERM', () => onSignal('SIGTERM'));

process.on('unhandledRejection', (reason) => {
  process.stderr.write(`未处理的 Promise 拒绝：${String(reason)}\n`);
  process.exit(1);
});

const code = await runCli(process.argv, { signal: controller.signal });
process.exit(code);
