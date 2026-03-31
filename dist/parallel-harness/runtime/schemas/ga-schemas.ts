/**
 * parallel-harness: GA-Level Schema Contracts
 *
 * 商业化 GA 级别的数据契约。所有 runtime 模块共享这些 schema。
 * 包含版本字段、migration 策略、持久化支持。
 *
 * Schema 版本: 1.0.0
 */

import type {
  TaskGraph,
  TaskNode,
  ModelTier,
  VerifierType,
  VerificationDecision,
  RiskLevel,
} from "../orchestrator/task-graph";
import type { VerificationResult } from "../verifiers/verifier-result";

// ============================================================
// Schema 版本控制
// ============================================================

export const SCHEMA_VERSION = "1.0.0";

export interface Versioned {
  /** Schema 版本 */
  schema_version: string;
}

// ============================================================
// 统一 ID 体系
// ============================================================

/** 生成唯一 ID */
export function generateId(prefix: string): string {
  const ts = Date.now().toString(36);
  const rand = Math.random().toString(36).substring(2, 8);
  return `${prefix}_${ts}_${rand}`;
}

// ============================================================
// Run Schema — 顶层执行单元
// ============================================================

/** Run 状态机 */
export type RunStatus =
  | "pending"           // 等待启动
  | "planned"           // 规划完成
  | "awaiting_approval" // 等待审批
  | "scheduled"         // 已调度
  | "running"           // 执行中
  | "verifying"         // 验证中
  | "blocked"           // 被阻断
  | "failed"            // 执行失败
  | "partially_failed"  // 部分失败
  | "succeeded"         // 全部成功
  | "cancelled"         // 已取消
  | "archived";         // 已归档

/** Run 请求 */
export interface RunRequest extends Versioned {
  /** 请求 ID */
  request_id: string;

  /** 原始用户意图 */
  intent: string;

  /** 触发者 */
  actor: ActorIdentity;

  /** 项目上下文 */
  project: ProjectContext;

  /** 执行配置 */
  config: RunConfig;

  /** 请求时间 */
  requested_at: string;
}

/** Run 规划 */
export interface RunPlan extends Versioned {
  /** 规划 ID */
  plan_id: string;

  /** 关联的 Run ID */
  run_id: string;

  /** 任务图 */
  task_graph: TaskGraph;

  /** 所有权规划 */
  ownership_plan: import("../orchestrator/ownership-planner").OwnershipPlan;

  /** 调度计划 */
  schedule_plan: import("../scheduler/scheduler").SchedulePlan;

  /** 模型路由方案 */
  routing_decisions: RoutingDecision[];

  /** 预算估算 */
  budget_estimate: BudgetEstimate;

  /** 需要审批的动作 */
  pending_approvals: ApprovalRequest[];

  /** 需求契约 (Requirement Grounding) */
  requirement_grounding?: import("../orchestrator/requirement-grounding").RequirementGrounding;

  /** 阶段合同 (Stage Contracts) */
  stage_contracts?: import("../orchestrator/requirement-grounding").StageContract[];

  /** 规划时间 */
  planned_at: string;
}

/** Run 执行状态 */
export interface RunExecution extends Versioned {
  /** Run ID */
  run_id: string;

  /** Batch ID */
  batch_id: string;

  /** 当前状态 */
  status: RunStatus;

  /** 状态历史 */
  status_history: StatusTransition[];

  /** 活跃的 task attempts */
  active_attempts: Record<string, TaskAttempt>;

  /** 已完成的 task attempts */
  completed_attempts: Record<string, TaskAttempt[]>;

  /** verifier 结果 */
  verification_results: Record<string, VerificationResult>;

  /** 审批记录 */
  approval_records: ApprovalRecord[];

  /** 策略违规 */
  policy_violations: PolicyViolation[];

  /** 成本账本 */
  cost_ledger: CostLedger;

  /** 开始时间 */
  started_at: string;

  /** 最后更新时间 */
  updated_at: string;
}

/** Run 结果 */
export interface RunResult extends Versioned {
  /** Run ID */
  run_id: string;

  /** 最终状态 */
  final_status: RunStatus;

  /** 完成的任务 */
  completed_tasks: string[];

  /** 失败的任务 */
  failed_tasks: FailedTaskSummary[];

