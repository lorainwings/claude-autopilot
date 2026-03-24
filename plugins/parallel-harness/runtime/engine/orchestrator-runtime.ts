/**
 * parallel-harness: Unified Runtime Orchestrator
 *
 * 商业化 GA 级统一运行时入口。
 * 负责从 intent ingest 到 result synthesis 的完整生命周期管理。
 *
 * 所有模块通过 ExecutionContext 共享统一 metadata。
 * 所有状态迁移通过 StateMachine 追踪。
 */

import { EventBus, createEvent } from "../observability/event-bus";
import { analyzeIntent } from "../orchestrator/intent-analyzer";
import { buildTaskGraph } from "../orchestrator/task-graph-builder";
import { planOwnership, validateOwnership } from "../orchestrator/ownership-planner";
import { createSchedulePlan, getNextBatch } from "../scheduler/scheduler";
import { routeModel } from "../models/model-router";
import { packContext, buildTaskContract } from "../session/context-packager";
import { GateSystem } from "../gates/gate-system";
import { ApprovalWorkflow } from "../governance/governance";
import { WorkerExecutionController, type WorkerExecutionConfig } from "../workers/worker-runtime";
import { SessionStore, RunStore, AuditTrail, FileStore } from "../persistence/session-persistence";
import type { TaskGraph, TaskNode, ModelTier } from "../orchestrator/task-graph";
import type { VerificationResult } from "../verifiers/verifier-result";
import type { WorkerOutput, SynthesizerInput, SynthesizerOutput } from "../orchestrator/role-contracts";
import type { OwnershipPlan, OwnershipAssignment } from "../orchestrator/ownership-planner";
import type { SchedulePlan } from "../scheduler/scheduler";
import type { FileInfo } from "../session/context-packager";
import {
  generateId,
  SCHEMA_VERSION,
  FAILURE_ACTION_MAP,
  DEFAULT_RUN_CONFIG,
  type RunRequest,
  type RunPlan,
  type RunExecution,
  type RunResult,
  type RunStatus,
  type RunConfig,
  type TaskAttempt,
  type AttemptStatus,
  type FailureClass,
  type StatusTransition,
  type PreCheckResult,
  type CostLedger,
  type CostEntry,
  type CostSummary,
  type PolicyViolation,
  type ApprovalRecord,
  type ApprovalRequest,
  type AuditEvent,
  type AuditEventType,
  type ActorIdentity,
  type ProjectContext,
  type ScopeContext,
  type RoutingDecision,
  type BudgetEstimate,
  type RunQualityReport,
  type AuditSummary,
  type FailedTaskSummary,
  type GateResult,
  type SessionState,
} from "../schemas/ga-schemas";

// ============================================================
// Execution Context — 所有模块共享的运行上下文
// ============================================================

export interface ExecutionContext {
  /** Run ID */
  run_id: string;

  /** 关联的 Request ID，用于跨进程恢复时回填 checkpoint */
  request_id?: string;

  /** Batch ID */
  batch_id: string;

  /** 触发者 */
  actor: ActorIdentity;

  /** 项目上下文 */
  project: ProjectContext;

  /** 运行配置 */
  config: RunConfig;

  /** 事件总线 */
  eventBus: EventBus;

  /** 成本账本 */
  costLedger: CostLedger;

  /** 策略引擎 */
  policyEngine: PolicyEngine;

  /** 所有权规划 */
  ownershipPlan?: OwnershipPlan;

  /** 审计事件收集器 */
  auditLog: AuditEvent[];

  /** 收集的 gate 结果 */
  collectedGateResults: GateResult[];
}

// ============================================================
// Policy Engine (最小可用版本)
// ============================================================

export interface PolicyEngine {
  evaluate(context: ExecutionContext, action: string, params: Record<string, unknown>): PolicyEvalResult;
}

export interface PolicyEvalResult {
  allowed: boolean;
  violations: PolicyViolation[];
  requires_approval: boolean;
  message: string;
}

/** 默认策略引擎 — 基于配置规则的策略评估 */
export class DefaultPolicyEngine implements PolicyEngine {
  private rules: import("../schemas/ga-schemas").PolicyRule[];

  constructor(rules: import("../schemas/ga-schemas").PolicyRule[] = []) {
    this.rules = rules;
  }

  evaluate(context: ExecutionContext, action: string, params: Record<string, unknown>): PolicyEvalResult {
    const violations: PolicyViolation[] = [];
    let requires_approval = false;

    for (const rule of this.rules) {
      if (!rule.enabled) continue;

      const matched = this.matchCondition(rule.condition, action, params, context);
      if (!matched) continue;

      if (rule.enforcement === "block") {
        violations.push({
          violation_id: generateId("pvio"),
          rule_id: rule.rule_id,
          task_id: (params.task_id as string) || "",
          category: rule.category,
          severity: "error",
          message: `策略 ${rule.name} 阻断: ${action}`,
          blocked: true,
          occurred_at: new Date().toISOString(),
        });
      } else if (rule.enforcement === "approve") {
        requires_approval = true;
      } else if (rule.enforcement === "warn") {
        violations.push({
          violation_id: generateId("pvio"),
          rule_id: rule.rule_id,
          task_id: (params.task_id as string) || "",
          category: rule.category,
          severity: "warning",
          message: `策略 ${rule.name} 警告: ${action}`,
          blocked: false,
          occurred_at: new Date().toISOString(),
        });
      }
    }

    const blocked = violations.some((v) => v.blocked);

    return {
      allowed: !blocked,
      violations,
      requires_approval,
      message: blocked
        ? `策略阻断: ${violations.filter((v) => v.blocked).map((v) => v.message).join("; ")}`
        : requires_approval
          ? "需要审批"
          : "允许",
    };
  }

  private matchCondition(
    condition: import("../schemas/ga-schemas").PolicyCondition,
    action: string,
    params: Record<string, unknown>,
    context: ExecutionContext
  ): boolean {
    switch (condition.type) {
      case "always":
        return true;
      case "path_match": {
        const paths = ((params.paths as string[]) || (params.modified_paths as string[]) || []);
        const pattern = condition.params.pattern as string;
        return paths.some((p) => p.includes(pattern));
      }
      case "budget_threshold": {
        const threshold = condition.params.threshold as number;
        return context.costLedger.remaining_budget < threshold;
      }
      case "risk_level": {
        const minRisk = condition.params.min_risk as string;
        const riskOrder = { low: 0, medium: 1, high: 2, critical: 3 };
        const currentRisk = (params.risk_level as string) || "low";
        return (riskOrder[currentRisk as keyof typeof riskOrder] || 0) >= (riskOrder[minRisk as keyof typeof riskOrder] || 0);
      }
      case "model_tier": {
        const maxTier = condition.params.max_tier as string;
        const tierOrder = { "tier-1": 1, "tier-2": 2, "tier-3": 3 };
        const currentTier = (params.model_tier as string) || "tier-1";
        return (tierOrder[currentTier as keyof typeof tierOrder] || 0) > (tierOrder[maxTier as keyof typeof tierOrder] || 3);
      }
      case "action_type": {
        const targetActions = condition.params.actions as string[];
        return targetActions?.includes(action) || false;
      }
      default:
        return false;
    }
  }
}

// ============================================================
// State Machine
// ============================================================

/** Run 状态机合法迁移 */
const RUN_STATE_TRANSITIONS: Record<RunStatus, RunStatus[]> = {
  pending:           ["planned", "failed", "cancelled"],
  planned:           ["awaiting_approval", "scheduled", "failed", "cancelled"],
  awaiting_approval: ["scheduled", "failed", "cancelled"],
  scheduled:         ["running", "failed", "cancelled"],
  running:           ["verifying", "blocked", "failed", "partially_failed", "succeeded", "cancelled"],
  verifying:         ["running", "blocked", "failed", "partially_failed", "succeeded"],
  blocked:           ["running", "failed", "cancelled"],
  failed:            ["archived"],
  partially_failed:  ["running", "archived"],
  succeeded:         ["archived"],
  cancelled:         ["archived"],
  archived:          [],
};

export function isValidRunTransition(from: RunStatus, to: RunStatus): boolean {
  return RUN_STATE_TRANSITIONS[from]?.includes(to) || false;
}

export function transitionRunStatus(
  execution: RunExecution,
  newStatus: RunStatus,
  reason: string,
  actor?: string
): void {
  const from = execution.status;
  if (!isValidRunTransition(from, newStatus)) {
    throw new Error(`非法状态迁移: ${from} -> ${newStatus}`);
  }

  const transition: StatusTransition = {
    from,
    to: newStatus,
    reason,
    timestamp: new Date().toISOString(),
    actor,
  };

  execution.status = newStatus;
  execution.status_history.push(transition);
  execution.updated_at = new Date().toISOString();
}

