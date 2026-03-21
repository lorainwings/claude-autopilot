/**
 * parallel-harness: Task Graph Schema
 *
 * 任务图是整个平台的核心数据结构。
 * 所有调度、所有权分配、模型路由、验证都围绕 TaskGraph 运转。
 *
 * 来源设计：
 * - claude-task-master: 任务分解、依赖、复杂度字段
 * - oh-my-claudecode: 多 agent 调度导向（但必须 task-graph-first）
 * - BMAD-METHOD: planner/worker/verifier/synthesizer 四类角色
 *
 * 反向增强：
 * - 不能只拆任务不做 ownership 和 verifier 联动
 * - 每个任务节点必须携带完整契约
 */

// ============================================================
// 枚举定义
// ============================================================

/** 任务状态生命周期 */
export type TaskStatus =
  | "pending" // 等待依赖满足
  | "ready" // 依赖已满足，可调度
  | "dispatched" // 已派发给 worker
  | "running" // worker 正在执行
  | "completed" // 执行完成，待验证
  | "verified" // 验证通过
  | "failed" // 执行失败
  | "blocked" // 被 verifier 阻断
  | "retrying" // 重试中
  | "downgraded"; // 已降级为串行

/** 风险等级 */
export type RiskLevel = "low" | "medium" | "high" | "critical";

/** 复杂度等级 */
export type ComplexityLevel = "trivial" | "low" | "medium" | "high" | "extreme";

/** 模型 Tier（来自 claude-code-switch 增强） */
export type ModelTier = "tier-1" | "tier-2" | "tier-3";

/** 验证器类型（来自 Harness 增强） */
export type VerifierType =
  | "test"
  | "review"
  | "security"
  | "perf"
  | "coverage";

/** 验证结果判定 */
export type VerificationDecision = "pass" | "retry" | "block" | "downgrade";

// ============================================================
// 核心结构
// ============================================================

/** 任务节点 —— 任务图中的每一个可调度单元 */
export interface TaskNode {
  /** 全局唯一任务 ID */
  id: string;

  /** 任务标题（简短描述） */
  title: string;

  /** 任务目标（详细说明期望达到的效果） */
  goal: string;

  /** 依赖任务 ID 列表（DAG 边） */
  dependencies: string[];

  /** 当前状态 */
  status: TaskStatus;

  /** 风险等级 */
  risk_level: RiskLevel;

  /** 复杂度评分结果 */
  complexity: ComplexityScore;

  /** 允许修改的文件路径（glob 模式） */
  allowed_paths: string[];

  /** 禁止修改的文件路径（glob 模式） */
  forbidden_paths: string[];

  /** 验收标准 */
  acceptance_criteria: string[];

  /** 测试要求 */
  required_tests: string[];

  /** 推荐模型 Tier */
  model_tier: ModelTier;

  /** 需要哪些 verifier */
  verifier_set: VerifierType[];

  /** 重试策略 */
  retry_policy: RetryPolicy;

  /** 执行结果（完成后填充） */
  result?: TaskResult;

  /** 验证结果（验证后填充） */
  verification?: import("../verifiers/verifier-result").VerificationResult;
}

/** 复杂度评分 */
export interface ComplexityScore {
  /** 综合等级 */
  level: ComplexityLevel;

  /** 数值评分 (0-100) */
  score: number;

  /** 评分维度明细 */
  dimensions: {
    /** 涉及文件数量 */
    file_count: number;
    /** 涉及模块数量 */
    module_count: number;
    /** 是否涉及 schema/infra/critical 逻辑 */
    involves_critical: boolean;
    /** 预估 token 消耗 */
    estimated_tokens: number;
  };

  /** 评分解释 */
  reasoning: string;
}

/** 重试策略 */
export interface RetryPolicy {
  /** 最大重试次数 */
  max_retries: number;

  /** 重试时是否升级模型 tier */
  escalate_on_retry: boolean;

  /** 重试时是否压缩上下文 */
  compact_context_on_retry: boolean;
}

/** 任务执行结果 */
export interface TaskResult {
  /** 执行是否成功 */
  success: boolean;

  /** 摘要 */
  summary: string;

  /** 产出文件列表 */
  artifacts: string[];

  /** 实际使用的模型 tier */
  actual_model_tier: ModelTier;

  /** 实际 token 消耗 */
  tokens_used: number;

  /** 执行耗时（毫秒） */
  duration_ms: number;

  /** 重试次数 */
  retry_count: number;
}

/** DAG 边 */
export interface TaskEdge {
  /** 源任务 ID（前置任务） */
  from: string;

  /** 目标任务 ID（后置任务） */
  to: string;

  /** 边类型 */
  type: "dependency" | "data_flow" | "interface_contract";
}

/** 任务图元数据 */
export interface TaskGraphMetadata {
  /** 创建时间 */
  created_at: string;

  /** 原始用户意图 */
  original_intent: string;

  /** 总任务数 */
  total_tasks: number;

  /** 最大并行度 */
  max_parallelism: number;

  /** 关键路径长度 */
  critical_path_length: number;

  /** 预估总 token 消耗 */
  estimated_total_tokens: number;
}

/** 任务图 —— 平台的核心数据结构 */
export interface TaskGraph {
  /** 图唯一 ID */
  graph_id: string;

  /** 所有任务节点 */
  tasks: TaskNode[];

  /** 所有边 */
  edges: TaskEdge[];

  /** 关键路径上的任务 ID（有序） */
  critical_path: string[];

  /** 元数据 */
  metadata: TaskGraphMetadata;
}