  /** 跳过的任务 */
  skipped_tasks: string[];

  /** 综合质量报告 */
  quality_report: RunQualityReport;

  /** 成本汇总 */
  cost_summary: CostSummary;

  /** 审计摘要 */
  audit_summary: AuditSummary;

  /** PR 产出 (如有) */
  pr_artifacts?: PRArtefacts;

  /** 完成时间 */
  completed_at: string;

  /** 总耗时 (ms) */
  total_duration_ms: number;
}

// ============================================================
// Task Attempt Schema — Worker 执行尝试
// ============================================================

/** Task Attempt 状态 */
export type AttemptStatus =
  | "pending"
  | "pre_check"    // 执行前校验 (ownership/policy/budget/approval)
  | "executing"
  | "post_check"   // 执行后校验
  | "succeeded"
  | "failed"
  | "cancelled"
  | "timed_out";

/** 单次 Worker 执行尝试 */
export interface TaskAttempt extends Versioned {
  /** Attempt ID */
  attempt_id: string;

  /** 关联 Run ID */
  run_id: string;

  /** 关联 Task ID */
  task_id: string;

  /** 尝试序号 (从 1 开始) */
  attempt_number: number;

  /** 状态 */
  status: AttemptStatus;

  /** 状态历史 */
  status_history: StatusTransition[];

  /** 使用的模型 tier */
  model_tier: ModelTier;

  /** 输入摘要 (不含完整上下文，用于审计) */
  input_summary: string;

  /** 输出摘要 */
  output_summary: string;

  /** 修改的文件 */
  modified_files: string[];

  /** 产出物 */
  artifacts: string[];

  /** Token 使用量 */
  tokens_used: number;

  /** 成本 (相对值) */
  cost: number;

  /** 失败分类 (如果失败) */
  failure_class?: FailureClass;

  /** 失败详情 */
  failure_detail?: string;

  /** 执行前检查结果 */
  pre_checks: PreCheckResult[];

  /** 开始时间 */
  started_at: string;

  /** 结束时间 */
  ended_at?: string;

  /** 耗时 (ms) */
  duration_ms?: number;
}

// ============================================================
// 失败分类体系
// ============================================================

/** 失败分类枚举 */
export type FailureClass =
  | "transient_tool_failure"       // 工具临时故障，可重试
  | "permanent_policy_failure"     // 策略永久拒绝，不可重试
  | "ownership_conflict"           // 所有权冲突
  | "budget_exhausted"             // 预算耗尽
  | "approval_denied"              // 审批被拒
  | "verification_failed"          // 验证失败
  | "network_restricted"           // 网络受限
  | "unsupported_capability"       // 能力不支持
  | "human_intervention_required"  // 需要人工介入
  | "timeout"                      // 超时
  | "unknown";                     // 未知错误

/** 失败分类 → 推荐动作映射 */
export const FAILURE_ACTION_MAP: Record<FailureClass, FailureAction> = {
  transient_tool_failure:      { retry: true, escalate: false, downgrade: false, human: false },
  permanent_policy_failure:    { retry: false, escalate: false, downgrade: false, human: true },
  ownership_conflict:          { retry: false, escalate: false, downgrade: true, human: false },
  budget_exhausted:            { retry: false, escalate: false, downgrade: true, human: true },
  approval_denied:             { retry: false, escalate: false, downgrade: false, human: true },
  verification_failed:         { retry: true, escalate: true, downgrade: false, human: false },
  network_restricted:          { retry: false, escalate: false, downgrade: false, human: true },
  unsupported_capability:      { retry: false, escalate: true, downgrade: false, human: false },
  human_intervention_required: { retry: false, escalate: false, downgrade: false, human: true },
  timeout:                     { retry: true, escalate: true, downgrade: false, human: false },
  unknown:                     { retry: true, escalate: false, downgrade: false, human: true },
};

export interface FailureAction {
  retry: boolean;
  escalate: boolean;
  downgrade: boolean;
  human: boolean;
}

// ============================================================
// Status Transition — 状态迁移追踪
// ============================================================

export interface StatusTransition {
  from: string;
  to: string;
  reason: string;
  timestamp: string;
  actor?: string;
}

// ============================================================
// Pre-Check Result
// ============================================================

