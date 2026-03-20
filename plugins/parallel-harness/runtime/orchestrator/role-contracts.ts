/**
 * parallel-harness: Role Contracts
 *
 * 四类一等角色的标准接口定义。
 * 所有方法论都必须映射到可执行 contract。
 *
 * 来源设计：
 * - BMAD-METHOD: planner/worker/verifier/synthesizer 四类角色
 *
 * 反向增强：
 * - 方法论不只是文档，必须映射到 runtime 接口
 * - 每类角色都有清晰的输入输出和失败语义
 */

import type { TaskGraph, TaskNode, ModelTier, VerificationDecision } from "./task-graph";
import type { TaskContract } from "../session/context-pack";
import type { VerificationResult } from "../verifiers/verifier-result";

// ============================================================
// Role: Planner（规划者）
// ============================================================

/** Planner 输入 */
export interface PlannerInput {
  /** 原始用户意图 */
  user_intent: string;

  /** 项目上下文 */
  project_context: {
    root_path: string;
    known_modules: string[];
    recent_changes?: string[];
  };
}

/** Planner 输出 */
export interface PlannerOutput {
  /** 状态 */
  status: "ok" | "warning" | "failed";

  /** 生成的任务图 */
  task_graph: TaskGraph;

  /** 规划摘要 */
  summary: string;

  /** 规划时间 */
  planned_at: string;
}

/** Planner 接口 */
export interface PlannerContract {
  /** 角色名 */
  role: "planner";

  /** 分析意图并生成任务图 */
  plan(input: PlannerInput): Promise<PlannerOutput>;
}

// ============================================================
// Role: Worker（执行者）
// ============================================================

/** Worker 输入 */
export interface WorkerInput {
  /** 任务契约 */
  contract: TaskContract;

  /** 分配的模型 tier */
  model_tier: ModelTier;
}

/** Worker 输出 */
export interface WorkerOutput {
  /** 状态 */
  status: "ok" | "warning" | "blocked" | "failed";

  /** 摘要 */
  summary: string;

  /** 产出文件 */
  artifacts: string[];

  /** 修改的文件路径列表 */
  modified_paths: string[];

  /** token 使用量 */
  tokens_used: number;

  /** 执行耗时（毫秒） */
  duration_ms: number;
}

/** Worker 接口 */
export interface WorkerContract {
  /** 角色名 */
  role: "worker";

  /** 执行任务 */
  execute(input: WorkerInput): Promise<WorkerOutput>;
}

// ============================================================
// Role: Verifier（验证者）
// ============================================================

/** Verifier 输入 */
export interface VerifierInput {
  /** 任务节点 */
  task: TaskNode;

  /** Worker 输出 */
  worker_output: WorkerOutput;

  /** 任务契约（用于对比验收标准） */
  contract: TaskContract;
}

/** Verifier 接口 */
export interface VerifierContract {
  /** 角色名 */
  role: "verifier";

  /** 验证 worker 输出 */
  verify(input: VerifierInput): Promise<VerificationResult>;
}

// ============================================================
// Role: Synthesizer（综合者）
// ============================================================

/** Synthesizer 输入 */
export interface SynthesizerInput {
  /** 原始任务图 */
  task_graph: TaskGraph;

  /** 所有 worker 输出 */
  worker_outputs: Map<string, WorkerOutput>;

  /** 所有验证结果 */
  verification_results: Map<string, VerificationResult>;
}

/** Synthesizer 输出 */
export interface SynthesizerOutput {
  /** 最终状态 */
  status: "completed" | "partial" | "failed";

  /** 整体摘要 */
  summary: string;

  /** 通过的任务 */
  passed_tasks: string[];

  /** 失败的任务 */
  failed_tasks: string[];

  /** 需要重试的任务 */
  retry_tasks: string[];

  /** 质量报告摘要 */
  quality_summary: string;

  /** 成本报告 */
  cost_report: {
    total_tokens: number;
    tier_distribution: Record<ModelTier, number>;
    total_retries: number;
  };
}

/** Synthesizer 接口 */
export interface SynthesizerContract {
  /** 角色名 */
  role: "synthesizer";

  /** 综合所有结果 */
  synthesize(input: SynthesizerInput): Promise<SynthesizerOutput>;
}
