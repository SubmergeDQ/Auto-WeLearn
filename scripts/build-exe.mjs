#!/usr/bin/env node
/**
 * 把 CLI 打包成单文件可执行程序（Node SEA）。
 *
 * 为什么不用 pkg/nexe：Node 22 自带 SEA（Single Executable Application），
 * 官方维护、无需第三方打包器的运行时兼容层。
 *
 * 产物：dist/welearn-cli[.exe] —— 内嵌 Node 运行时 + 所有依赖，
 * 目标机器不需要安装 Node，也不带 node_modules。
 */
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const isWin = process.platform === 'win32';
const exeName = isWin ? 'welearn-cli.exe' : 'welearn-cli';
// 刻意不放 dist/：tsup 的 clean 会在每次 npm run build 时清空 dist，把 exe 删掉
const outExe = join(root, 'release', exeName);
const seaBlob = join(root, 'build', 'sea', 'sea-prep.blob');

const run = (cmd, args, opts = {}) =>
  execFileSync(cmd, args, { stdio: 'inherit', cwd: root, shell: isWin, ...opts });

console.log('[1/4] 构建 CJS 单文件（SEA 只接受 CommonJS 主脚本）');
run('npx', ['tsup', '--config', 'tsup.sea.config.ts']);

console.log('[2/4] 生成 SEA blob');
mkdirSync(dirname(seaBlob), { recursive: true });
run(process.execPath, ['--experimental-sea-config', 'sea-config.json']);

console.log('[3/4] 复制 Node 运行时');
mkdirSync(dirname(outExe), { recursive: true });
copyFileSync(process.execPath, outExe);

console.log('[4/4] 注入 blob');
run('npx', [
  'postject',
  outExe,
  'NODE_SEA_BLOB',
  seaBlob,
  '--sentinel-fuse',
  'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2',
]);

const mb = (statSync(outExe).size / 1024 / 1024).toFixed(1);
console.log(`\n完成：${outExe}（${mb} MB）`);
console.log('试运行：' + (isWin ? 'release\\welearn-cli.exe --help' : './release/welearn-cli --help'));
