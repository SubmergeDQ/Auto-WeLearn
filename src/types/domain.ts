/**
 * 领域模型。字段命名与 docs/NODE_CLI_SPEC.md §3 保持一致，
 * 平台返回的字段（如 isvisible / iscomplete）在 api 层归一化，不污染本层。
 */

export type Cid = string;
export type ScoId = string;

export interface Course {
  cid: Cid;
  name: string;
  /** clist[].per，0-100 的整数百分比 */
  percent: number;
}

/** 平台返回的单元原始结构（归一化后） */
export interface Unit {
  /** 0-based，来自接口数组下标，不是平台字段 */
  index: number;
  unitName: string;
  name: string;
  visible: boolean;
}

export interface Lesson {
  unitIndex: number;
  scoid: ScoId;
  location: string;
  visible: boolean;
  complete: boolean;
  /** 平台原值，形如 "00:03:49"，仅用于展示 */
  learnTime: string;
  /** 平台原值，形如 "100" / "-" / "无"，不可当数字解析 */
  crateLabel: string;
}

export type QuestionType = 'blank' | 'tof' | 'choice' | 'match' | 'order';

export interface Question {
  type: QuestionType;
  answer: string;
  /** 原始来源标记，便于调试：legacy 用 et-* 标签名，courseware 用 controltype 值 */
  tag: string;
}

export interface Interaction {
  id: string;
  type: QuestionType;
  student_response: string;
  result: 'correct' | 'wrong';
  weighting: '1';
  correct_responses?: Array<{ pattern: string }>;
}

export interface InteractionBundle {
  interactions: Interaction[];
  /** 写入 [INTERACTIONINFO] 之后的串 */
  interactionInfo: string;
}

export interface LessonStats {
  questions: number;
  oral: number;
  answered: number;
}

export type LessonStatus =
  | 'done'
  | 'partial'
  | 'failed'
  | 'skipped'
  | 'interrupted'
  | 'dry-run';

export interface LessonResult {
  scoid: ScoId;
  location: string;
  status: LessonStatus;
  crate: number;
  waitSec: number;
  heartbeats: number;
  stats: LessonStats;
  attempts: number;
  errorCode?: string;
  errorMessage?: string;
}

export type RatePlan =
  | { mode: 'fixed'; value: number }
  | { mode: 'range'; min: number; max: number };

export type WaitPlan =
  | { mode: 'fixed'; seconds: number }
  | { mode: 'range'; min: number; max: number };

export interface RunConfig {
  course: Cid;
  /** 1-based；all 表示遍历全部单元 */
  unit: 'all' | number;
  rate: RatePlan;
  wait: WaitPlan;
  concurrency: 1 | 2 | 3;
  /** 节间间隔，秒 */
  interval: { min: number; max: number };
  skipOralLesson: boolean;
  skipOralQuestion: boolean;
  dryRun: boolean;
  resume: boolean;
  statePath: string;
  maxLessons?: number;
  /**
   * cmi.total_time 的语义：session 只写本节秒数（Python 老行为），
   * total 写历史累计 + 本节（SCORM 语义，默认）。
   */
  cmiTime: 'session' | 'total';
}

export interface RunState {
  version: 1;
  updatedAt: string;
  course: { cid: Cid; name: string; uid: string; classid: string };
  lessons: Record<
    ScoId,
    {
      status: LessonStatus;
      attempts: number;
      crate?: number;
      waitSec?: number;
      finishedAt?: string;
      errorCode?: string;
    }
  >;
  stats: { done: number; partial: number; failed: number; skipped: number };
}