export interface PreCheckResult {
  check_type: "ownership" | "policy" | "budget" | "approval" | "capability";
  passed: boolean;
  message: string;
  details?: Record<string, unknown>;
}

// ============================================================
// Policy Schema
// ============================================================

/** Policy 规则 */
export interface PolicyRule {
  /** 规则 ID */
  rule_id: string;

  /** 规则名称 */
  name: string;

  /** 规则类别 */
  category: PolicyCategory;

  /** 条件表达式 (JSON) */
  condition: PolicyCondition;

  /** 违规时动作 */
  enforcement: PolicyEnforcement;

  /** 是否启用 */
  enabled: boolean;

  /** 优先级 (越小越高) */
  priority: number;
}

export type PolicyCategory =
  | "path_boundary"          // 路径边界
  | "model_tier_limit"       // 模型等级上限
  | "network_access"         // 网络访问
  | "sensitive_directory"    // 敏感目录
  | "approval_required"      // 需要审批的动作
  | "max_concurrency"        // 最大并行度
  | "budget_limit"           // 预算上限
  | "tool_restriction"       // 工具限制
  | "data_classification";   // 数据分类

export interface PolicyCondition {
  /** 条件类型 */
  type: "path_match" | "budget_threshold" | "risk_level" | "model_tier" | "action_type" | "always";

  /** 条件参数 */
  params: Record<string, unknown>;
}

export type PolicyEnforcement =
  | "block"     // 阻断
  | "warn"      // 警告但允许
  | "approve"   // 需要审批
  | "log";      // 仅记录

/** Policy 决策记录 */
export interface PolicyDecision extends Versioned {
  /** 决策 ID */
  decision_id: string;

  /** Run ID */
  run_id: string;

  /** Task ID */
  task_id?: string;

  /** 匹配的规则 */
  matched_rules: PolicyRule[];

  /** 最终执行动作 */
  enforcement: PolicyEnforcement;

  /** 决策原因 */
  reasoning: string;

  /** 时间戳 */
  decided_at: string;
}

/** Policy 违规 */
export interface PolicyViolation {
  /** 违规 ID */
  violation_id: string;

  /** 关联规则 */
  rule_id: string;

  /** 关联任务 */
  task_id: string;

  /** 违规类型 */
  category: PolicyCategory;

  /** 严重程度 */
  severity: "info" | "warning" | "error" | "critical";

  /** 描述 */
  message: string;

  /** 被阻断还是放行 */
  blocked: boolean;

  /** 时间戳 */
  occurred_at: string;
}

// ============================================================
// Approval Schema
// ============================================================

export interface ApprovalRequest {
  /** 审批请求 ID */
  approval_id: string;

  /** 关联 Run */
  run_id: string;

  /** 关联 Task (可选) */
  task_id?: string;

  /** 审批动作描述 */
  action: string;

  /** 审批原因 */
  reason: string;

  /** 触发的策略规则 */
  triggered_rules: string[];

  /** 状态 */
  status: "pending" | "approved" | "denied" | "expired";

  /** 请求时间 */
  requested_at: string;

  /** 决策时间 */
  decided_at?: string;

  /** 审批者 */
  decided_by?: string;

  /** 审批意见 */
  comment?: string;
}

export interface ApprovalRecord extends ApprovalRequest {
  /** 决策结果 */
  decision: "approved" | "denied" | "expired";
}

// ============================================================
// Audit Event Schema
// ============================================================

export type AuditEventType =
  | "run_created"
  | "run_planned"
  | "run_started"
  | "run_completed"
  | "run_failed"
  | "run_cancelled"
  | "task_dispatched"
  | "task_completed"
  | "task_failed"
  | "task_retried"
  | "worker_started"
  | "worker_completed"
  | "worker_failed"
  | "model_routed"
  | "model_escalated"
  | "model_downgraded"
  | "verification_started"
  | "verification_passed"
  | "verification_blocked"
  | "policy_evaluated"
  | "policy_violated"
  | "approval_requested"
  | "approval_decided"
  | "ownership_checked"
  | "ownership_violated"
  | "budget_consumed"
  | "budget_exceeded"
  | "gate_passed"
  | "gate_blocked"
  | "pr_created"
  | "pr_reviewed"
  | "pr_merged"
  | "human_feedback"
  | "config_changed";

export interface AuditEvent extends Versioned {
  /** 事件 ID */
  event_id: string;