/** Attempt 状态机合法迁移 */
const ATTEMPT_STATE_TRANSITIONS: Record<AttemptStatus, AttemptStatus[]> = {
  pending:    ["pre_check", "cancelled"],
  pre_check:  ["executing", "failed", "cancelled"],
  executing:  ["post_check", "succeeded", "failed", "timed_out", "cancelled"],
  post_check: ["succeeded", "failed"],
  succeeded:  [],
  failed:     [],
  cancelled:  [],
  timed_out:  [],
};

export function isValidAttemptTransition(from: AttemptStatus, to: AttemptStatus): boolean {
  return ATTEMPT_STATE_TRANSITIONS[from]?.includes(to) || false;
}

export function transitionAttemptStatus(
  attempt: TaskAttempt,
  newStatus: AttemptStatus,
  reason: string
): void {
  const from = attempt.status;
  if (!isValidAttemptTransition(from, newStatus)) {
    throw new Error(`非法 Attempt 状态迁移: ${from} -> ${newStatus}`);
  }

  attempt.status = newStatus;
  attempt.status_history.push({
    from,
    to: newStatus,
    reason,
    timestamp: new Date().toISOString(),
  });

  if (newStatus === "succeeded" || newStatus === "failed" || newStatus === "cancelled" || newStatus === "timed_out") {
    attempt.ended_at = new Date().toISOString();
    if (attempt.started_at) {
      attempt.duration_ms = new Date(attempt.ended_at).getTime() - new Date(attempt.started_at).getTime();
    }
  }
}

// ============================================================
// Audit Event Helper
// ============================================================

export function emitAudit(
  ctx: ExecutionContext,
  type: AuditEventType,
  payload: Record<string, unknown>,
  taskId?: string,
  attemptId?: string
): void {
  const event: AuditEvent = {
    schema_version: SCHEMA_VERSION,
    event_id: generateId("evt"),
    type,
    timestamp: new Date().toISOString(),
    actor: ctx.actor,
    run_id: ctx.run_id,
    task_id: taskId,
    attempt_id: attemptId,
    payload,
    scope: ctx.project.scope,
  };

  ctx.auditLog.push(event);

  // 同步到 event bus
  ctx.eventBus.emit(createEvent(
    mapAuditToEventType(type),
    payload,
    { graph_id: ctx.run_id, task_id: taskId }
  ));
}

function mapAuditToEventType(auditType: AuditEventType): import("../observability/event-bus").EventType {
  const mapping: Partial<Record<AuditEventType, import("../observability/event-bus").EventType>> = {
    task_dispatched: "task_dispatched",
    task_completed: "task_completed",
    task_failed: "task_failed",
    task_retried: "task_retrying",
    verification_passed: "verification_passed",
    verification_blocked: "verification_blocked",
    model_escalated: "model_escalated",
    model_downgraded: "downgrade_triggered",
    run_started: "session_started",
    run_completed: "session_completed",
  };
  return mapping[auditType] || "session_started";
}

// ============================================================
// Cost Ledger Helper
// ============================================================

export function recordCost(
  ledger: CostLedger,
  taskId: string,
  attemptId: string,
  tier: ModelTier,
  tokensUsed: number
): void {
  const tierCostRate: Record<ModelTier, number> = {
    "tier-1": 1,
    "tier-2": 5,
    "tier-3": 25,
  };

  const cost = (tokensUsed / 1000) * tierCostRate[tier];

  const entry: CostEntry = {
    entry_id: generateId("cost"),
    task_id: taskId,
    attempt_id: attemptId,
    model_tier: tier,
    tokens_used: tokensUsed,
    cost,
    recorded_at: new Date().toISOString(),
  };

  ledger.entries.push(entry);
  ledger.total_cost += cost;
  ledger.remaining_budget = ledger.budget_limit - ledger.total_cost;

  // 更新 tier 分布
  if (!ledger.tier_distribution[tier]) {
    ledger.tier_distribution[tier] = { tokens: 0, cost: 0, count: 0 };
  }
  ledger.tier_distribution[tier].tokens += tokensUsed;
  ledger.tier_distribution[tier].cost += cost;
  ledger.tier_distribution[tier].count += 1;
}

export function isBudgetExhausted(ledger: CostLedger): boolean {
  return ledger.remaining_budget <= 0;
}

// ============================================================
// Orchestrator Runtime — 统一主入口
// ============================================================

export class OrchestratorRuntime {
  private eventBus: EventBus;
  private policyEngine: PolicyEngine;
  private workerAdapter: WorkerAdapter;
  private workerController: WorkerExecutionController;
  private gateSystem: GateSystem;
  private approvalWorkflow: ApprovalWorkflow;

  // 持久化存储
  private sessionStore: SessionStore;
  private runStore: RunStore;
  private auditTrail: AuditTrail;
  private prProvider?: import("../integrations/pr-provider").PRProvider;
  private rbacEngine?: import("../governance/governance").RBACEngine;
  private hookRegistry?: import("../capabilities/capability-registry").HookRegistry;
  private instructionRegistry?: import("../capabilities/capability-registry").InstructionRegistry;

  constructor(options: OrchestratorOptions = {}) {
    this.eventBus = options.eventBus || new EventBus();
    this.policyEngine = options.policyEngine || new DefaultPolicyEngine();
    this.workerAdapter = options.workerAdapter || new LocalWorkerAdapter();
    this.workerController = new WorkerExecutionController(this.workerAdapter);
    this.gateSystem = options.gateSystem || new GateSystem();
    this.approvalWorkflow = options.approvalWorkflow || new ApprovalWorkflow(options.autoApproveRules || []);
    // 持久化：优先使用显式传入的 store，否则根据 dataDir 决定
    const dataDir = options.dataDir || ".parallel-harness/data";
    this.sessionStore = options.sessionStore || SessionStore.createDurable(`${dataDir}/sessions`);
    this.runStore = options.runStore || RunStore.createDurable(dataDir);
    this.auditTrail = options.auditTrail || AuditTrail.createDurable(`${dataDir}/audit`);
    this.prProvider = options.prProvider;
    this.rbacEngine = options.rbacEngine;
    this.hookRegistry = options.hookRegistry;
    this.instructionRegistry = options.instructionRegistry;
  }

