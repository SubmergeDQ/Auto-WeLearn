import { defineConfig } from 'tsup';

/**
 * 打包为单文件 ESM。
 * shebang 由 src/index.ts 首行提供，tsup 会保留在产物第 1 行，无需 banner。
 */
export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm'],
  target: 'node22',
  platform: 'node',
  clean: true,
  splitting: false,
  sourcemap: true,
});
