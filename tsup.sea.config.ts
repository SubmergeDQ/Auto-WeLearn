import { defineConfig } from 'tsup';

/**
 * 专供 Node SEA（单文件 exe）的构建配置。
 *
 * SEA 的主脚本必须是单文件 CommonJS，所以这里 format 固定 cjs；
 * 所有依赖（commander/zod/cheerio/tough-cookie）都会被打进同一个文件，
 * 生成的 exe 运行时不需要 node_modules。
 */
export default defineConfig({
  entry: { index: 'src/index.ts' },
  format: ['cjs'],
  target: 'node22',
  platform: 'node',
  outDir: 'build/sea',
  clean: true,
  splitting: false,
  sourcemap: false,
  // tsup 默认把 package.json 的 dependencies 当外部依赖（留成 require），
  // 但 exe 里没有 node_modules，必须全部内联进同一个文件
  noExternal: [/.*/],
  // CJS 里没有 import.meta，也不需要 ESM 的 __dirname 兼容层
  shims: false,
});