  /**
   * 执行完整 Run — 统一入口 API
   */
  async executeRun(request: RunRequest): Promise<RunResult> {
    const run_id = generateId("run");
    const batch_id = generateId("batch");

    // 1. 初始化 Execution Context
    const ctx = this.createContext(run_id, batch_id, request);

    // 保存原始 request
    await this.runStore.saveRequest(request);

    // 2. 初始化 Run Execution
    const execution = this.initExecution(run_id, batch_id, request.config);
    await this.runStore.saveExecution(execution);

    // 3. 创建 Session
    const session = this.initSession(run_id);
    await this.sessionStore.save(session);

    emitAudit(ctx, "run_created", { intent: request.intent });

    try {
      // Phase 1: Plan
      await this.executeHookPhase("pre_plan", ctx);
      transitionRunStatus(execution, "planned", "规划完成");
      const plan = await this.planPhase(ctx, request);
      await this.runStore.savePlan(plan);
      await this.executeHookPhase("post_plan", ctx);
      emitAudit(ctx, "run_planned", {
        plan_id: plan.plan_id,
        task_count: plan.task_graph.tasks.length,
        batch_count: plan.schedule_plan.total_batches,
      });

      // Phase 2: 检查审批
      if (plan.pending_approvals.length > 0) {
        transitionRunStatus(execution, "awaiting_approval", "等待审批");

        for (const approval of plan.pending_approvals) {
          const result = this.approvalWorkflow.requestApproval({
            run_id: approval.run_id,
            task_id: approval.task_id,
            action: approval.action,
            reason: approval.reason,
            triggered_rules: approval.triggered_rules,
          });

          if (result.status === "approved") {
            execution.approval_records.push({
              ...result,
              decision: "approved",
            } as ApprovalRecord);
            emitAudit(ctx, "approval_decided", { approval_id: result.approval_id, decision: "auto_approved" });
          } else {
            // 审批仍处于 pending — 阻断并持久化完整状态以支持 resume
            emitAudit(ctx, "approval_decided", { approval_id: result.approval_id, decision: "blocked_pending" });
            transitionRunStatus(execution, "blocked", `审批未通过: ${approval.reason}`);

            // 写 checkpoint 以支持恢复（含完整 ApprovalRequest，支持跨进程恢复）
            await this.sessionStore.updateCheckpoint(session.session_id, {
              blocked_at: "approval",
              plan_id: plan.plan_id,
              pending_approval_id: result.approval_id,
              pending_approval_request: result,
              request_id: request.request_id,
            });
            execution.cost_ledger = ctx.costLedger;
            await this.runStore.saveExecution(execution);
            await this.auditTrail.recordBatch(ctx.auditLog);
            await this.auditTrail.forceFlush();

            const blockedResult = this.finalizeRun(ctx, execution, plan);
            blockedResult.final_status = "blocked";
            await this.runStore.saveResult(blockedResult);
            return blockedResult;
          }
        }
      }

      // Phase 3: Schedule + Execute
      await this.executeHookPhase("pre_dispatch", ctx);
      transitionRunStatus(execution, "scheduled", "已调度");
      transitionRunStatus(execution, "running", "开始执行");
      emitAudit(ctx, "run_started", {});

      ctx.ownershipPlan = plan.ownership_plan;
      await this.executePhase(ctx, execution, plan);
      await this.executeHookPhase("post_dispatch", ctx);

      // Phase 4: Verify (Run-level gates)
      if (execution.status === "running") {
        await this.executeHookPhase("pre_verify", ctx);
        transitionRunStatus(execution, "verifying", "运行级验证");
        await this.runLevelGates(ctx, execution, plan);
        await this.executeHookPhase("post_verify", ctx);
      }

      // Phase 5: Finalize
      // 同步 cost_ledger 到 execution
      execution.cost_ledger = ctx.costLedger;

      const result = this.finalizeRun(ctx, execution, plan);
      await this.runStore.saveResult(result);

      const finalStatus = this.determineFinalStatus(execution);
      if (execution.status !== finalStatus) {
        transitionRunStatus(execution, finalStatus, "执行完成");
      }
      result.final_status = execution.status;

      emitAudit(ctx, execution.status === "succeeded" ? "run_completed" : "run_failed", {
        final_status: execution.status,
        tasks_completed: result.completed_tasks.length,
        tasks_failed: result.failed_tasks.length,
      });

      // Phase 5b: PR 产出（如果配置了 PR 策略且有 provider）
      if (ctx.config.pr_strategy !== "none" && this.prProvider && execution.status === "succeeded") {
        await this.executeHookPhase("pre_pr", ctx);
        try {
          const { renderPRSummary, renderReviewComments } = await import("../integrations/pr-provider");
          const prResult = await this.prProvider.createPR({
            title: `[parallel-harness] ${request.intent.slice(0, 50)}`,
            body: renderPRSummary(result, plan, ctx.collectedGateResults),
            head_branch: `ph/${ctx.run_id}`,
            base_branch: "main",
            labels: ["parallel-harness"],
          });
          result.pr_artifacts = {
            pr_url: prResult.pr_url,
            pr_number: prResult.pr_number,
            branch_name: prResult.head_branch,
            summary: renderPRSummary(result, plan, ctx.collectedGateResults),
            walkthrough: "",
            review_comments: renderReviewComments(ctx.collectedGateResults),
            checks_status: {},
          };

          // 添加 review comments
          const reviewComments = renderReviewComments(ctx.collectedGateResults);
          for (const comment of reviewComments) {
            try {
              await this.prProvider.addReviewComment(String(prResult.pr_number), {
                file_path: comment.file_path,
                line: comment.line,
                body: comment.body,
              });
            } catch { /* review comment 失败不阻断 */ }
          }

          // 设置 check status
          const checkConclusion = execution.status === "succeeded" ? "success" as const : "failure" as const;
          try {
            await this.prProvider.setCheckStatus(String(prResult.pr_number), {
              name: "parallel-harness",
              status: "completed",
              conclusion: checkConclusion,
              output: {
                title: `parallel-harness: ${execution.status}`,
                summary: `${result.completed_tasks.length} 个任务完成, ${result.failed_tasks.length} 个失败`,
              },
            });
          } catch { /* check status 失败不阻断 */ }

          emitAudit(ctx, "pr_created", { pr_url: prResult.pr_url, pr_number: prResult.pr_number });
        } catch (prError) {
          emitAudit(ctx, "run_failed", { phase: "pr_creation", error: String(prError) });
          // PR 创建失败不阻断 run 结果
        }
        await this.executeHookPhase("post_pr", ctx);
      }

      // 持久化审计日志 + 最终状态
      await this.auditTrail.recordBatch(ctx.auditLog);
      await this.auditTrail.forceFlush();
      await this.runStore.saveExecution(execution);

      // 完成 session
      await this.sessionStore.complete(session.session_id);

      return result;
    } catch (error) {
      if (isValidRunTransition(execution.status, "failed")) {
        transitionRunStatus(execution, "failed", `运行时错误: ${error instanceof Error ? error.message : String(error)}`);
      }
      emitAudit(ctx, "run_failed", { error: error instanceof Error ? error.message : String(error) });
      // 异常路径完整持久化
      execution.cost_ledger = ctx.costLedger;
      await this.auditTrail.recordBatch(ctx.auditLog);
      await this.auditTrail.forceFlush();
      await this.runStore.saveExecution(execution);
      await this.sessionStore.complete(session.session_id);
      throw error;
    }
  }

  // ============================================================
  // Phase 实现
  // ============================================================

  private async planPhase(ctx: ExecutionContext, request: RunRequest): Promise<RunPlan> {
    // 1. 意图分析
    const intentResult = analyzeIntent(request.intent, {
      root_path: request.project.root_path,
      known_modules: request.project.known_modules,
    });

    // 2. 构建任务图 (buildTaskGraph 内部调用 scoreComplexity)
    const taskGraph = buildTaskGraph(intentResult, {}, request.project.root_path);

    // 4. 所有权规划
    const ownershipPlan = planOwnership(taskGraph);

    // 5. 调度计划
    const schedulePlan = createSchedulePlan(taskGraph, {
      max_concurrency: ctx.config.max_concurrency,
      high_risk_max_concurrency: ctx.config.high_risk_max_concurrency,
      prioritize_critical_path: ctx.config.prioritize_critical_path,
    });

    // 6. 模型路由决策（受 max_model_tier 约束）
    const tierOrder: ModelTier[] = ["tier-1", "tier-2", "tier-3"];
    const maxTierIdx = tierOrder.indexOf(ctx.config.max_model_tier || "tier-3");

    const routingDecisions: RoutingDecision[] = taskGraph.tasks.map((task) => {
      const result = routeModel({
        complexity: task.complexity.level,
        risk_level: task.risk_level,
        token_budget: ctx.config.budget_limit,
        retry_count: 0,
      });
      // 应用 max_model_tier 约束
      let finalTier = result.recommended_tier;
      const recIdx = tierOrder.indexOf(finalTier);
      if (recIdx > maxTierIdx) {
        finalTier = tierOrder[maxTierIdx];
      }
      return {
        schema_version: SCHEMA_VERSION,
        decision_id: generateId("route"),
        task_id: task.id,
        phase: "worker" as const,
        recommended_tier: finalTier,
        reasoning: result.reasoning,
        inputs: {
          complexity: task.complexity.level,
          risk: task.risk_level,
          retry_count: 0,
          budget_remaining: ctx.costLedger.remaining_budget,
        },
        decided_at: new Date().toISOString(),
      };
    });

    // 7. 预算估算
    const budgetEstimate: BudgetEstimate = {
      estimated_total_tokens: taskGraph.metadata.estimated_total_tokens,
      estimated_total_cost: taskGraph.tasks.reduce((sum, t) => {
        const tierRate: Record<ModelTier, number> = { "tier-1": 1, "tier-2": 5, "tier-3": 25 };
        return sum + (t.complexity.dimensions.estimated_tokens / 1000) * tierRate[t.model_tier];
      }, 0),
      budget_limit: ctx.config.budget_limit,
      within_budget: true,
    };
    budgetEstimate.within_budget = budgetEstimate.estimated_total_cost <= budgetEstimate.budget_limit;

    // 8. 检查需要审批的动作
    const pendingApprovals: import("../schemas/ga-schemas").ApprovalRequest[] = [];
    if (ownershipPlan.has_unresolvable_conflicts) {
      pendingApprovals.push({
        approval_id: generateId("appr"),
        run_id: ctx.run_id,
        action: "execute_with_conflicts",
        reason: "存在不可解决的所有权冲突",
        triggered_rules: ["ownership_conflict"],
        status: "pending",
        requested_at: new Date().toISOString(),
      });
    }

    return {
      schema_version: SCHEMA_VERSION,
      plan_id: generateId("plan"),
      run_id: ctx.run_id,
      task_graph: taskGraph,
      ownership_plan: ownershipPlan,
      schedule_plan: schedulePlan,
      routing_decisions: routingDecisions,
      budget_estimate: budgetEstimate,
      pending_approvals: pendingApprovals,
      planned_at: new Date().toISOString(),
    };
  }

