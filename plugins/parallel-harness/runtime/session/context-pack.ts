/**
 * parallel-harness: Context Pack Schema
 *
 * 每个 worker 只接收最小必要上下文，而不是整个仓库或整段对话历史。
 *
 * 来源设计：
 * - get-shit-done: 最小上下文包、低摩擦推进
 * - superpowers: 能力清单化、低摩擦入口
 *
 * 反向增强：
 * - 不能只追求快，还要加 verifier 和 metrics
 * - 上下文超预算时自动摘要，而不是截断
 */

import type { ModelTier, RetryPolicy, VerifierType } from "../orchestrator/task-graph";

// ============================================================
// 上下文包
// ============================================================

/** 代码片段 */
export interface CodeSnippet {
  /** 文件路径 */
  file_path: string;

  /** 起始行 */
  start_line: number;

  /** 结束行 */
  end_line: number;

  /** 代码内容 */
  content: string;

  /** 为什么这段代码与任务相关 */
  relevance: string;
}

/** 上下文包 —— Worker 收到的全部信息 */
export interface ContextPack {
  /** 任务摘要（目标 + 验收标准） */
  task_summary: string;

  /** 相关文件路径列表 */
  relevant_files: string[];

  /** 精选代码片段 */
  relevant_snippets: CodeSnippet[];

  /** 约束条件 */
  constraints: ContextConstraints;

  /** 测试要求 */
  test_requirements: string[];

  /** Token 预算 */
  budget: ContextBudget;

  /** 上下文占用率 (0-1) */
  occupancy_ratio: number;

  /** 加载的文件数量 */
  loaded_files_count: number;

  /** 加载的代码片段数量 */
  loaded_snippets_count: number;

  /** 压缩策略 */
  compaction_policy: "none" | "summarize" | "truncate";

  /** 重试提示：非零时表示第 N 次重试，上下文应有所不同 */
  retry_hint?: number;
}

/** 约束条件 */
export interface ContextConstraints {
  /** 允许修改的路径 */
  allowed_paths: string[];

  /** 禁止修改的路径 */
  forbidden_paths: string[];

  /** 接口契约（其他任务期望本任务的输出满足的约定） */
  interface_contracts: string[];

  /** 必须遵守的编码规范 */
  coding_standards: string[];
}

/** Token 预算 */
export interface ContextBudget {
  /** 最大输入 token 数 */
  max_input_tokens: number;

  /** 最大输出 token 数 */
  max_output_tokens: number;

  /** 超预算时是否自动摘要 */
  auto_summarize_on_overflow: boolean;

  /** Occupancy 阈值 (0-1)，超过时提前触发 compaction */
  occupancy_threshold?: number;

  /** 角色类型，影响上下文优先级排序 */
  role?: "planner" | "author" | "verifier";
}

// ============================================================
// 任务契约（Worker 的完整输入）
// ============================================================

/** 任务契约 —— Worker 执行任务的完整合同 */
export interface TaskContract {
  /** 任务 ID */
  task_id: string;

  /** 任务目标 */
  goal: string;

  /** 依赖任务 ID 列表 */
  dependencies: string[];

  /** 文件所有权 */
  allowed_paths: string[];

  /** 禁止路径 */
  forbidden_paths: string[];

  /** 验收标准 */
  acceptance_criteria: string[];

  /** 测试要求 */
  test_requirements: string[];

  /** 推荐模型 tier */
  preferred_model_tier: ModelTier;

  /** 重试策略 */
  retry_policy: RetryPolicy;

  /** 需要的验证器 */
  verifier_set: VerifierType[];

  /** 上下文包 */
  context: ContextPack;

  /** 来自 Requirement Grounding 的验收矩阵条目 */
  grounding_criteria?: Array<{
    category: string;
    criterion: string;
    blocking: boolean;
  }>;

  /** 来自 Requirement Grounding 的必要审批 */
  required_approvals?: string[];
}

// ============================================================
// P2-2: ContextEnvelope V2
// ============================================================

/** 证据引用（V2） */
export interface EvidenceRef {
  ref_id: string;
  kind: "file" | "snippet" | "symbol" | "artifact" | "test" | "policy";
  rationale: string;
  priority: number;
}

/** 依赖输出引用 */
export interface DependencyOutput {
  task_id: string;
  artifact_ref: string;
  summary?: string;
}

/** V2 压缩策略 */
export type CompactionPolicyV2 = "none" | "retrieve_only" | "symbol_only" | "summary";

/** 上下文信封 V2 — symbol-aware, dependency-aware, role-aware, retry-aware */
export interface ContextEnvelopeV2 {
  task_id: string;
  /** 角色感知：不同角色看到不同上下文 */
  role: "planner" | "author" | "verifier" | "reporter";
  /** 证据引用（按优先级排序） */
  evidence_refs: EvidenceRef[];
  /** 依赖任务的输出 */
  dependency_outputs: DependencyOutput[];
  /** Token 预算 */
  budget: {
    max_input_tokens: number;
    max_output_tokens: number;
  };
  /** 上下文占用率 */
  occupancy_ratio: number;
  /** 压缩策略 V2 */
  compaction_policy: CompactionPolicyV2;
  /** 符号索引 — symbol-aware */
  symbol_index?: Array<{
    symbol_name: string;
    symbol_type: "function" | "class" | "interface" | "type" | "variable" | "module";
    file_path: string;
    line: number;
  }>;
  /** 重试上下文 — retry-aware */
  retry_context?: {
    attempt_number: number;
    previous_failure_reason?: string;
    excluded_approaches?: string[];
  };
}

/** 从 ContextPack 升级到 ContextEnvelopeV2 */
export function upgradeToEnvelopeV2(
  pack: ContextPack,
  taskId: string,
  role: ContextEnvelopeV2["role"],
  dependencyOutputs?: DependencyOutput[],
  retryContext?: ContextEnvelopeV2["retry_context"]
): ContextEnvelopeV2 {
  return {
    task_id: taskId,
    role,
    evidence_refs: pack.relevant_files.map((f, i) => ({
      ref_id: `ev_${i}`,
      kind: "file" as const,
      rationale: `在任务 ${taskId} 的所有权范围内`,
      priority: pack.relevant_files.length - i,
    })),
    dependency_outputs: dependencyOutputs || [],
    budget: {
      max_input_tokens: pack.budget.max_input_tokens,
      max_output_tokens: pack.budget.max_output_tokens,
    },
    occupancy_ratio: pack.occupancy_ratio,
    compaction_policy: mapCompactionPolicy(pack.compaction_policy),
    retry_context: retryContext || (pack.retry_hint ? {
      attempt_number: pack.retry_hint,
    } : undefined),
  };
}

function mapCompactionPolicy(policy: ContextPack["compaction_policy"]): CompactionPolicyV2 {
  switch (policy) {
    case "none": return "none";
    case "summarize": return "summary";
    case "truncate": return "retrieve_only";
    default: return "none";
  }
}