  /** 事件类型 */
  type: AuditEventType;

  /** 时间戳 */
  timestamp: string;

  /** 触发者 */
  actor: ActorIdentity;

  /** 关联 Run */
  run_id?: string;

  /** 关联 Task */
  task_id?: string;

  /** 关联 Attempt */
  attempt_id?: string;

  /** 事件载荷 */
  payload: Record<string, unknown>;

  /** 影响范围 */
  scope: ScopeContext;
}

// ============================================================
// Cost Ledger Schema
// ============================================================

export interface CostLedger extends Versioned {
  /** Run ID */
  run_id: string;

  /** 条目列表 */
  entries: CostEntry[];

  /** 当前总成本 */
  total_cost: number;

  /** 预算上限 */
  budget_limit: number;

  /** 剩余预算 */
  remaining_budget: number;

  /** Tier 分布 */
  tier_distribution: Record<ModelTier, { tokens: number; cost: number; count: number }>;
}

export interface CostEntry {
  /** 条目 ID */
  entry_id: string;

  /** 关联 Task */
  task_id: string;

  /** 关联 Attempt */
  attempt_id: string;

  /** 模型 Tier */
  model_tier: ModelTier;

  /** Token 使用量 */
  tokens_used: number;

  /** 成本 */
  cost: number;

  /** 时间戳 */
  recorded_at: string;
}

export interface CostSummary {
  total_tokens: number;
  total_cost: number;
  tier_distribution: Record<ModelTier, number>;
  total_retries: number;
  budget_utilization: number; // 0-1
}

// ============================================================
// Routing Decision Schema
// ============================================================

export interface RoutingDecision extends Versioned {
  /** 决策 ID */
  decision_id: string;

  /** 关联 Task */
  task_id: string;

  /** 阶段 */
  phase: "planner" | "worker" | "review" | "security" | "summary";

  /** 推荐 Tier */
  recommended_tier: ModelTier;

  /** 路由原因 */
  reasoning: string;

  /** 路由输入 */
  inputs: {
    complexity: string;
    risk: string;
    retry_count: number;
    budget_remaining: number;
    org_policy_max_tier?: ModelTier;
    sensitivity?: string;
    slo_level?: string;
  };

  /** 时间戳 */
  decided_at: string;
}

// ============================================================
// Actor / Scope / Project Context
// ============================================================

export interface ActorIdentity {
  /** Actor ID */
  id: string;

  /** Actor 类型 */
  type: "user" | "bot" | "system" | "ci";

  /** 显示名 */
  name: string;

  /** 角色 */
  roles: string[];
}

export interface ScopeContext {
  /** 组织 */
  org?: string;

  /** 项目 */
  project?: string;

  /** 仓库 */
  repo?: string;

  /** 环境 */
  environment?: string;
}

export interface ProjectContext {
  /** 仓库根路径 */
  root_path: string;

  /** 已知模块 */
  known_modules: string[];

  /** 最近改动 */
  recent_changes?: string[];

  /** 作用域 */
  scope: ScopeContext;
}

// ============================================================
// Run Config
// ============================================================

export interface RunConfig {
  /** 最大并发 */
  max_concurrency: number;

  /** 高风险最大并发 */
  high_risk_max_concurrency: number;

  /** 优先关键路径 */
  prioritize_critical_path: boolean;

  /** 预算上限 (相对值) */
  budget_limit: number;

  /** 默认最高 Tier */
  max_model_tier: ModelTier;

  /** 启用的 gate 类型 */
  enabled_gates: GateType[];

  /** 自动审批规则 */
  auto_approve_rules: string[];

  /** 超时 (ms) */
  timeout_ms: number;

  /** PR 策略 */
  pr_strategy: "none" | "single_pr" | "stacked_pr";

  /** 是否启用 autofix */
  enable_autofix: boolean;

  /** 执行沙箱模式 */
  execution_sandbox_mode?: "none" | "path_check" | "worktree";
}

export const DEFAULT_RUN_CONFIG: RunConfig = {
  max_concurrency: 5,
  high_risk_max_concurrency: 2,
  prioritize_critical_path: true,
  budget_limit: 100000,
  max_model_tier: "tier-3",
  enabled_gates: ["test", "lint_type", "review", "policy"],
  auto_approve_rules: [],
  timeout_ms: 600000,
  pr_strategy: "single_pr",
  enable_autofix: false,
};