  private async executePhase(
    ctx: ExecutionContext,
    execution: RunExecution,
    plan: RunPlan
  ): Promise<void> {
    const { task_graph: graph, schedule_plan: schedule, ownership_plan: ownership } = plan;
    const taskMap = new Map(graph.tasks.map((t) => [t.id, t]));

    // 从已持久化的 completed_attempts 中恢复已完成任务集合（支持 resume）
    const completedTasks = new Set<string>();
    const failedTasks = new Set<string>();
    for (const [taskId, attempts] of Object.entries(execution.completed_attempts)) {
      const succeeded = attempts.some((a) => a.status === "succeeded");
      if (succeeded) {
        completedTasks.add(taskId);
      }
    }

    for (const batch of schedule.batches) {
      ctx.eventBus.emit(createEvent("batch_started", { batch_index: batch.batch_index }, { graph_id: ctx.run_id }));

      const batchPromises = batch.task_ids.map(async (taskId) => {
        const task = taskMap.get(taskId);
        if (!task) return;

        // 跳过已完成的任务（支持 resume）
        if (completedTasks.has(taskId)) return;

        // 检查依赖是否满足
        const depsOk = task.dependencies.every((d) => completedTasks.has(d));
        if (!depsOk) {
          failedTasks.add(taskId);
          return;
        }

        // 检查是否因之前失败被跳过
        const depsFailed = task.dependencies.some((d) => failedTasks.has(d));
        if (depsFailed) {
          failedTasks.add(taskId);
          return;
        }

        try {
          await this.executeTask(ctx, execution, task, ownership, plan);
          completedTasks.add(taskId);
        } catch {
          failedTasks.add(taskId);
        }
      });

      await Promise.all(batchPromises);

      ctx.eventBus.emit(createEvent("batch_completed", {
        batch_index: batch.batch_index,
        completed: [...completedTasks].length,
        failed: [...failedTasks].length,
      }, { graph_id: ctx.run_id }));

      // 预算检查
      if (isBudgetExhausted(ctx.costLedger)) {
        emitAudit(ctx, "budget_exceeded", { total_cost: ctx.costLedger.total_cost });
        break;
      }
    }
  }

  private async executeTask(
    ctx: ExecutionContext,
    execution: RunExecution,
    task: TaskNode,
    ownership: OwnershipPlan,
    plan: RunPlan
  ): Promise<void> {
    const maxRetries = task.retry_policy.max_retries;
    let lastFailureClass: FailureClass | undefined;

    for (let attemptNum = 1; attemptNum <= maxRetries + 1; attemptNum++) {
      // 动态模型路由 — 每次 attempt 重新计算，考虑失败历史和预算
      const routingResult = routeModel({
        complexity: task.complexity.level,
        risk_level: task.risk_level,
        token_budget: ctx.costLedger.remaining_budget,
        retry_count: attemptNum - 1,
        task_type_hint: task.title,
      });
      const currentTier = routingResult.recommended_tier;

      const attempt = this.createAttempt(ctx.run_id, task.id, attemptNum, currentTier);

      // Pre-checks
      transitionAttemptStatus(attempt, "pre_check", "执行前检查");
      const preChecks = this.runPreChecks(ctx, task, ownership, attempt, execution);
      attempt.pre_checks = preChecks;

      const blocked = preChecks.some((c) => !c.passed);
      if (blocked) {
        const failedCheck = preChecks.find((c) => !c.passed);

        // 如果是 approval 类型失败，触发审批流
        if (failedCheck?.check_type === "approval") {
          const approvalResult = this.approvalWorkflow.requestApproval({
            run_id: ctx.run_id,
            task_id: task.id,
            action: "worker_execute",
            reason: failedCheck.message,
            triggered_rules: ["policy_approval_required"],
          });

          if (approvalResult.status === "approved") {
            // 自动审批通过，继续执行
            execution.approval_records.push({
              ...approvalResult,
              decision: "approved",
            } as ApprovalRecord);
            emitAudit(ctx, "approval_decided", {
              approval_id: approvalResult.approval_id,
              decision: "auto_approved",
              task_id: task.id,
            });
            // 继续正常执行（不 break/continue）
          } else {
            // 需要人工审批 — 阻断整个 run，并写 checkpoint 支持跨进程恢复
            emitAudit(ctx, "approval_requested", {
              approval_id: approvalResult.approval_id,
              task_id: task.id,
              reason: failedCheck.message,
            });
            transitionRunStatus(execution, "blocked", `任务 ${task.id} 需要审批: ${failedCheck.message}`);

            // 持久化 checkpoint（仿 plan-level 审批分支）
            const taskSession = await this.sessionStore.getByRunId(ctx.run_id);
            if (taskSession) {
              await this.sessionStore.updateCheckpoint(taskSession.session_id, {
                blocked_at: "task_approval",
                plan_id: plan.plan_id,
                pending_approval_id: approvalResult.approval_id,
                pending_approval_request: approvalResult,
                request_id: ctx.request_id,
              });
            }
            execution.cost_ledger = ctx.costLedger;
            await this.runStore.saveExecution(execution);
            await this.auditTrail.recordBatch(ctx.auditLog);
            const blockedResult = this.finalizeRun(ctx, execution, plan);
            blockedResult.final_status = "blocked";
            await this.runStore.saveResult(blockedResult);

            throw new Error(`任务 ${task.id} 被审批阻断`);
          }
        } else {
          // 非 approval 类型的前置检查失败 — 原有逻辑
          transitionAttemptStatus(attempt, "failed", `前置检查失败: ${failedCheck?.message}`);
          attempt.failure_class = failedCheck?.check_type === "ownership"
            ? "ownership_conflict"
            : failedCheck?.check_type === "policy"
              ? "permanent_policy_failure"
              : failedCheck?.check_type === "budget"
                ? "budget_exhausted"
                : "permanent_policy_failure";
          lastFailureClass = attempt.failure_class;

          execution.completed_attempts[task.id] = [
            ...(execution.completed_attempts[task.id] || []), attempt
          ];
          emitAudit(ctx, "worker_failed", {
            failure_class: attempt.failure_class,
            message: failedCheck?.message,
          }, task.id, attempt.attempt_id);

          // 如果是永久失败，不重试
          if (!FAILURE_ACTION_MAP[attempt.failure_class].retry) break;
          continue;
        }
      }

      // Execute
      transitionAttemptStatus(attempt, "executing", "执行中");
      emitAudit(ctx, "worker_started", { attempt_number: attemptNum, model_tier: attempt.model_tier }, task.id, attempt.attempt_id);

      try {
        // 打包上下文
        const contextPack = packContext(task, this.getAvailableFiles(ctx));
        const contract = buildTaskContract(task, contextPack);

        // 调用 Worker — 通过 WorkerExecutionController（带超时/沙箱/能力校验）
        const executionResult = await this.workerController.execute({
          contract,
          model_tier: attempt.model_tier,
          project_root: ctx.project.root_path,
          max_idle_ms: ctx.config.timeout_ms,
        });
        const workerOutput = executionResult.output;

        // 检测 worker 是否真实执行成功
        if (workerOutput.status === "failed" || workerOutput.status === "blocked") {
          transitionAttemptStatus(attempt, "failed", `Worker 返回 ${workerOutput.status}: ${workerOutput.summary}`);
          attempt.failure_class = "transient_tool_failure";
          attempt.failure_detail = workerOutput.summary;
          lastFailureClass = attempt.failure_class;
          execution.completed_attempts[task.id] = [...(execution.completed_attempts[task.id] || []), attempt];
          emitAudit(ctx, "worker_failed", { failure_class: attempt.failure_class, status: workerOutput.status }, task.id, attempt.attempt_id);
          continue;
        }
        if (workerOutput.status === "warning" && workerOutput.modified_paths.length === 0) {
          // 降级模式：CLI 不可用且未产出任何修改 — 视为失败，不可伪装成功
          transitionAttemptStatus(attempt, "failed", `Worker 降级执行无产出: ${workerOutput.summary}`);
          attempt.failure_class = "unsupported_capability";
          attempt.failure_detail = workerOutput.summary;
          lastFailureClass = attempt.failure_class;
          execution.completed_attempts[task.id] = [...(execution.completed_attempts[task.id] || []), attempt];
          emitAudit(ctx, "worker_failed", { failure_class: attempt.failure_class, status: "warning_no_output" }, task.id, attempt.attempt_id);
          continue;
        }

        attempt.output_summary = workerOutput.summary;
        attempt.modified_files = workerOutput.modified_paths;
        attempt.artifacts = workerOutput.artifacts;
        attempt.tokens_used = workerOutput.tokens_used;

        // Post-check: Ownership 验证
        transitionAttemptStatus(attempt, "post_check", "执行后检查");
        const ownershipAssignment = ownership.assignments.find((a) => a.task_id === task.id);
        if (ownershipAssignment) {
          const violations = validateOwnership(ownershipAssignment, workerOutput.modified_paths);
          if (violations.length > 0) {
            transitionAttemptStatus(attempt, "failed", `所有权违规: ${violations.map((v) => v.message).join("; ")}`);
            attempt.failure_class = "ownership_conflict";
            lastFailureClass = attempt.failure_class;

            for (const v of violations) {
              emitAudit(ctx, "ownership_violated", { path: v.path, message: v.message }, task.id);
            }

            execution.completed_attempts[task.id] = [
              ...(execution.completed_attempts[task.id] || []), attempt
            ];
            continue;
          }
        }

        // 记录成本
        recordCost(ctx.costLedger, task.id, attempt.attempt_id, attempt.model_tier, workerOutput.tokens_used);
        attempt.cost = (workerOutput.tokens_used / 1000) * ({ "tier-1": 1, "tier-2": 5, "tier-3": 25 }[attempt.model_tier]);

        // Task-level Gate 验证
        const gateResults = await this.gateSystem.evaluate(
          { ctx, task, workerOutput, level: "task" },
          ctx.config.enabled_gates
        );

        // 收集 gate 结果（无论通过与否）
        ctx.collectedGateResults.push(...gateResults);

        const gateBlocked = this.gateSystem.hasBlockingFailure(gateResults);
        if (gateBlocked) {
          transitionAttemptStatus(attempt, "failed", "Gate 验证阻断");
          attempt.failure_class = "verification_failed";
          lastFailureClass = attempt.failure_class;

          for (const g of gateResults.filter((r) => !r.passed)) {
            emitAudit(ctx, "gate_blocked", {
              gate_type: g.gate_type,
              conclusion: g.conclusion?.summary,
            }, task.id);
          }

          execution.completed_attempts[task.id] = [
            ...(execution.completed_attempts[task.id] || []), attempt
          ];

          // 模型升级由下一次循环顶部的动态路由自动处理（retry_count 增加 → tier 提升）
          continue;
        }

        // 成功
        transitionAttemptStatus(attempt, "succeeded", "执行成功");
        emitAudit(ctx, "worker_completed", {
          tokens_used: workerOutput.tokens_used,
          modified_files: workerOutput.modified_paths.length,
        }, task.id, attempt.attempt_id);

        task.status = "verified";
        task.result = {
          success: true,
          summary: workerOutput.summary,
          artifacts: workerOutput.artifacts,
          actual_model_tier: attempt.model_tier,
          tokens_used: workerOutput.tokens_used,
          duration_ms: attempt.duration_ms || 0,
          retry_count: attemptNum - 1,
        };

        execution.completed_attempts[task.id] = [
          ...(execution.completed_attempts[task.id] || []), attempt
        ];

        for (const g of gateResults.filter((r) => r.passed)) {
          emitAudit(ctx, "gate_passed", { gate_type: g.gate_type }, task.id);
        }

        return; // 成功，退出重试循环
      } catch (error) {
        transitionAttemptStatus(attempt, "failed", `执行错误: ${error instanceof Error ? error.message : String(error)}`);
        attempt.failure_class = "transient_tool_failure";
        attempt.failure_detail = error instanceof Error ? error.message : String(error);
        lastFailureClass = attempt.failure_class;

        emitAudit(ctx, "worker_failed", {
          failure_class: attempt.failure_class,
          error: attempt.failure_detail,
        }, task.id, attempt.attempt_id);

        execution.completed_attempts[task.id] = [
          ...(execution.completed_attempts[task.id] || []), attempt
        ];
        // 模型升级由下一次循环顶部的动态路由自动处理
      }
    }

    // 所有重试用尽
    task.status = "failed";
    throw new Error(`任务 ${task.id} 在 ${maxRetries + 1} 次尝试后失败，最后一次失败: ${lastFailureClass}`);
  }

