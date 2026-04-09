/**
 * parallel-harness: Unified Runtime Orchestrator
 *
 * 商业化 GA 级统一运行时入口。
 * 负责从 intent ingest 到 result synthesis 的完整生命周期管理。
 *
 * 所有模块通过 ExecutionContext 共享统一 metadata。
 * 所有状态迁移通过 StateMachine 追踪。
 */

import { MergeGuard } from "../guards/merge-guard";
import { EventBus, createEvent } from "../observability/event-bus";
import { analyzeIntent } from "../orchestrator/intent-analyzer";
import { buildTaskGraph } from "../orchestrator/task-graph-builder";
import { planOwnership, validateOwnership } from "../orchestrator/ownership-planner";
import { createSchedulePlan, getNextBatch } from "../scheduler/scheduler";
import { routeModel } from "../models/model-router";
import { packContext, buildTaskContract } from "../session/context-packager";
import { GateSystem } from "../gates/gate-system";
import { classifyGate } from "../gates/gate-classification";
import { ApprovalWorkflow } from "../governance/governance";
import { WorkerExecutionController, type WorkerExecutionConfig } from "../workers/worker-runtime";
import { ExecutionProxy, inspectMergeTargetCleanliness } from "../workers/execution-proxy";
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
  failed:            ["archived", "running"],
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
    // Skill lifecycle
    skill_candidates_resolved: "skill_candidates_resolved",
    skill_selected: "skill_selected",
    skill_injected: "skill_injected",
    skill_completed: "skill_completed",
    skill_failed: "skill_failed",
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
// Skill Phase Inference — 推断 task 所属阶段
// ============================================================

/**
 * 从 task 元数据推断其所属的 skill 阶段。
 * 不依赖 task title 的字符串猜测，而是使用 task 的结构化属性。
 */