// ============================================================
// Gate System Schema
// ============================================================

export type GateType =
  | "test"
  | "lint_type"
  | "review"
  | "security"
  | "perf"
  | "coverage"
  | "policy"
  | "documentation"
  | "release_readiness";

export type GateLevel =
  | "task"    // 单个任务级别
  | "run"     // Run 级别
  | "pr";     // PR 级别

export interface GateResult extends Versioned {
  /** Gate ID */
  gate_id: string;

  /** Gate 类型 */
  gate_type: GateType;

  /** Gate 级别 */
  gate_level: GateLevel;

  /** 关联 Run */
  run_id: string;

  /** 关联 Task (task-level) */
  task_id?: string;

  /** 是否通过 */
  passed: boolean;

  /** 阻断级别 */
  blocking: boolean;

  /** 结论 */
  conclusion: GateConclusion;

  /** 时间戳 */
  evaluated_at: string;
}

export interface GateConclusion {
  /** 摘要 */
  summary: string;

  /** 发现列表 */
  findings: GateFinding[];

  /** 风险评估 */
  risk: RiskLevel;

  /** 必须修复项 */
  required_actions: string[];

  /** 建议修复补丁 */
  suggested_patches: SuggestedPatch[];
}

export interface GateFinding {
  severity: "info" | "warning" | "error" | "critical";
  message: string;
  file_path?: string;
  line?: number;
  rule_id?: string;
  suggestion?: string;
}

export interface SuggestedPatch {
  file_path: string;
  description: string;
  diff?: string;
}

// ============================================================
// Quality Report
// ============================================================

export interface RunQualityReport {
  overall_grade: "A" | "B" | "C" | "D" | "F";
  gate_results: GateResult[];
  pass_rate: number;
  findings_count: { info: number; warning: number; error: number; critical: number };
  recommendations: string[];
}

// ============================================================
// Audit Summary
// ============================================================

export interface AuditSummary {
  total_events: number;
  key_decisions: string[];
  policy_violations_count: number;
  approvals_count: number;
  human_interventions: number;
  model_escalations: number;
}

// ============================================================
// PR Artefacts
// ============================================================

export interface PRArtefacts {
  pr_url?: string;
  pr_number?: number;
  branch_name: string;
  summary: string;
  walkthrough: string;
  review_comments: PRReviewComment[];
  checks_status: Record<string, "pass" | "fail" | "pending">;
}

export interface PRReviewComment {
  file_path: string;
  line: number;
  body: string;
  severity: "info" | "warning" | "error";
}

// ============================================================
// Budget Estimate
// ============================================================

export interface BudgetEstimate {
  estimated_total_tokens: number;
  estimated_total_cost: number;
  budget_limit: number;
  within_budget: boolean;
}

// ============================================================
// Connector Schema
// ============================================================

export interface ConnectorConfig {
  /** Connector ID */
  id: string;

  /** Connector 类型 */
  type: "llm" | "scm" | "ci" | "ticketing" | "chat" | "mcp";

  /** 名称 */
  name: string;

  /** 配置 (不含密钥) */
  config: Record<string, unknown>;

  /** 密钥引用 (非明文) */
  secret_ref?: string;

  /** 是否启用 */
  enabled: boolean;
}

// ============================================================
// Session Schema
// ============================================================

export interface SessionState extends Versioned {
  /** Session ID */
  session_id: string;

  /** 关联 Run ID */
  run_id: string;

  /** 创建时间 */
  created_at: string;

  /** 最后活跃时间 */
  last_active_at: string;

  /** 状态 */
  status: "active" | "paused" | "completed" | "expired";

  /** 检查点数据 (用于恢复) */
  checkpoint: Record<string, unknown>;

  /** 人工反馈历史 */
  human_feedback: HumanFeedback[];
}

export interface HumanFeedback {
  feedback_id: string;
  actor: ActorIdentity;
  content: string;
  target_task_id?: string;
  timestamp: string;
}

// ============================================================
// Failed Task Summary
// ============================================================

export interface FailedTaskSummary {
  task_id: string;
  failure_class: FailureClass;
  message: string;
  attempts: number;
  last_attempt_id: string;
}