  private async runLevelGates(
    ctx: ExecutionContext,
    execution: RunExecution,
    plan: RunPlan
  ): Promise<void> {
    const runGates = await this.gateSystem.evaluate(
      { ctx, plan, level: "run" },
      ctx.config.enabled_gates
    );

    // 收集 run-level gate 结果
    ctx.collectedGateResults.push(...runGates);

    for (const gate of runGates) {
      if (gate.blocking && !gate.passed) {
        transitionRunStatus(execution, "blocked", `Run-level gate 阻断: ${gate.gate_type}`);
        emitAudit(ctx, "gate_blocked", { gate_type: gate.gate_type, level: "run" });
        return;
      }
      if (gate.passed) {
        emitAudit(ctx, "gate_passed", { gate_type: gate.gate_type, level: "run" });
      }
    }
  }

  // ============================================================
  // Helper Methods
  // ============================================================

  private createContext(run_id: string, batch_id: string, request: RunRequest): ExecutionContext {
    const config = { ...DEFAULT_RUN_CONFIG, ...request.config };

    return {
      run_id,
      request_id: request.request_id,
      batch_id,
      actor: request.actor,
      project: request.project,
      config,
      eventBus: this.eventBus,
      costLedger: {
        schema_version: SCHEMA_VERSION,
        run_id,
        entries: [],
        total_cost: 0,
        budget_limit: config.budget_limit,
        remaining_budget: config.budget_limit,
        tier_distribution: {} as Record<ModelTier, { tokens: number; cost: number; count: number }>,
      },
      policyEngine: this.policyEngine,
      auditLog: [],
      collectedGateResults: [],
    };
  }