export function inferTaskPhase(task: TaskNode): string {
  // 优先使用 task metadata 中的 phase 标注
  if ((task as any).phase) return (task as any).phase;

  // 基于 verifier_set 推断：有 review/security/coverage gate 的倾向于验证阶段
  const verifierSet = task.verifier_set || [];
  if (verifierSet.includes("review" as any) || verifierSet.includes("security" as any)) {
    return "verification";
  }

  // 默认：implementation（dispatch 阶段覆盖的具体执行）
  return "dispatch";
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
  private skillRegistry?: import("../capabilities/capability-registry").SkillRegistry;

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
    this.skillRegistry = options.skillRegistry || this.createDefaultSkillRegistry();
  }

  /**
   * 创建默认 SkillRegistry — 注册三个阶段协议模板
   *
   * 所有 OrchestratorRuntime 实例默认自带三个阶段协议，
   * 确保 skill 选择/注入/完成事件在每次 run 中都会触发。
   */
  private createDefaultSkillRegistry(): import("../capabilities/capability-registry").SkillRegistry {
    const { SkillRegistry } = require("../capabilities/capability-registry");
    const { resolve, dirname } = require("path");
    const { existsSync, readFileSync } = require("fs");
    const registry = new SkillRegistry();

    // 定位 skills 目录：从当前模块向上查找
    const moduleDir = dirname(__filename);
    const pluginRoot = resolve(moduleDir, "../..");
    const skillsDir = resolve(pluginRoot, "skills");

    /** 从 SKILL.md 中提取协议摘要（去除 frontmatter，截断到合理长度） */
    const loadProtocol = (skillId: string): string | undefined => {
      const filePath = resolve(skillsDir, skillId, "SKILL.md");
      if (!existsSync(filePath)) return undefined;
      try {
        let content = readFileSync(filePath, "utf-8");
        // 去除 YAML frontmatter
        if (content.startsWith("---")) {
          const endIdx = content.indexOf("---", 3);
          if (endIdx > 0) content = content.slice(endIdx + 3).trim();
        }
        // 截断到合理长度避免 prompt 膨胀（保留前 800 字符作为协议摘要）
        return content.length > 800 ? content.slice(0, 800) + "\n..." : content;
      } catch {
        return undefined;
      }
    };

    registry.register({
      id: "harness-plan",
      name: "Harness Plan",
      version: "1.0.0",
      description: "并行工程规划阶段协议模板。负责意图分析、任务图构建、复杂度评估、文件所有权规划、模型路由和预算评估。",
      input_schema: {},
      output_schema: {},
      permissions: [],
      required_tools: [],
      recommended_tier: "tier-2" as const,
      applicable_phases: ["planning"],
      protocol_content: loadProtocol("harness-plan"),
    });

    registry.register({
      id: "harness-dispatch",
      name: "Harness Dispatch",
      version: "1.0.0",
      description: "并行工程调度阶段协议模板。负责执行前检查、按批次派发 Worker、监控执行状态、处理失败重试和降级策略。",
      input_schema: {},
      output_schema: {},
      permissions: [],
      required_tools: [],
      recommended_tier: "tier-2" as const,
      applicable_phases: ["dispatch"],
      protocol_content: loadProtocol("harness-dispatch"),
    });

    registry.register({
      id: "harness-verify",
      name: "Harness Verify",
      version: "1.0.0",
      description: "并行工程验证阶段协议模板。负责调度 9 类 Gate System 进行多维度质量验证，综合门禁结论并输出阻断或放行决策。",
      input_schema: {},
      output_schema: {},
      permissions: [],
      required_tools: [],
      recommended_tier: "tier-2" as const,
      applicable_phases: ["verification"],
      protocol_content: loadProtocol("harness-verify"),
    });

    return registry;
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
      if ((ctx.config.execution_sandbox_mode || "path_check") === "worktree") {
        new ExecutionProxy().cleanupStaleWorktrees(
          ctx.project.root_path,
          ctx.config.worktree_retention_minutes ?? DEFAULT_RUN_CONFIG.worktree_retention_minutes ?? 240,
        );
      }

      // Phase 1: Plan
      await this.executeHookPhase("pre_plan", ctx);
      transitionRunStatus(execution, "planned", "规划完成");

      // Skill lifecycle: run 级 planning 阶段 skill 选择
      const planSkillInvocation = this.emitRunPhaseSkillEvent(ctx, "planning", execution);

      let plan: RunPlan;
      try {
        plan = await this.planPhase(ctx, request);
        this.completeRunPhaseSkill(ctx, planSkillInvocation, true);
      } catch (planError) {
        this.completeRunPhaseSkill(ctx, planSkillInvocation, false, planError instanceof Error ? planError.message : String(planError));
        throw planError;
      }
      await this.runStore.savePlan(plan);
      await this.executeHookPhase("post_plan", ctx);
      emitAudit(ctx, "run_planned", {
        plan_id: plan.plan_id,
        task_count: plan.task_graph.tasks.length,
        batch_count: plan.schedule_plan.total_batches,
      });

      // Phase 1b: 歧义治理 — 高歧义请求走 blocked 状态
      if (plan.requirement_grounding && plan.requirement_grounding.ambiguity_items.length > 2) {
        transitionRunStatus(execution, "blocked", `需求歧义过多: ${plan.requirement_grounding.ambiguity_items.join("; ")}`);
        emitAudit(ctx, "gate_blocked", { phase: "requirement_grounding", ambiguity_count: plan.requirement_grounding.ambiguity_items.length });

        await this.sessionStore.updateCheckpoint(session.session_id, {
          blocked_at: "requirement_grounding",
          plan_id: plan.plan_id,
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
      const preDispatchEffects = await this.executeHookPhase("pre_dispatch", ctx);

      // 消费 hook effects：影响运行时行为
      for (const effect of preDispatchEffects) {
        switch (effect.type) {
          case "require_approval": {
            // hook 要求审批 — 如果尚未被 auto-approve 则阻断
            const reason = (effect.payload.reason as string) || "hook triggered approval";
            const approvalResult = this.approvalWorkflow.requestApproval({
              run_id: ctx.run_id,
              action: "hook_approval",
              reason,
              triggered_rules: ["hook_effect"],
              status: "pending",
              requested_at: new Date().toISOString(),
            } as any);
            if (approvalResult.status !== "approved") {
              emitAudit(ctx, "approval_requested", { source: "hook_effect", reason });
            }
            break;
          }
          case "reduce_concurrency": {
            // hook 要求降低并发
            const newMax = (effect.payload.max_concurrency as number) || 1;
            ctx.config.max_concurrency = Math.min(ctx.config.max_concurrency, newMax);
            emitAudit(ctx, "run_planned", { effect: "reduce_concurrency", new_max: ctx.config.max_concurrency });
            break;
          }
          case "add_gate": {
            // hook 要求追加 gate 类型到 enabled_gates
            const gateType = effect.payload.gate_type as string;
            if (gateType && !ctx.config.enabled_gates.includes(gateType as any)) {
              ctx.config.enabled_gates.push(gateType as any);
              emitAudit(ctx, "run_planned", { effect: "add_gate", gate_type: gateType });
            }
            break;
          }
          case "add_instruction": {
            // hook 要求追加 instruction — 记录审计，实际注入在 executeTask 中完成
            emitAudit(ctx, "run_planned", { effect: "add_instruction", content: effect.payload.content });
            break;
          }
        }
      }

      transitionRunStatus(execution, "scheduled", "已调度");
      transitionRunStatus(execution, "running", "开始执行");
      emitAudit(ctx, "run_started", {});

      // Skill lifecycle: run 级 dispatch 阶段 skill 选择
      const dispatchSkillInvocation = this.emitRunPhaseSkillEvent(ctx, "dispatch", execution);

      ctx.ownershipPlan = plan.ownership_plan;
      try {
        await this.executePhase(ctx, execution, plan);
        this.completeRunPhaseSkill(ctx, dispatchSkillInvocation, true);
      } catch (dispatchError) {
        this.completeRunPhaseSkill(ctx, dispatchSkillInvocation, false, dispatchError instanceof Error ? dispatchError.message : String(dispatchError));
        throw dispatchError;
      }
      await this.executeHookPhase("post_dispatch", ctx);

      // Phase 4: Verify (Run-level gates)
      if (execution.status === "running") {
        await this.executeHookPhase("pre_verify", ctx);
        transitionRunStatus(execution, "verifying", "运行级验证");

        // Skill lifecycle: run 级 verification 阶段 skill 选择
        const verifySkillInvocation = this.emitRunPhaseSkillEvent(ctx, "verification", execution);

        try {
          await this.runLevelGates(ctx, execution, plan);
          this.completeRunPhaseSkill(ctx, verifySkillInvocation, true);
        } catch (verifyError) {
          this.completeRunPhaseSkill(ctx, verifySkillInvocation, false, verifyError instanceof Error ? verifyError.message : String(verifyError));
          throw verifyError;
        }
        await this.executeHookPhase("post_verify", ctx);
      }

      // Phase 5: Finalize
      // 同步 cost_ledger 到 execution
      execution.cost_ledger = ctx.costLedger;

      // Phase 5a: MergeGuard — 在终态判定前做最终写集收敛检查
      const mergeGuard = new MergeGuard();
      const workerOutputsMap = new Map<string, WorkerOutput>();
      for (const [taskId, attempts] of Object.entries(execution.completed_attempts)) {
        const succeeded = attempts.find((a) => a.status === "succeeded");
        if (succeeded) {
          workerOutputsMap.set(taskId, {
            status: "ok",
            summary: succeeded.output_summary || "",
            artifacts: succeeded.artifacts || [],
            modified_paths: succeeded.modified_files || [],
            tokens_used: succeeded.tokens_used || 0,
            duration_ms: 0,
            actual_tool_calls: [],
            exit_code: 0,
          });
        }
      }
      const mergeGuardResult = mergeGuard.check(ctx, plan.task_graph, plan.ownership_plan, workerOutputsMap);
      emitAudit(ctx, mergeGuardResult.allowed ? "gate_passed" : "gate_blocked", {
        gate_type: "merge_guard",
        allowed: mergeGuardResult.allowed,
        blocking_reasons: mergeGuardResult.blocking_reasons,
      });

      if (!mergeGuardResult.allowed) {
        transitionRunStatus(execution, "blocked", `MergeGuard 阻断: ${mergeGuardResult.blocking_reasons.join("; ")}`);
      }

      // Phase 5b-pre: P1-2 HiddenEvalRunner — 在终态判定之前执行，结果影响终态
      let hiddenEvalBlocked = false;
      try {
        const { createDefaultHiddenSuites, runHiddenEvalForRelease } = await import("../verifiers/hidden-eval-runner");
        const hiddenSuites = createDefaultHiddenSuites(ctx.project.root_path);
        // 使用真实测试数据：只取 run 级 test gate（排除 TEST-DEFERRED 的 task 级结果）
        const testGates = ctx.collectedGateResults.filter(g =>
          g.gate_type === "test" &&
          g.gate_level === "run" // 只取 run 级，排除 task 级 TEST-DEFERRED
        );
        // fallback: 如果没有 run 级 test gate，取所有非 DEFERRED 的 test gate
        const effectiveTestGates = testGates.length > 0
          ? testGates
          : ctx.collectedGateResults.filter(g =>
              g.gate_type === "test" &&
              !g.conclusion?.findings?.some(f => f.rule_id === "TEST-DEFERRED")
            );
        const testCount = effectiveTestGates.length > 0 ? effectiveTestGates.length : 1;
        const testPassCount = effectiveTestGates.filter(g => g.passed).length;
        const hiddenResult = await runHiddenEvalForRelease(
          hiddenSuites,
          { test_count: testCount, pass_count: testPassCount },
          ctx.project.root_path
        );
        if (hiddenResult.gate_recommendation === "block") {
          hiddenEvalBlocked = true;
        }
        // 存储结果供后续报告使用
        (ctx as any)._hiddenEvalResult = hiddenResult;
      } catch { /* hidden eval 非关键路径 */ }

      // Phase 5b: 终态判定（在 MergeGuard + HiddenEval 之后）
      const finalStatus = this.determineFinalStatus(execution, plan);
      if (execution.status !== finalStatus) {
        transitionRunStatus(execution, finalStatus, "执行完成");
      }
      // hidden eval block 降级终态
      if (hiddenEvalBlocked && execution.status === "succeeded") {
        transitionRunStatus(execution, "blocked", "HiddenEval 阻断: 隐藏评估未通过");
      }

      // Phase 5c: 使用执行时真实收集的 attestation（不再 finalize 重建）
      const allAttestations: import("../workers/execution-proxy").ExecutionAttestation[] =
        (ctx as any)._collectedAttestations || [];

      // Phase 5d: 生成最终报告（含 evidence aggregation）
      const result = this.finalizeRun(ctx, execution, plan);
      result.final_status = execution.status;

      // 将 report aggregator 接入主链（含 attestation 证据）
      const { aggregateRunEvidence } = await import("../integrations/report-aggregator");
      const runReport = aggregateRunEvidence(result, ctx.collectedGateResults, allAttestations);
      // evidence refs 写入质量报告的 recommendations
      result.quality_report.recommendations = [
        ...result.quality_report.recommendations,
        ...runReport.evidence_refs.map(r => `[${r.type}${r.strength ? `/${r.strength}` : ""}] ${r.ref_id}: ${r.description}`),
      ];

      // P1-1: StageContractEngine — 基于 run 执行结果构建审计用阶段摘要
      // 注意：当前是推断式阶段摘要（从执行结果反推涉及阶段），而非全流程生命周期图。
      // 全流程生命周期图需要真正的 phase transition 驱动（如 LifecycleSpecStore.recordTransition），
      // 当前 parallel-harness 的 run 模型不覆盖 requirement/product_design/ui_design/tech_plan 阶段。
      try {
        const { buildStageGraph } = await import("../lifecycle/stage-contract-engine");
        const { LifecycleSpecStore } = await import("../lifecycle/lifecycle-spec-store");
        const lifecycleStore = new LifecycleSpecStore();

        const hasSucceeded = execution.status === "succeeded";
        const hasFailed = execution.status === "failed" || execution.status === "partially_failed";

        // 从 run 执行结果直接推断涉及的标准阶段（不依赖 domain → phase 映射）
        // 所有 run 至少涉及 implementation 阶段
        lifecycleStore.setSpec("implementation", {
          status: (hasSucceeded ? "completed" : hasFailed ? "blocked" : "in_progress") as any,
          ...(hasSucceeded ? { completed_at: new Date().toISOString() } : {}),
          ...(execution.started_at ? { started_at: execution.started_at } : {}),
        });

        // 如果有测试 gate 结果，说明经历了 testing 阶段
        const hasTestGates = ctx.collectedGateResults.some(g => g.gate_type === "test");
        if (hasTestGates) {
          const testsPassed = ctx.collectedGateResults
            .filter(g => g.gate_type === "test" && g.gate_level === "run")
            .every(g => g.passed);
          lifecycleStore.setSpec("testing", {
            status: (testsPassed ? "completed" : "blocked") as any,
          });
        }

        // 如果生成了报告，说明经历了 reporting 阶段
        if (result.generated_reports && result.generated_reports.length > 0) {
          lifecycleStore.setSpec("reporting", {
            status: "completed" as any,
            completed_at: new Date().toISOString(),
          });
        }

        const stageGraph = buildStageGraph(lifecycleStore);
        emitAudit(ctx, "run_completed", {
          stage_graph: {
            current_phase: stageGraph.current_phase,
            completed: stageGraph.completed_phases.length,
            blocked: stageGraph.blocked_phases.length,
            is_inferred: true, // 标注为推断值而非真实生命周期转换
          },
        });
      } catch { /* lifecycle 非关键路径 */ }

      // P1-2: 写入 hidden eval 结果到报告
      const hiddenEvalResult = (ctx as any)._hiddenEvalResult;
      if (hiddenEvalResult) {
        if (hiddenEvalResult.gate_recommendation === "block") {
          result.quality_report.recommendations.push("[hidden-eval/blocking] 隐藏评估未通过，建议复查");
        } else if (hiddenEvalResult.gate_recommendation === "warn") {
          result.quality_report.recommendations.push("[hidden-eval/signal] 隐藏评估存在差异，建议关注");
        }
      }

      // P1-3: ReportTemplateEngine 主链化 — 生成正式报告
      try {
        const { ReportTemplateEngine, generateFinalReports } = await import("../integrations/report-template-engine");
        const reportEngine = new ReportTemplateEngine();
        const finalReports = generateFinalReports(reportEngine, {
          run_id: ctx.run_id,
          run_result: result,
          evidence_refs: runReport.evidence_refs.map(r => ({
            ref_id: r.ref_id,
            kind: r.type,
            description: r.description,
          })),
          gate_results: ctx.collectedGateResults,
        });
        if (finalReports.size > 0) {
          result.quality_report.recommendations.push(`[reports] 已生成 ${finalReports.size} 份正式报告`);
          // Finding 5 修正: 持久化报告摘要到 RunResult
          result.generated_reports = [];
          for (const [reportType, report] of finalReports) {
            result.generated_reports.push({
              report_type: reportType,
              executive_summary: report.executive_summary,
              generated_at: new Date().toISOString(),
            });
          }
        }
      } catch { /* report 非关键路径 */ }

      // Grounding evidence 追溯到报告
      if (plan.requirement_grounding) {
        const totalPlanned = plan.task_graph.tasks.length;
        const totalCompleted = result.completed_tasks.length;
        const allPassed = totalCompleted === totalPlanned && result.failed_tasks.length === 0;
        const groundingEvidence = plan.requirement_grounding.acceptance_matrix.map(item => {
          // 阻断性验收项：只有全部任务完成且无失败时才算满足
          // 非阻断性验收项：有任何成功即可
          const met = item.blocking
            ? allPassed
            : totalCompleted > 0;
          return {
            category: item.category,
            criterion: item.criterion,
            blocking: item.blocking,
            met,
          };
        });
        // 将未满足的 grounding 追溯作为 recommendations
        for (const ge of groundingEvidence) {
          if (!ge.met) {
            result.quality_report.recommendations.push(
              `[grounding/${ge.blocking ? "blocking" : "signal"}] ${ge.category}: ${ge.criterion}`
            );
          }
        }
      }

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

          // 汇总本次 run 所有成功 attempt 的 modified_files
          const allModifiedFiles = new Set<string>();
          for (const attempts of Object.values(execution.completed_attempts)) {
            for (const attempt of attempts) {
              if (attempt.status === "succeeded" && attempt.modified_files) {
                for (const f of attempt.modified_files) allModifiedFiles.add(f);
              }
            }
          }

          const prResult = await this.prProvider.createPR({
            title: `[parallel-harness] ${request.intent.slice(0, 50)}`,
            body: renderPRSummary(result, plan, ctx.collectedGateResults),
            head_branch: `ph/${ctx.run_id}`,
            base_branch: "main",
            labels: ["parallel-harness"],
            modified_files: [...allModifiedFiles],
            repo_root: ctx.project.root_path,
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

      // Phase 5d: 最终持久化 — PR artifacts 收敛后再保存 RunResult
      await this.runStore.saveResult(result);

      // 持久化审计日志 + 最终状态
      await this.auditTrail.recordBatch(ctx.auditLog);
      await this.auditTrail.forceFlush();
      await this.runStore.saveExecution(execution);

      // 完成 session
      await this.sessionStore.complete(session.session_id);

      if ((ctx.config.execution_sandbox_mode || "path_check") === "worktree") {
        new ExecutionProxy().cleanupStaleWorktrees(
          ctx.project.root_path,
          ctx.config.worktree_retention_minutes ?? DEFAULT_RUN_CONFIG.worktree_retention_minutes ?? 240,
        );
      }

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
      if ((ctx.config.execution_sandbox_mode || "path_check") === "worktree") {
        new ExecutionProxy().cleanupStaleWorktrees(
          ctx.project.root_path,
          ctx.config.worktree_retention_minutes ?? DEFAULT_RUN_CONFIG.worktree_retention_minutes ?? 240,
        );
      }
      throw error;
    }
  }

  // ============================================================
  // Phase 实现
  // ============================================================

  private async planPhase(ctx: ExecutionContext, request: RunRequest): Promise<RunPlan> {
    // 0. Requirement Grounding
    const { groundRequirement, buildStageContracts } = await import("../orchestrator/requirement-grounding");
    const grounding = groundRequirement(request);
    emitAudit(ctx, "run_planned", { phase: "requirement_grounding", ambiguity_count: grounding.ambiguity_items.length });

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
    }, ownershipPlan);

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
      requirement_grounding: grounding,
      stage_contracts: buildStageContracts(grounding, taskGraph.tasks),
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

      // 强制应用 max_model_tier 约束
      const tierOrder: ModelTier[] = ["tier-1", "tier-2", "tier-3"];
      const maxTierIdx = tierOrder.indexOf(ctx.config.max_model_tier || "tier-3");
      const recommendedTierIdx = tierOrder.indexOf(routingResult.recommended_tier);
      const currentTier = recommendedTierIdx > maxTierIdx
        ? tierOrder[maxTierIdx]
        : routingResult.recommended_tier;

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
            || failedCheck?.check_type === "workspace"
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

      // 提升 worktree 相关变量到 try 之外，确保 catch 可以访问
      const savedRootPath = ctx.project.root_path;
      let worktreePathForCleanup: string | undefined;
      let worktreeBranchForCleanup: string | undefined;
      let proxyForCleanup: any;

      // Skill invocation 提升到 try 之外，确保 catch 可以调用 markSkillFailed
      let skillInvocation: import("../capabilities/capability-registry").SkillInvocationRecord | undefined;

      /** 标记 task 级 skill 失败 — 所有失败分支统一调用此辅助函数 */
      const markSkillFailed = (reason: string) => {
        if (!skillInvocation) return;
        skillInvocation.status = "failed";
        skillInvocation.completed_at = new Date().toISOString();
        skillInvocation.evidence = { failure_reason: reason };
        emitAudit(ctx, "skill_failed", {
          selected_skill_id: skillInvocation.selected_skill_id,
          failure_reason: reason,
        }, task.id, attempt.attempt_id);
      };

      try {
        // 打包上下文 - 传递当前任务到 context，传入 routing 的 context_budget（Workstream D 闭环）
        const prevTask = (ctx as any).currentTask;
        (ctx as any).currentTask = task;
        const contextPack = packContext(
          task,
          this.getAvailableFiles(ctx),
          {},
          { max_input_tokens: routingResult.context_budget },
          undefined,
          ctx.project.root_path
        );
        (ctx as any).currentTask = prevTask;

        const contract = buildTaskContract(task, contextPack);

        // 注入 grounding criteria 到 contract（Workstream E 闭环）
        if (plan.requirement_grounding) {
          const { extractGroundingCriteria } = await import("../orchestrator/requirement-grounding");
          contract.grounding_criteria = extractGroundingCriteria(plan.requirement_grounding);
          contract.required_approvals = plan.requirement_grounding.required_approvals;
        }

        // 注入 instruction 到 contract（Workstream G effect 化）
        if (this.instructionRegistry) {
          const instructions = this.instructionRegistry.resolve({
            repo_path: ctx.project.root_path,
          });
          if (instructions.length > 0) {
            contract.context.constraints.coding_standards = instructions.map(i => i.content);
          }
        }

        // Skill Resolution: 运行时确定性 skill 选择与注入（Skill Observability 闭环）
        if (this.skillRegistry) {
          const taskPhase = inferTaskPhase(task);
          const skillMatches = this.skillRegistry.resolve({
            phase: taskPhase,
            language: undefined,
            file_path: task.allowed_paths?.[0],
            task_title: task.title,
          });

          // 发射 skill_candidates_resolved 事件
          if (skillMatches.length > 0) {
            emitAudit(ctx, "skill_candidates_resolved", {
              candidate_count: skillMatches.length,
              candidate_skill_ids: skillMatches.map(m => m.skill_id),
            }, task.id, attempt.attempt_id);
          }

          const selectedSkill = this.skillRegistry.select(skillMatches);
          if (selectedSkill) {
            // 发射 skill_selected 事件
            emitAudit(ctx, "skill_selected", {
              selected_skill_id: selectedSkill.skill_id,
              selection_reason: selectedSkill.selection_reason,
              source: selectedSkill.source,
              version: selectedSkill.version,
            }, task.id, attempt.attempt_id);

            // 注入到 contract
            contract.selected_skill_id = selectedSkill.skill_id;
            const skillManifest = this.skillRegistry.get(selectedSkill.skill_id);
            if (skillManifest) {
              // 优先使用从 SKILL.md 读取的真实协议内容，回退到 description
              contract.skill_protocol_summary = skillManifest.protocol_content
                || `[Skill: ${skillManifest.name} v${skillManifest.version}] ${skillManifest.description}`;
            }

            // 记录到 attempt
            attempt.selected_skill_id = selectedSkill.skill_id;

            // 创建调用记录
            skillInvocation = {
              run_id: ctx.run_id,
              task_id: task.id,
              attempt_id: attempt.attempt_id,
              phase: taskPhase,
              selected_skill_id: selectedSkill.skill_id,
              injected_at: new Date().toISOString(),
              status: "injected",
            };
            attempt.skill_invocation = skillInvocation;

            // 发射 skill_injected 事件
            emitAudit(ctx, "skill_injected", {
              selected_skill_id: selectedSkill.skill_id,
              protocol_digest: contract.skill_protocol_summary?.slice(0, 100),
            }, task.id, attempt.attempt_id);
          }
        }

        // ExecutionProxy: 前置准备（proxy 成为真实执行入口，绑定 model/tool policy/cwd）
        const proxy = new ExecutionProxy();
        const proxyPrep = proxy.prepareExecution({
          model_tier: currentTier,
          project_root: ctx.project.root_path,
          sandbox_paths: task.allowed_paths,
          allowed_tools: contract.context.constraints.allowed_paths.length > 0 ? undefined : undefined,
          denied_tools: ["TaskStop", "EnterWorktree"],
          worker_id: `worker_${task.id}`,
          attempt_id: attempt.attempt_id,
          run_id: ctx.run_id,
          task_id: task.id,
          sandbox_mode: ctx.config.execution_sandbox_mode || "path_check",
          preserve_failed_worktree: ctx.config.preserve_failed_worktree,
          worktree_retention_minutes: ctx.config.worktree_retention_minutes,
        });

        // 记录到外层变量，确保 catch/ownership 路径可访问
        worktreePathForCleanup = proxyPrep.worktree_path;
        worktreeBranchForCleanup = proxyPrep.worktree_branch;
        proxyForCleanup = proxy;

        // 调用 Worker — 通过 WorkerExecutionController（带超时/沙箱/能力校验）
        // validated_cwd 和 tool_policy 由 proxy 提供
        const executionResult = await this.workerController.execute({
          contract,
          model_tier: attempt.model_tier,
          project_root: proxyPrep.validated_cwd,
          max_idle_ms: ctx.config.timeout_ms,
          tool_policy: proxyPrep.tool_policy_serialized,
        });
        const workerOutput = executionResult.output;

        // P0-4: worktree 模式下，改动保留在 worktree 中直到 gate 通过才合并
        // 记录 worktree cwd 供 gate 使用（gate 将在 worktree 目录中执行命令）
        const effectiveCwd = proxyPrep.worktree_path || ctx.project.root_path;
        // 临时覆盖 ctx.project.root_path 让 gate evaluator 在正确目录执行
        const originalRootPath = ctx.project.root_path;
        if (proxyPrep.worktree_path) {
          ctx.project.root_path = proxyPrep.worktree_path;
        }

        // ExecutionProxy: 后置 attestation（真实执行数据生成 attestation）
        const { attestation } = proxy.finalizeExecution(
          {
            model_tier: currentTier,
            project_root: ctx.project.root_path,
            sandbox_paths: task.allowed_paths,
            denied_tools: ["TaskStop", "EnterWorktree"],
            worker_id: `worker_${task.id}`,
            attempt_id: attempt.attempt_id,
          },
          workerOutput,
          proxyPrep.started_at,
          proxyPrep.tool_policy_enforced,
          proxyPrep.baseline_commit,
          proxyPrep.validated_cwd, // P0-4 修正: 传入实际执行目录
        );

        // 收集 attestation 到 ctx 供 finalize 阶段直接使用（不再事后重建）
        if (!(ctx as any)._collectedAttestations) (ctx as any)._collectedAttestations = [];
        (ctx as any)._collectedAttestations.push(attestation);

        // 记录 attestation 到审计（attestation 成为 durable truth）
        emitAudit(ctx, "worker_completed", {
          attestation_model: attestation.actual_model,
          attestation_outcome: attestation.execution_outcome,
          sandbox_violations: attestation.sandbox_violations,
          modified_paths: attestation.modified_paths,
          tool_policy_enforced: attestation.tool_policy_enforced,
          context_occupancy: contextPack.occupancy_ratio,
          context_compaction: contextPack.compaction_policy,
        }, task.id, attempt.attempt_id);

        // 检测 worker 是否真实执行成功
        if (workerOutput.status === "failed" || workerOutput.status === "blocked") {
          ctx.project.root_path = originalRootPath; // 恢复 root_path
          if (proxyPrep.worktree_path) proxy.cleanupWorktree(originalRootPath, proxyPrep.worktree_path, proxyPrep.worktree_branch);
          transitionAttemptStatus(attempt, "failed", `Worker 返回 ${workerOutput.status}: ${workerOutput.summary}`);
          attempt.failure_class = "transient_tool_failure";
          attempt.failure_detail = workerOutput.summary;
          lastFailureClass = attempt.failure_class;
          execution.completed_attempts[task.id] = [...(execution.completed_attempts[task.id] || []), attempt];
          emitAudit(ctx, "worker_failed", { failure_class: attempt.failure_class, status: workerOutput.status }, task.id, attempt.attempt_id);
          markSkillFailed(`Worker 返回 ${workerOutput.status}: ${workerOutput.summary}`);
          continue;
        }
        if (workerOutput.status === "warning" && workerOutput.modified_paths.length === 0) {
          ctx.project.root_path = originalRootPath; // 恢复 root_path
          if (proxyPrep.worktree_path) proxy.cleanupWorktree(originalRootPath, proxyPrep.worktree_path, proxyPrep.worktree_branch);
          transitionAttemptStatus(attempt, "failed", `Worker 降级执行无产出: ${workerOutput.summary}`);
          attempt.failure_class = "unsupported_capability";
          attempt.failure_detail = workerOutput.summary;
          lastFailureClass = attempt.failure_class;
          execution.completed_attempts[task.id] = [...(execution.completed_attempts[task.id] || []), attempt];
          emitAudit(ctx, "worker_failed", { failure_class: attempt.failure_class, status: "warning_no_output" }, task.id, attempt.attempt_id);
          markSkillFailed(`Worker 降级无产出: ${workerOutput.summary}`);
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
            // 恢复 root_path 和清理 worktree
            ctx.project.root_path = originalRootPath;
            if (proxyPrep.worktree_path) {
              proxy.cleanupWorktree(originalRootPath, proxyPrep.worktree_path, proxyPrep.worktree_branch);
            }
            transitionAttemptStatus(attempt, "failed", `所有权违规: ${violations.map((v) => v.message).join("; ")}`);
            attempt.failure_class = "ownership_conflict";
            lastFailureClass = attempt.failure_class;

            for (const v of violations) {
              emitAudit(ctx, "ownership_violated", { path: v.path, message: v.message }, task.id);
            }

            execution.completed_attempts[task.id] = [
              ...(execution.completed_attempts[task.id] || []), attempt
            ];
            markSkillFailed(`所有权违规: ${violations.map((v: any) => v.message).join("; ")}`);
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

          // P0-4: gate 失败 — 不合并 worktree 改动到主仓，只清理
          ctx.project.root_path = originalRootPath;
          if (proxyPrep.worktree_path) {
            proxy.cleanupWorktree(originalRootPath, proxyPrep.worktree_path, proxyPrep.worktree_branch);          }

          markSkillFailed("Gate 验证阻断");
          // 模型升级由下一次循环顶部的动态路由自动处理（retry_count 增加 → tier 提升）
          continue;
        }

        // P0-4: worktree 合并必须在 attempt 标为 succeeded 之前执行
        // 此时 attempt 仍在 post_check 态，迁移到 failed 合法
        ctx.project.root_path = originalRootPath;
        if (proxyPrep.worktree_path && proxyPrep.worktree_branch) {
          const mergeResult = proxy.mergeWorktreeChanges(
            originalRootPath,
            proxyPrep.worktree_path,
            proxyPrep.worktree_branch,
            {
              preserve_failed_worktree: ctx.config.preserve_failed_worktree,
              attempt_id: attempt.attempt_id,
              run_id: ctx.run_id,
              task_id: task.id,
            },
          );
          if (!mergeResult.merged) {
            // 合并失败 — attempt 从 post_check → failed（合法迁移）
            transitionAttemptStatus(attempt, "failed", "Worktree 合并失败：cherry-pick 冲突或脏仓状态");
            attempt.failure_class = "ownership_conflict";
            attempt.failure_detail = `worktree merge failed: ${mergeResult.failure_reason || proxyPrep.worktree_path}`;
            lastFailureClass = attempt.failure_class;

            emitAudit(ctx, "worker_failed", {
              failure_class: "ownership_conflict",
              reason: "worktree_merge_failed_post_gate",
              worktree_path: proxyPrep.worktree_path,
              worktree_branch: proxyPrep.worktree_branch,
              action: ctx.config.preserve_failed_worktree ? "worktree_preserved_for_manual_recovery" : "recovery_artifact_exported",
              recovery_patch_path: mergeResult.recovery_patch_path,
              recovery_metadata_path: mergeResult.recovery_metadata_path,
            }, task.id, attempt.attempt_id);

            execution.completed_attempts[task.id] = [
              ...(execution.completed_attempts[task.id] || []), attempt
            ];
            if (!ctx.config.preserve_failed_worktree) {
              proxy.cleanupWorktree(originalRootPath, proxyPrep.worktree_path, proxyPrep.worktree_branch);
            }
            markSkillFailed(`Worktree 合并失败: ${mergeResult.failure_reason || "cherry-pick conflict"}`);
            continue; // 进入重试循环
          } else {
            // 合并成功才清理 worktree 和临时分支
            proxy.cleanupWorktree(originalRootPath, proxyPrep.worktree_path, proxyPrep.worktree_branch);
          }
        }

        // 成功 — worktree 合并已完成（或非 worktree 模式）
        transitionAttemptStatus(attempt, "succeeded", "执行成功");
        emitAudit(ctx, "worker_completed", {
          tokens_used: workerOutput.tokens_used,
          modified_files: workerOutput.modified_paths.length,
        }, task.id, attempt.attempt_id);

        // Skill lifecycle: 标记 skill_completed
        if (skillInvocation) {
          skillInvocation.status = "completed";
          skillInvocation.completed_at = new Date().toISOString();
          emitAudit(ctx, "skill_completed", {
            selected_skill_id: skillInvocation.selected_skill_id,
            phase: skillInvocation.phase,
          }, task.id, attempt.attempt_id);
        }

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
        // 异常路径：恢复 root_path 和清理 worktree（使用提升到外层的变量）
        ctx.project.root_path = savedRootPath;
        if (worktreePathForCleanup && proxyForCleanup) {
          proxyForCleanup.cleanupWorktree(savedRootPath, worktreePathForCleanup, worktreeBranchForCleanup);
        }
        // 仅当 attempt 尚未处于终态时才迁移（避免 succeeded→failed 非法迁移）
        const terminalStates = ["succeeded", "failed", "cancelled", "timed_out"];
        if (!terminalStates.includes(attempt.status)) {
          transitionAttemptStatus(attempt, "failed", `执行错误: ${error instanceof Error ? error.message : String(error)}`);
        }
        attempt.failure_class = attempt.failure_class || "transient_tool_failure";
        attempt.failure_detail = error instanceof Error ? error.message : String(error);
        lastFailureClass = attempt.failure_class;

        emitAudit(ctx, "worker_failed", {
          failure_class: attempt.failure_class,
          error: attempt.failure_detail,
        }, task.id, attempt.attempt_id);

        execution.completed_attempts[task.id] = [
          ...(execution.completed_attempts[task.id] || []), attempt
        ];
        markSkillFailed(`执行异常: ${attempt.failure_detail}`);
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
    // Finding 2 修正: 聚合所有 attempt（含失败）的 workerOutput，确保安全 gate 不遗漏
    const allModifiedPaths: string[] = [];
    const allArtifacts: string[] = [];
    let totalTokens = 0;
    let maxDuration = 0;
    for (const attempts of Object.values(execution.completed_attempts)) {
      for (const att of attempts) {
        // 安全检查需要覆盖所有 attempt（含失败的），防止敏感文件写入逃逸
        allModifiedPaths.push(...att.modified_files);
        if (att.status === "succeeded") {
          allArtifacts.push(...att.artifacts);
          totalTokens += att.tokens_used;
          maxDuration = Math.max(maxDuration, att.duration_ms || 0);
        }
      }
    }
    const aggregatedWorkerOutput = allModifiedPaths.length > 0 ? {
      status: "ok" as const,
      summary: `Run 级聚合: ${allModifiedPaths.length} 个文件修改`,
      modified_paths: [...new Set(allModifiedPaths)],
      artifacts: [...new Set(allArtifacts)],
      tokens_used: totalTokens,
      duration_ms: maxDuration,
      actual_tool_calls: [] as Array<{ name: string; args_hash: string }>,
      exit_code: 0,
    } : undefined;

    const runGates = await this.gateSystem.evaluate(
      { ctx, plan, level: "run", workerOutput: aggregatedWorkerOutput },
      ctx.config.enabled_gates
    );

    // 收集 run-level gate 结果
    ctx.collectedGateResults.push(...runGates);

    // 使用 classification 路径判定阻断
    if (this.gateSystem.hasBlockingFailure(runGates)) {
      const classified = this.gateSystem.classifyResults(runGates);
      transitionRunStatus(execution, "blocked",
        `Hard gate 阻断: ${classified.blocking_failures.map(g => g.gate_type).join(", ")}`);
      for (const g of classified.blocking_failures) {
        emitAudit(ctx, "gate_blocked", { gate_type: g.gate_type, level: "run", strength: "hard" });
      }
      return;
    }

    // 审计全部结果（含 signal 警告）
    for (const gate of runGates) {
      const strength = classifyGate(gate.gate_type).strength;
      emitAudit(ctx, gate.passed ? "gate_passed" : "gate_blocked",
        { gate_type: gate.gate_type, level: "run", strength, signal_only: strength === "signal" });
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

    if ((ctx.config.execution_sandbox_mode || "path_check") === "worktree") {
      const mergeTarget = inspectMergeTargetCleanliness(ctx.project.root_path);
      results.push({
        check_type: "workspace",
        passed: mergeTarget.clean,
        message: mergeTarget.clean
          ? "worktree merge target is clean"
          : `worktree merge target blocked: ${mergeTarget.issues.join("; ")}`,
        details: { issues: mergeTarget.issues },
      });
    }

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

  private getAvailableFiles(ctx: ExecutionContext & { currentTask?: any }): FileInfo[] {
    // 加载真实证据文件
    const { loadEvidenceFiles } = require("../session/evidence-loader");
    const task = ctx.currentTask;
    if (!task) return [];

    return loadEvidenceFiles(task, {
      project_root: ctx.project.root_path,
      max_files_per_task: 50,
      max_file_size_kb: 500,
    });
  }

  private determineFinalStatus(execution: RunExecution, plan?: RunPlan): RunStatus {
    // blocked 状态优先级最高，不能被覆盖
    if (execution.status === "blocked") return "blocked";

    // 基于 plan.task_graph.tasks 全集判定（而非仅 completed_attempts）
    const allAttempts = Object.values(execution.completed_attempts).flat();
    const attemptedTaskIds = new Set(allAttempts.map((a) => a.task_id));

    // 获取全部计划任务 ID
    const allTaskIds = plan
      ? new Set(plan.task_graph.tasks.map((t) => t.id))
      : attemptedTaskIds;

    // 检查是否有未尝试的任务
    const hasSkippedTasks = [...allTaskIds].some(id => !attemptedTaskIds.has(id));

    let allSucceeded = true;
    let anySucceeded = false;

    for (const taskId of attemptedTaskIds) {
      const taskAttempts = allAttempts.filter((a) => a.task_id === taskId);
      const succeeded = taskAttempts.some((a) => a.status === "succeeded");
      if (succeeded) {
        anySucceeded = true;
      } else {
        allSucceeded = false;
      }
    }

    // 有 skipped tasks 时，不能返回 succeeded
    if (hasSkippedTasks) allSucceeded = false;

    if (allSucceeded && attemptedTaskIds.size > 0 && !hasSkippedTasks) return "succeeded";
    if (anySucceeded) return "partially_failed";
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

    // Finalize — 与 normal path 使用同一套终态判定逻辑
    execution.cost_ledger = ctx.costLedger;
    const finalStatus = this.determineFinalStatus(execution, plan);
    if (execution.status !== finalStatus) {
      transitionRunStatus(execution, finalStatus, "恢复执行完成");
    }
    const result = this.finalizeRun(ctx, execution, plan);
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

  /**
   * 重试指定 run 中的失败 task
   */
  async retryTask(runId: string, taskId: string, retriedBy?: string): Promise<RunResult> {
    if (retriedBy) this.requirePermission(retriedBy, "run.retry");

    // 1. 加载 execution 和 plan
    const execution = await this.runStore.getExecution(runId);
    if (!execution) throw new Error(`Run ${runId} 不存在`);

    // 2. 校验 run 状态：必须为 failed 或 partially_failed
    if (execution.status !== "failed" && execution.status !== "partially_failed") {
      throw new Error(`Run ${runId} 当前状态 ${execution.status} 不允许重试，需要 failed 或 partially_failed`);
    }

    // 查找 plan (通过 audit trail)
    const auditEvents = await this.auditTrail.query({ run_id: runId });
    const plannedEvent = auditEvents.find((e) => e.type === "run_planned");
    const planId = (plannedEvent?.payload as Record<string, unknown>)?.plan_id as string | undefined;
    const plan = planId ? await this.runStore.getPlan(planId) : undefined;
    if (!plan) throw new Error(`无法找到 Run ${runId} 的执行计划`);

    // 3. 校验 task 存在
    const task = plan.task_graph.tasks.find(t => t.id === taskId);
    if (!task) throw new Error(`Task ${taskId} 不存在于 Run ${runId} 的任务图中`);

    // 4. 校验 task 最近 attempt 为 failed
    const taskAttempts = execution.completed_attempts[taskId] || [];
    if (taskAttempts.length === 0) {
      throw new Error(`Task ${taskId} 没有历史执行记录`);
    }
    const lastAttempt = taskAttempts[taskAttempts.length - 1];
    if (lastAttempt.status === "succeeded") {
      throw new Error(`Task ${taskId} 已成功，不需要重试`);
    }

    // 5. 下游安全检查：如果下游 task 有成功 attempt，拒绝重试
    const downstreamTaskIds = plan.task_graph.edges
      .filter(e => e.from === taskId)
      .map(e => e.to);
    for (const dsId of downstreamTaskIds) {
      const dsAttempts = execution.completed_attempts[dsId] || [];
      if (dsAttempts.some(a => a.status === "succeeded")) {
        throw new Error(`下游 Task ${dsId} 已成功，重试 ${taskId} 可能导致不一致`);
      }
    }

    // 6. 重置 run 状态为 running
    transitionRunStatus(execution, "running", `重试 task ${taskId}` + (retriedBy ? ` (by ${retriedBy})` : ""));
    await this.runStore.saveExecution(execution);

    // 7. 重建 execution context
    const requestId = (plannedEvent?.payload as Record<string, unknown>)?.request_id as string | undefined
      || (auditEvents.find(e => e.type === "run_created")?.payload as Record<string, unknown>)?.request_id as string | undefined;
    const originalRequest = requestId ? await this.runStore.getRequest(requestId) : undefined;
    const config = originalRequest
      ? { ...DEFAULT_RUN_CONFIG, ...originalRequest.config }
      : { ...DEFAULT_RUN_CONFIG };

    const ctx: ExecutionContext = {
      run_id: runId,
      batch_id: execution.batch_id,
      actor: originalRequest?.actor || { id: retriedBy || "system", type: "user", name: retriedBy || "system", roles: [] },
      project: originalRequest?.project || { root_path: ".", known_modules: [], scope: {} },
      config,
      eventBus: this.eventBus,
      costLedger: execution.cost_ledger,
      policyEngine: this.policyEngine,
      ownershipPlan: plan.ownership_plan,
      auditLog: [],
      collectedGateResults: [],
    };

    emitAudit(ctx, "task_retried", { task_id: taskId, retried_by: retriedBy || "system" });

    // 8. 以 escalated tier 重新执行该 task
    try {
      await this.executeTask(ctx, execution, task, plan.ownership_plan, plan);
    } catch {
      // task 执行失败
    }

    // 9. 重新判定终态
    execution.cost_ledger = ctx.costLedger;
    const finalStatus = this.determineFinalStatus(execution, plan);
    if (execution.status !== finalStatus) {
      transitionRunStatus(execution, finalStatus, "重试完成");
    }

    const result = this.finalizeRun(ctx, execution, plan);
    result.final_status = execution.status;

    await this.runStore.saveResult(result);
    await this.auditTrail.recordBatch(ctx.auditLog);
    await this.runStore.saveExecution(execution);

    return result;
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
        selected_skill_id: latest.selected_skill_id,
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
    // timeline from status_history + skill events from audit
    const timeline: import("../server/control-plane").TimelineEvent[] = execution.status_history.map((h) => ({
      timestamp: h.timestamp,
      type: h.to,
      message: h.reason || "",
    }));

    // 合并 audit 中的 skill_* 事件到 timeline
    const skillAuditTypes = ["skill_candidates_resolved", "skill_selected", "skill_injected", "skill_completed", "skill_failed"];
    const skillAuditEvents = auditEvents.filter(e => skillAuditTypes.includes(e.type));
    for (const se of skillAuditEvents) {
      timeline.push({
        timestamp: se.timestamp,
        type: se.type,
        task_id: se.task_id,
        message: se.type === "skill_selected"
          ? `Skill ${(se.payload as any).selected_skill_id} 选中 (${(se.payload as any).selection_reason || (se.payload as any).run_phase || ""})`
          : se.type === "skill_injected"
          ? `Skill ${(se.payload as any).selected_skill_id} 协议注入`
          : se.type === "skill_completed"
          ? `Skill ${(se.payload as any).selected_skill_id} 完成`
          : se.type === "skill_failed"
          ? `Skill ${(se.payload as any).selected_skill_id} 失败`
          : `Skill 候选: ${(se.payload as any).candidate_count} 个`,
      });
    }

    // 按时间戳排序
    timeline.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

    // skill_events 聚合
    const skillEvents: import("../server/control-plane").SkillEventView[] = skillAuditEvents.map(se => ({
      timestamp: se.timestamp,
      type: se.type,
      skill_id: (se.payload as any).selected_skill_id || (se.payload as any).candidate_skill_ids?.[0] || "",
      phase: (se.payload as any).run_phase || (se.payload as any).phase,
      task_id: se.task_id,
      message: JSON.stringify(se.payload),
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
      skill_events: skillEvents.length > 0 ? skillEvents : undefined,
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
      type: actorId === "control-plane" ? "system" : "user",
      name: actorId,
      roles: actorId === "control-plane" ? ["admin"] : [],
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
   * 在 run 的宏观阶段入口发射 skill 选择和注入事件。
   * 返回 SkillInvocationRecord 供阶段结束后调用 completeRunPhaseSkill。
   */
  private emitRunPhaseSkillEvent(
    ctx: ExecutionContext,
    phase: string,
    execution: RunExecution
  ): import("../capabilities/capability-registry").SkillInvocationRecord | undefined {
    if (!this.skillRegistry) return undefined;

    const matches = this.skillRegistry.resolve({ phase });
    if (matches.length === 0) return undefined;

    emitAudit(ctx, "skill_candidates_resolved", {
      run_phase: phase,
      candidate_count: matches.length,
      candidate_skill_ids: matches.map(m => m.skill_id),
    });

    const selected = this.skillRegistry.select(matches);
    if (!selected) return undefined;

    emitAudit(ctx, "skill_selected", {
      run_phase: phase,
      selected_skill_id: selected.skill_id,
      selection_reason: selected.selection_reason,
      source: selected.source,
      version: selected.version,
    });

    // 构造 invocation record
    const invocation: import("../capabilities/capability-registry").SkillInvocationRecord = {
      run_id: ctx.run_id,
      task_id: `run_phase_${phase}`,
      attempt_id: "",
      phase,
      selected_skill_id: selected.skill_id,
      injected_at: new Date().toISOString(),
      status: "injected",
    };

    // 发射 skill_injected 事件
    const manifest = this.skillRegistry.get(selected.skill_id);
    const protocolDigest = manifest?.protocol_content
      ? manifest.protocol_content.slice(0, 100)
      : manifest?.description?.slice(0, 100);
    emitAudit(ctx, "skill_injected", {
      run_phase: phase,
      selected_skill_id: selected.skill_id,
      protocol_digest: protocolDigest,
      has_protocol_content: !!manifest?.protocol_content,
    });

    // 记录到 execution
    if (!execution.skill_invocations) {
      execution.skill_invocations = [];
    }
    execution.skill_invocations.push(invocation);

    return invocation;
  }

  /**
   * 标记 run 级阶段 skill 完成或失败
   */
  private completeRunPhaseSkill(
    ctx: ExecutionContext,
    invocation: import("../capabilities/capability-registry").SkillInvocationRecord | undefined,
    success: boolean,
    failureReason?: string
  ): void {
    if (!invocation) return;

    invocation.completed_at = new Date().toISOString();
    if (success) {
      invocation.status = "completed";
      emitAudit(ctx, "skill_completed", {
        run_phase: invocation.phase,
        selected_skill_id: invocation.selected_skill_id,
      });
    } else {
      invocation.status = "failed";
      invocation.evidence = { failure_reason: failureReason };
      emitAudit(ctx, "skill_failed", {
        run_phase: invocation.phase,
        selected_skill_id: invocation.selected_skill_id,
        failure_reason: failureReason,
      });
    }
  }

  /**
   * 执行 Hook 阶段：调用 HookRegistry 中注册的 hooks。
   * Hook 返回的 effects 会被收集并影响主链行为（Workstream G effect 化）。
   */
  private async executeHookPhase(
    phase: import("../capabilities/capability-registry").HookPhase,
    ctx: ExecutionContext
  ): Promise<import("../capabilities/capability-registry").HookEffect[]> {
    if (!this.hookRegistry) return [];
    try {
      const results = await this.hookRegistry.executePhase(phase, {
        run_id: ctx.run_id,
        data: { timestamp: new Date().toISOString() },
      });

      // 收集所有 hook 产生的 effects
      const effects: import("../capabilities/capability-registry").HookEffect[] = [];
      for (const result of results) {
        if (result.effects) {
          effects.push(...result.effects);
        }
      }

      // 如果有 effects，记录到审计
      if (effects.length > 0) {
        emitAudit(ctx, "run_planned", {
          phase: `hook_${phase}`,
          effects_count: effects.length,
          effect_types: effects.map(e => e.type),
        });
      }

      return effects;
    } catch (err) {
      emitAudit(ctx, "run_failed", {
        phase: `hook_${phase}`,
        error: err instanceof Error ? err.message : String(err),
      });
      return [];
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

    // 注入 Skill 协议约束（skill_protocol_summary 是 runtime 确定性注入的）
    if (contract.skill_protocol_summary) {
      promptParts.push(`\n## 协议约束\n${contract.skill_protocol_summary}`);
    }

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
            ...(contract.selected_skill_id ? { PARALLEL_HARNESS_SKILL_ID: contract.selected_skill_id } : {}),
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
          actual_tool_calls: [],
          exit_code: exitCode,
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
        actual_tool_calls: [],
        exit_code: 0,
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
        actual_tool_calls: [],
        exit_code: -1,
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
  skillRegistry?: import("../capabilities/capability-registry").SkillRegistry;
  /** 持久化数据目录，设置后默认使用 FileStore */
  dataDir?: string;
}
