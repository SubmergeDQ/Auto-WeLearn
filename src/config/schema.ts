import { z } from 'zod';

/**
 * 运行配置校验。命令行解析出的原始值先经过这里，
 * 保证下游拿到的永远是合法结构（concurrency 只可能是 1/2/3 等）。
 */

export const DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const percent = z.number().int().min(0).max(100);

export const ratePlanSchema = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('fixed'), value: percent }),
  z
    .object({ mode: z.literal('range'), min: percent, max: percent })
    .refine((v) => v.min <= v.max, { message: '正确率区间 min 不能大于 max' }),
]);

export const waitPlanSchema = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('fixed'), seconds: z.number().int().min(1).max(86_400) }),
  z
    .object({
      mode: z.literal('range'),
      min: z.number().int().min(1).max(86_400),
      max: z.number().int().min(1).max(86_400),
    })
    .refine((v) => v.min <= v.max, { message: '等待区间 min 不能大于 max' }),
]);

export const intervalSchema = z
  .object({ min: z.number().min(0).max(600), max: z.number().min(0).max(600) })
  .refine((v) => v.min <= v.max, { message: '节间间隔 min 不能大于 max' });

export const retrySchema = z.object({
  max: z.number().int().min(0).max(10).default(3),
  baseDelayMs: z.number().int().positive().max(60_000).default(2000),
});

export const runConfigSchema = z.object({
  course: z.string().min(1, { message: '缺少课程 ID' }),
  unit: z.union([z.literal('all'), z.number().int().min(1)]).default('all'),
  rate: ratePlanSchema.default({ mode: 'range', min: 90, max: 100 }),
  wait: waitPlanSchema.default({ mode: 'range', min: 300, max: 480 }),
  concurrency: z.union([z.literal(1), z.literal(2), z.literal(3)]).default(1),
  interval: intervalSchema.default({ min: 3, max: 8 }),
  skipOralLesson: z.boolean().default(true),
  skipOralQuestion: z.boolean().default(true),
  dryRun: z.boolean().default(false),
  resume: z.boolean().default(false),
  statePath: z.string().min(1).default('~/.welearn-cli/state.json'),
  maxLessons: z.number().int().positive().optional(),
  cmiTime: z.union([z.literal('session'), z.literal('total')]).default('total'),
});

export const appConfigSchema = z.object({
  baseUrl: z.string().min(1).default('https://welearn.sflep.com'),
  userAgent: z.string().min(10).default(DEFAULT_USER_AGENT),
  timeoutMs: z.number().int().positive().max(120_000).default(15_000),
  retry: retrySchema.default({ max: 3, baseDelayMs: 2000 }),
  statePath: z.string().min(1).default('~/.welearn-cli/state.json'),
});

export type AppConfig = z.infer<typeof appConfigSchema>;
export type ParsedRunConfig = z.infer<typeof runConfigSchema>;

/** 把 zod 的报错压成一行人话，避免把整个 issue 数组甩给用户 */
export function describeZodError(err: z.ZodError): string {
  return err.issues
    .map((i) => (i.path.length > 0 ? `${i.path.join('.')}: ${i.message}` : i.message))
    .join('；');
}