  private initExecution(run_id: string, batch_id: string, config?: RunConfig): RunExecution {
    const budgetLimit = config?.budget_limit ?? DEFAULT_RUN_CONFIG.budget_limit;
    return {
      schema_version: SCHEMA_VERSION,
      run_id,
      batch_id,
      status: "pending",
      status_history: [{
        from: "",
        to: "pending",
        reason: "Run 初始化",
        timestamp: new Date().toISOString(),
      }],
      active_attempts: {},
      completed_attempts: {},
      verification_results: {},
      approval_records: [],
      policy_violations: [],
      cost_ledger: {
        schema_version: SCHEMA_VERSION,
        run_id,
        entries: [],
        total_cost: 0,
        budget_limit: budgetLimit,
        remaining_budget: budgetLimit,
        tier_distribution: {} as Record<ModelTier, { tokens: number; cost: number; count: number }>,
      },
      started_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
  }

  private initSession(run_id: string): SessionState {
    return {
      schema_version: SCHEMA_VERSION,
      session_id: generateId("sess"),
      run_id,
      created_at: new Date().toISOString(),
      last_active_at: new Date().toISOString(),
      status: "active",
      checkpoint: {},
      human_feedback: [],
    };
  }

  private createAttempt(run_id: string, task_id: string, attemptNumber: number, modelTier: ModelTier): TaskAttempt {
    return {
      schema_version: SCHEMA_VERSION,
      attempt_id: generateId("att"),
      run_id,
      task_id,
      attempt_number: attemptNumber,
      status: "pending",
      status_history: [{
        from: "",
        to: "pending",
        reason: "Attempt 初始化",
        timestamp: new Date().toISOString(),
      }],
      model_tier: modelTier,
      input_summary: "",
      output_summary: "",
      modified_files: [],
      artifacts: [],
      tokens_used: 0,
      cost: 0,
      pre_checks: [],
      started_at: new Date().toISOString(),
    };
  }

  private runPreChecks(
    ctx: ExecutionContext,
    task: TaskNode,
    ownership: OwnershipPlan,
    attempt: TaskAttempt,
    execution?: RunExecution
  ): PreCheckResult[] {
    const results: PreCheckResult[] = [];

    // 1. Ownership 检查
    const assignment = ownership.assignments.find((a) => a.task_id === task.id);
    results.push({
      check_type: "ownership",
      passed: !!assignment,
      message: assignment ? "所有权分配正常" : `任务 ${task.id} 缺少所有权分配`,
    });

    // 2. Policy 检查
    const policyResult = ctx.policyEngine.evaluate(ctx, "worker_execute", {
      task_id: task.id,
      paths: task.allowed_paths,
      risk_level: task.risk_level,
      model_tier: attempt.model_tier,
    });
    results.push({
      check_type: "policy",
      passed: policyResult.allowed,
      message: policyResult.message,
      details: { violations: policyResult.violations },
    });

    // 2b. Approval 检查 — 如果策略要求审批，但该任务已有批准记录则跳过
    if (policyResult.requires_approval) {
      const alreadyApproved = execution?.approval_records?.some(
        (r) => r.task_id === task.id && r.decision === "approved"
      );
      if (!alreadyApproved) {
        results.push({
          check_type: "approval",
          passed: false,
          message: `策略要求审批: ${policyResult.message}`,
          details: { requires_approval: true, task_id: task.id },
        });
      }
    }

    // 3. Budget 检查
    const budgetOk = !isBudgetExhausted(ctx.costLedger);
    results.push({
      check_type: "budget",
      passed: budgetOk,
      message: budgetOk
        ? `预算剩余: ${ctx.costLedger.remaining_budget.toFixed(2)}`
        : "预算已耗尽",
    });

    // 4. Capability 检查 — 使用 CapabilityRegistry 进行真实匹配
    const capabilities = this.workerController.getCapabilityRegistry().findByTaskType(task.title);
    const capabilityFound = capabilities.length > 0;
    results.push({
      check_type: "capability",
      passed: true, // 未找到匹配不阻断（降级允许），但记录真实状态
      message: capabilityFound
        ? `匹配 ${capabilities.length} 个能力: ${capabilities.map(c => c.name).join(", ")}`
        : `未找到任务 "${task.title}" 的匹配能力，允许继续执行`,
      details: { matched_capabilities: capabilities.map(c => c.id), found: capabilityFound },
    });

    emitAudit(ctx, "ownership_checked", {
      task_id: task.id,
      all_passed: results.every((r) => r.passed),
    }, task.id);

    return results;
  }

  private getAvailableFiles(_ctx: ExecutionContext): FileInfo[] {
    // 本地适配器：返回空列表，由 worker 自行发现文件
    return [];
  }

  private determineFinalStatus(execution: RunExecution): RunStatus {
    const allAttempts = Object.values(execution.completed_attempts).flat();
    const taskIds = new Set(allAttempts.map((a) => a.task_id));
    let allSucceeded = true;
    let anySucceeded = false;

    for (const taskId of taskIds) {
      const taskAttempts = allAttempts.filter((a) => a.task_id === taskId);
      const succeeded = taskAttempts.some((a) => a.status === "succeeded");
      if (succeeded) {
        anySucceeded = true;
      } else {
        allSucceeded = false;
      }
    }

    if (allSucceeded && taskIds.size > 0) return "succeeded";
    if (anySucceeded) return "partially_failed";
    if (execution.status === "blocked") return "blocked";
    return "failed";
  }

  private finalizeRun(ctx: ExecutionContext, execution: RunExecution, plan: RunPlan): RunResult {
    const allAttempts = Object.values(execution.completed_attempts).flat();
    const taskIds = new Set(allAttempts.map((a) => a.task_id));

    const completedTasks: string[] = [];
    const failedTasks: FailedTaskSummary[] = [];
    const skippedTasks: string[] = [];

    for (const task of plan.task_graph.tasks) {
      const taskAttempts = allAttempts.filter((a) => a.task_id === task.id);
      if (taskAttempts.length === 0) {
        skippedTasks.push(task.id);
        continue;
      }

      const succeeded = taskAttempts.some((a) => a.status === "succeeded");
      if (succeeded) {
        completedTasks.push(task.id);
      } else {
        const lastAttempt = taskAttempts[taskAttempts.length - 1];
        failedTasks.push({
          task_id: task.id,
          failure_class: lastAttempt.failure_class || "unknown",
          message: lastAttempt.failure_detail || "未知错误",
          attempts: taskAttempts.length,
          last_attempt_id: lastAttempt.attempt_id,
        });
      }
    }

    const costSummary: CostSummary = {
      total_tokens: ctx.costLedger.entries.reduce((s, e) => s + e.tokens_used, 0),
      total_cost: ctx.costLedger.total_cost,
      tier_distribution: Object.fromEntries(
        Object.entries(ctx.costLedger.tier_distribution).map(([k, v]) => [k, v.tokens])
      ) as Record<ModelTier, number>,
      total_retries: allAttempts.filter((a) => a.attempt_number > 1).length,
      budget_utilization: ctx.costLedger.total_cost / ctx.costLedger.budget_limit,
    };

    return {
      schema_version: SCHEMA_VERSION,
      run_id: ctx.run_id,
      final_status: execution.status,
      completed_tasks: completedTasks,
      failed_tasks: failedTasks,
      skipped_tasks: skippedTasks,
      quality_report: {
        overall_grade: failedTasks.length === 0 ? "A" : failedTasks.length <= 2 ? "B" : "C",
        gate_results: ctx.collectedGateResults,
        pass_rate: completedTasks.length / Math.max(plan.task_graph.tasks.length, 1),
        findings_count: {
          info: ctx.collectedGateResults.reduce((s, g) => s + g.conclusion.findings.filter(f => f.severity === "info").length, 0),
          warning: ctx.collectedGateResults.reduce((s, g) => s + g.conclusion.findings.filter(f => f.severity === "warning").length, 0),
          error: ctx.collectedGateResults.reduce((s, g) => s + g.conclusion.findings.filter(f => f.severity === "error").length, 0) + failedTasks.length,
          critical: ctx.collectedGateResults.reduce((s, g) => s + g.conclusion.findings.filter(f => f.severity === "critical").length, 0),
        },
        recommendations: ctx.collectedGateResults
          .filter(g => !g.passed)
          .flatMap(g => g.conclusion.required_actions),
      },
      cost_summary: costSummary,
      audit_summary: {
        total_events: ctx.auditLog.length,
        key_decisions: ctx.auditLog
          .filter((e) => ["model_escalated", "policy_violated", "gate_blocked", "approval_decided"].includes(e.type))
          .map((e) => `${e.type}: ${JSON.stringify(e.payload)}`),
        policy_violations_count: execution.policy_violations.length,
        approvals_count: execution.approval_records.length,
        human_interventions: 0,
        model_escalations: ctx.auditLog.filter((e) => e.type === "model_escalated").length,
      },
      completed_at: new Date().toISOString(),
      total_duration_ms: Date.now() - new Date(execution.started_at).getTime(),
    };
  }

  // ============================================================
  // 写操作 API：approve / reject / cancel / resume
  // ============================================================

  /**
   * 审批通过被阻断的 run，并恢复执行剩余任务图
   */
  async approveAndResume(runId: string, approvalId: string, decidedBy: string): Promise<RunResult> {
    // 根据审批类型映射到对应权限
    const session = await this.sessionStore.getByRunId(runId);
    const approvalAction = (session?.checkpoint?.pending_approval_request as ApprovalRequest)?.action;
    const permission = this.mapApprovalPermission(approvalAction);
    this.requirePermission(decidedBy, permission);
    const execution = await this.runStore.getExecution(runId);
    if (!execution) throw new Error(`Run ${runId} 不存在`);
    if (execution.status !== "blocked") throw new Error(`Run ${runId} 不在 blocked 状态，当前: ${execution.status}`);

    // 跨进程恢复：从 checkpoint 回填 pending approval 到内存
    if (session?.checkpoint?.pending_approval_request) {
      this.approvalWorkflow.rehydrate(
        session.checkpoint.pending_approval_request as ApprovalRequest,
      );
    }

    // 决策审批
    const record = this.approvalWorkflow.decide(approvalId, "approved", decidedBy, "手动审批通过");
    if (!record) throw new Error(`Approval ${approvalId} 不存在或已处理`);
    execution.approval_records.push(record);

    // 恢复 session
    if (session) {
      await this.sessionStore.updateCheckpoint(session.session_id, { resumed_at: new Date().toISOString() });
    }

    // 从 checkpoint 中取回 plan 和原始 request
    const planId = session?.checkpoint?.plan_id as string;
    const requestId = session?.checkpoint?.request_id as string;
    const plan = planId ? await this.runStore.getPlan(planId) : undefined;
    if (!plan) throw new Error(`无法恢复 Run ${runId} 的执行计划`);
    const originalRequest = requestId ? await this.runStore.getRequest(requestId) : undefined;

    // 恢复到 running 状态
    transitionRunStatus(execution, "running", `审批通过，恢复执行 (by ${decidedBy})`);
    await this.runStore.saveExecution(execution);

    // 从原始 request 重建 execution context（保留真实项目上下文）
    const config = originalRequest
      ? { ...DEFAULT_RUN_CONFIG, ...originalRequest.config }
      : { ...DEFAULT_RUN_CONFIG };

    const ctx: ExecutionContext = {
      run_id: runId,
      batch_id: execution.batch_id,
      actor: originalRequest?.actor || { id: decidedBy, type: "user", name: decidedBy, roles: [] },
      project: originalRequest?.project || { root_path: ".", known_modules: [], scope: {} },
      config,
      eventBus: this.eventBus,
      costLedger: execution.cost_ledger,
      policyEngine: this.policyEngine,
      ownershipPlan: plan.ownership_plan,
      auditLog: [],
      collectedGateResults: [],
    };

    emitAudit(ctx, "run_started", { resumed: true, approved_by: decidedBy });

    // 从头执行剩余的任务图（已完成的任务会被跳过）
    await this.executePhase(ctx, execution, plan);

    // Run-level gates (status 已被 transitionRunStatus 动态修改为 running)
    if ((execution.status as string) === "running") {
      transitionRunStatus(execution, "verifying", "运行级验证");
      await this.runLevelGates(ctx, execution, plan);
    }

    // Finalize
    execution.cost_ledger = ctx.costLedger;
    const result = this.finalizeRun(ctx, execution, plan);
    const finalStatus = this.determineFinalStatus(execution);
    if (execution.status !== finalStatus) {
      transitionRunStatus(execution, finalStatus, "恢复执行完成");
    }
    result.final_status = execution.status;

    await this.runStore.saveResult(result);
    await this.auditTrail.recordBatch(ctx.auditLog);
    await this.auditTrail.forceFlush();
    await this.runStore.saveExecution(execution);
    if (session) await this.sessionStore.complete(session.session_id);

    return result;
  }

  /**
   * 拒绝审批，标记 run 为 failed
   */
  async rejectRun(runId: string, approvalId: string, decidedBy: string, reason?: string): Promise<void> {
    // 根据审批类型映射到对应权限
    const session = await this.sessionStore.getByRunId(runId);
    const approvalAction = (session?.checkpoint?.pending_approval_request as ApprovalRequest)?.action;
    const permission = this.mapApprovalPermission(approvalAction);
    this.requirePermission(decidedBy, permission);
    const execution = await this.runStore.getExecution(runId);
    if (!execution) throw new Error(`Run ${runId} 不存在`);

    // 跨进程恢复：从 checkpoint 回填 pending approval 到内存
    if (session?.checkpoint?.pending_approval_request) {
      this.approvalWorkflow.rehydrate(
        session.checkpoint.pending_approval_request as ApprovalRequest,
      );
    }

    const record = this.approvalWorkflow.decide(approvalId, "denied", decidedBy, reason || "审批被拒绝");
    if (record) execution.approval_records.push(record);

    if (isValidRunTransition(execution.status, "failed")) {
      transitionRunStatus(execution, "failed", `审批被 ${decidedBy} 拒绝: ${reason || ""}`);
    }
    await this.runStore.saveExecution(execution);

    if (session) await this.sessionStore.complete(session.session_id);
  }

  /**
   * 取消 run
   */
  async cancelRun(runId: string, cancelledBy?: string): Promise<void> {
    if (cancelledBy) this.requirePermission(cancelledBy, "run.cancel");
    const execution = await this.runStore.getExecution(runId);
    if (!execution) throw new Error(`Run ${runId} 不存在`);

    if (isValidRunTransition(execution.status, "cancelled")) {
      transitionRunStatus(execution, "cancelled", "用户取消");
      await this.runStore.saveExecution(execution);
    } else {
      throw new Error(`Run ${runId} 当前状态 ${execution.status} 不能取消`);
    }

    const session = await this.sessionStore.getByRunId(runId);
    if (session) await this.sessionStore.complete(session.session_id);
  }

  // ============================================================
  // 查询 API
  // ============================================================

  async getRun(run_id: string): Promise<RunExecution | undefined> {
    return this.runStore.getExecution(run_id);
  }

  /**
   * Control Plane 专用：将 RunExecution 转换为前端可消费的 RunDetail 格式
   */
  async getRunDetail(run_id: string): Promise<import("../server/control-plane").RunDetail | undefined> {
    const execution = await this.runStore.getExecution(run_id);
    if (!execution) return undefined;
    const result = await this.runStore.getResult(run_id);
    // 从 audit trail 取 intent（run_created 事件携带）
    const auditEvents = await this.auditTrail.query({ run_id });
    const createdEvent = auditEvents.find((e) => e.type === "run_created");
    const intent = (createdEvent?.payload as Record<string, unknown>)?.intent as string || "";
    // 从 audit trail 获取 plan_id，再查 plan 以获取真实任务元数据
    const plannedEvent = auditEvents.find((e) => e.type === "run_planned");
    const planId = (plannedEvent?.payload as Record<string, unknown>)?.plan_id as string | undefined;
    const plan = planId ? await this.runStore.getPlan(planId) : undefined;
    const taskNodeMap = new Map((plan?.task_graph.tasks || []).map((t) => [t.id, t]));
    // 构建任务摘要
    const tasks: import("../server/control-plane").TaskSummary[] = [];
    for (const [taskId, attempts] of Object.entries(execution.completed_attempts)) {
      const latest = attempts[attempts.length - 1];
      if (!latest) continue;
      const totalTokens = attempts.reduce((s, a) => s + (a.tokens_used || 0), 0);
      const taskNode = taskNodeMap.get(taskId);
      tasks.push({
        id: taskId,
        title: taskNode?.title || latest.task_id,
        status: latest.status,
        model_tier: latest.model_tier,
        attempts: attempts.length,
        tokens_used: totalTokens,
        duration_ms: latest.duration_ms ?? 0,
        risk_level: taskNode?.risk_level || "medium",
      });
    }
    // gate_results from RunResult
    const gateResultViews: import("../server/control-plane").GateResultView[] = (result?.quality_report?.gate_results || []).map((g) => ({
      gate_type: g.gate_type,
      level: g.gate_level,
      passed: g.passed,
      blocking: g.blocking,
      findings_count: g.conclusion.findings.length,
      summary: g.conclusion.summary,
    }));
    // timeline from status_history
    const timeline: import("../server/control-plane").TimelineEvent[] = execution.status_history.map((h) => ({
      timestamp: h.timestamp,
      type: h.to,
      message: h.reason || "",
    }));
    const startedAt = execution.started_at;
    const completedAt = result?.completed_at;
    const durationMs = completedAt
      ? new Date(completedAt).getTime() - new Date(startedAt).getTime()
      : Date.now() - new Date(startedAt).getTime();
    return {
      run_id: execution.run_id,
      status: execution.status,
      intent,
      tasks,
      batches: (plan?.schedule_plan.batches || []).map((b, i) => ({
        batch_index: i,
        task_count: b.task_ids.length,
        has_critical_path: b.task_ids.some((tid: string) => plan?.task_graph.critical_path.includes(tid)),
      })),
      cost: {
        total_tokens: execution.cost_ledger.entries.reduce((s, e) => s + e.tokens_used, 0),
        total_cost: execution.cost_ledger.total_cost,
        budget_limit: execution.cost_ledger.budget_limit,
        budget_utilization: execution.cost_ledger.budget_limit > 0
          ? execution.cost_ledger.total_cost / execution.cost_ledger.budget_limit
          : 0,
        tier_breakdown: Object.entries(execution.cost_ledger.tier_distribution || {}).map(([tier, v]) => ({
          tier,
          tokens: (v as { tokens: number }).tokens,
          cost: (v as { cost: number }).cost,
        })),
      },
      gate_results: gateResultViews,
      timeline,
      started_at: startedAt,
      completed_at: completedAt,
      duration_ms: durationMs,
    };
  }

  /**
   * Control Plane 专用：列出所有 runs 的摘要
   */
  async listRuns(): Promise<import("../server/control-plane").RunSummary[]> {
    const executions = await this.runStore.listExecutions();
    const summaries: import("../server/control-plane").RunSummary[] = [];
    for (const execution of executions) {
      const auditEvents = await this.auditTrail.query({ run_id: execution.run_id });
      const createdEvent = auditEvents.find((e) => e.type === "run_created");
      const intent = (createdEvent?.payload as Record<string, unknown>)?.intent as string || "";
      const result = await this.runStore.getResult(execution.run_id);
      const taskCount = Object.keys(execution.completed_attempts).length;
      const completedAt = result?.completed_at;
      const durationMs = completedAt
        ? new Date(completedAt).getTime() - new Date(execution.started_at).getTime()
        : Date.now() - new Date(execution.started_at).getTime();
      summaries.push({
        run_id: execution.run_id,
        status: execution.status,
        intent,
        task_count: taskCount,
        started_at: execution.started_at,
        duration_ms: durationMs,
        total_cost: execution.cost_ledger.total_cost,
      });
    }
    return summaries;
  }

  /**
   * Control Plane 专用：获取 run 的 gate 结果
   */
  async getGateResults(run_id: string): Promise<GateResult[]> {
    const result = await this.runStore.getResult(run_id);
    return result?.quality_report?.gate_results || [];
  }

  async getRunResult(run_id: string): Promise<RunResult | undefined> {
    return this.runStore.getResult(run_id);
  }

  async getRunPlan(plan_id: string): Promise<RunPlan | undefined> {
    return this.runStore.getPlan(plan_id);
  }

  async getAuditLog(run_id?: string): Promise<AuditEvent[]> {
    if (run_id) {
      return this.auditTrail.query({ run_id });
    }
    return this.auditTrail.query({});
  }

  async getSession(run_id: string): Promise<SessionState | undefined> {
    return this.sessionStore.getByRunId(run_id);
  }

  private requirePermission(actorId: string, permission: import("../governance/governance").Permission): void {
    if (!this.rbacEngine) return; // RBAC 未配置时不阻断（向后兼容）
    const actor: import("../schemas/ga-schemas").ActorIdentity = {
      id: actorId,
      type: "user",
      name: actorId,
      roles: [],
    };
    if (!this.rbacEngine.hasPermission(actor, permission)) {
      throw new Error(`权限不足: ${actorId} 缺少 ${permission} 权限`);
    }
  }

  /**
   * 将审批动作类型映射到对应的 RBAC 权限
   */
  private mapApprovalPermission(action?: string): import("../governance/governance").Permission {
    const mapping: Record<string, import("../governance/governance").Permission> = {
      // 真实 action（由 orchestrator 发出）
      "execute_with_conflicts": "task.approve_sensitive_write",
      "worker_execute": "task.approve_sensitive_write",
      // 扩展 action
      "sensitive_file_write": "task.approve_sensitive_write",
      "budget_override": "gate.override",
      "high_risk_execution": "task.approve_model_upgrade",
      "model_upgrade": "task.approve_model_upgrade",
      "gate_override": "gate.override",
    };
    return (action && mapping[action]) || "task.approve_sensitive_write";
  }

  /**
   * 执行 Hook 阶段：调用 HookRegistry 中注册的 hooks
   */
  private async executeHookPhase(
    phase: import("../capabilities/capability-registry").HookPhase,
    ctx: ExecutionContext
  ): Promise<void> {
    if (!this.hookRegistry) return;
    try {
      await this.hookRegistry.executePhase(phase, {
        run_id: ctx.run_id,
        data: { timestamp: new Date().toISOString() },
      });
    } catch (err) {
      emitAudit(ctx, "run_failed", {
        phase: `hook_${phase}`,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  getEventBus(): EventBus {
    return this.eventBus;
  }
}

// ============================================================
// Worker Adapter Interface
// ============================================================

export interface WorkerAdapter {
  execute(input: import("../orchestrator/role-contracts").WorkerInput): Promise<WorkerOutput>;
}

/** 本地 Worker 适配器 — 通过 Bun.spawn 调用 claude CLI 执行任务 */
export class LocalWorkerAdapter implements WorkerAdapter {
  async execute(input: import("../orchestrator/role-contracts").WorkerInput): Promise<WorkerOutput> {
    const startTime = Date.now();
    const contract = input.contract;

    // 构造 prompt：将结构化 task contract 转换为 claude CLI 可执行的指令
    const promptParts = [
      `任务: ${contract.goal}`,
      `验收标准: ${contract.acceptance_criteria.join("; ")}`,
      `允许修改的文件: ${contract.allowed_paths.join(", ")}`,
      `禁止修改的文件: ${contract.forbidden_paths.join(", ")}`,
      contract.test_requirements.length > 0
        ? `测试要求: ${contract.test_requirements.join("; ")}`
        : "",
    ];

    // 注入 ContextPack：相关文件和代码片段
    if (contract.context?.relevant_files && contract.context.relevant_files.length > 0) {
      promptParts.push(`\n相关文件:\n${contract.context.relevant_files.map((f) => `- ${f}`).join("\n")}`);
    }
    if (contract.context?.relevant_snippets && contract.context.relevant_snippets.length > 0) {
      promptParts.push(`\n参考代码片段:\n${contract.context.relevant_snippets.map((s) => `--- ${s.file_path} ---\n${s.content}`).join("\n\n")}`);
    }

    promptParts.push(`执行完成后，请在输出中列出所有实际修改的文件路径（每行一个，以 "MODIFIED:" 为前缀）。`);

    const prompt = promptParts.filter(Boolean).join("\n");

    try {
      const proc = Bun.spawn(
        ["claude", "-p", prompt, "--output-format", "json"],
        {
          cwd: input.project_root || undefined,
          stdout: "pipe",
          stderr: "pipe",
          timeout: input.max_idle_ms || 300000,
          env: {
            ...process.env,
            PARALLEL_HARNESS_TASK_ID: contract.task_id,
            PARALLEL_HARNESS_MODEL_TIER: input.model_tier,
            ...(input.tool_policy ? { PARALLEL_HARNESS_TOOL_POLICY: input.tool_policy } : {}),
          },
        }
      );

      const stdout = await new Response(proc.stdout).text();
      const exitCode = await proc.exited;

      if (exitCode !== 0) {
        return {
          status: "failed",
          summary: `claude CLI 执行失败 (exit ${exitCode})`,
          artifacts: [],
          modified_paths: [],
          tokens_used: 0,
          duration_ms: Date.now() - startTime,
        };
      }

      // 解析 claude JSON 输出
      let parsed: { result?: string; cost_usd?: number } = {};
      try { parsed = JSON.parse(stdout); } catch { /* 非 JSON 输出 */ }

      const outputText = parsed.result || stdout;

      // 从输出中解析真实修改的文件路径
      const modifiedPaths = this.parseModifiedPaths(outputText, contract.allowed_paths);

      return {
        status: "ok",
        summary: outputText.slice(0, 500),
        artifacts: [],
        modified_paths: modifiedPaths,
        tokens_used: parsed.cost_usd ? Math.round(parsed.cost_usd * 100000) : 5000,
        duration_ms: Date.now() - startTime,
      };
    } catch {
      // claude CLI 不可用 — 返回 warning 状态，不伪装成功
      return {
        status: "warning",
        summary: `[降级] claude CLI 不可用，任务未实际执行: ${contract.goal}`,
        artifacts: [],
        modified_paths: [],
        tokens_used: 0,
        duration_ms: Date.now() - startTime,
      };
    }
  }

  /** 从 claude 输出中解析实际修改的文件路径 */
  private parseModifiedPaths(output: string, allowedPaths: string[]): string[] {
    const paths: string[] = [];

    // 方式 1：解析 "MODIFIED:" 前缀行
    const lines = output.split("\n");
    for (const line of lines) {
      const match = line.match(/^MODIFIED:\s*(.+)/);
      if (match) {
        paths.push(match[1].trim());
      }
    }

    // 方式 2：扫描 Write/Edit 工具调用提及的文件路径
    const filePatterns = output.matchAll(/(?:Write|Edit|Created|Modified|Updated)\s+(?:file\s+)?[`"']?([^\s`"']+\.\w{1,5})[`"']?/gi);
    for (const m of filePatterns) {
      if (m[1] && !paths.includes(m[1])) {
        paths.push(m[1]);
      }
    }

    // 如果仍无法解析，返回空（不伪造）
    return paths;
  }
}

// ============================================================
// Result Synthesizer — 综合所有结果
// ============================================================

export class ResultSynthesizer {
  /**
   * 综合所有 worker 输出和验证结果
   */
  synthesize(input: SynthesizerInput): SynthesizerOutput {
    const passedTasks: string[] = [];
    const failedTasks: string[] = [];
    const retryTasks: string[] = [];
    let totalTokens = 0;
    const tierDistribution: Record<ModelTier, number> = {
      "tier-1": 0,
      "tier-2": 0,
      "tier-3": 0,
    };
    let totalRetries = 0;

    for (const task of input.task_graph.tasks) {
      const workerOutput = input.worker_outputs.get(task.id);
      const verification = input.verification_results.get(task.id);

      if (!workerOutput) {
        failedTasks.push(task.id);
        continue;
      }

      if (workerOutput.status === "ok" || workerOutput.status === "warning") {
        if (verification && verification.final_decision === "block") {
          // 验证阻断
          if (verification.should_retry) {
            retryTasks.push(task.id);
          } else {
            failedTasks.push(task.id);
          }
        } else {
          passedTasks.push(task.id);
        }
      } else {
        failedTasks.push(task.id);
      }

      totalTokens += workerOutput.tokens_used;
      if (task.result?.actual_model_tier) {
        tierDistribution[task.result.actual_model_tier] += workerOutput.tokens_used;
      }
      totalRetries += task.result?.retry_count || 0;
    }

    const status = failedTasks.length === 0 ? "completed"
      : passedTasks.length > 0 ? "partial"
      : "failed";

    // 质量摘要
    const qualityParts: string[] = [];
    if (passedTasks.length > 0) qualityParts.push(`${passedTasks.length} 个任务通过`);
    if (failedTasks.length > 0) qualityParts.push(`${failedTasks.length} 个任务失败`);
    if (retryTasks.length > 0) qualityParts.push(`${retryTasks.length} 个任务需重试`);

    return {
      status,
      summary: `综合结果: ${qualityParts.join(", ")}`,
      passed_tasks: passedTasks,
      failed_tasks: failedTasks,
      retry_tasks: retryTasks,
      quality_summary: qualityParts.join("; "),
      cost_report: {
        total_tokens: totalTokens,
        tier_distribution: tierDistribution,
        total_retries: totalRetries,
      },
    };
  }
}

// ============================================================
// Orchestrator Options
// ============================================================

export interface OrchestratorOptions {
  eventBus?: EventBus;
  policyEngine?: PolicyEngine;
  workerAdapter?: WorkerAdapter;
  gateSystem?: GateSystem;
  approvalWorkflow?: ApprovalWorkflow;
  autoApproveRules?: string[];
  sessionStore?: SessionStore;
  runStore?: RunStore;
  auditTrail?: AuditTrail;
  prProvider?: import("../integrations/pr-provider").PRProvider;
  rbacEngine?: import("../governance/governance").RBACEngine;
  hookRegistry?: import("../capabilities/capability-registry").HookRegistry;
  instructionRegistry?: import("../capabilities/capability-registry").InstructionRegistry;
  /** 持久化数据目录，设置后默认使用 FileStore */
  dataDir?: string;
}

