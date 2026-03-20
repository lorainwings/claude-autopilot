/**
 * parallel-harness: Governance — RBAC / Approval / Human-in-the-loop
 *
 * 商业化必须的治理平面。
 * 定义谁可以做什么，什么动作需要审批，如何接收人工反馈。
 */

import type {
  ActorIdentity,
  ScopeContext,
  ApprovalRequest,
  ApprovalRecord,
} from "../schemas/ga-schemas";
import { generateId } from "../schemas/ga-schemas";

// ============================================================
// RBAC
// ============================================================

export type Permission =
  | "run.create"
  | "run.cancel"
  | "run.retry"
  | "run.view"
  | "task.approve_model_upgrade"
  | "task.approve_sensitive_write"
  | "task.approve_autofix_push"
  | "gate.override"
  | "policy.manage"
  | "config.manage"
  | "audit.view"
  | "audit.export";

export interface Role {
  name: string;
  permissions: Permission[];
  scope?: ScopeContext;
}

export const BUILT_IN_ROLES: Role[] = [
  {
    name: "admin",
    permissions: [
      "run.create", "run.cancel", "run.retry", "run.view",
      "task.approve_model_upgrade", "task.approve_sensitive_write", "task.approve_autofix_push",
      "gate.override", "policy.manage", "config.manage",
      "audit.view", "audit.export",
    ],
  },
  {
    name: "developer",
    permissions: [
      "run.create", "run.cancel", "run.retry", "run.view",
      "audit.view",
    ],
  },
  {
    name: "reviewer",
    permissions: [
      "run.view",
      "task.approve_model_upgrade", "task.approve_sensitive_write",
      "gate.override",
      "audit.view",
    ],
  },
  {
    name: "viewer",
    permissions: ["run.view", "audit.view"],
  },
];

export class RBACEngine {
  private roles: Map<string, Role> = new Map();
  private actorRoles: Map<string, string[]> = new Map();

  constructor() {
    for (const role of BUILT_IN_ROLES) {
      this.roles.set(role.name, role);
    }
  }

  addRole(role: Role): void {
    this.roles.set(role.name, role);
  }

  assignRole(actorId: string, roleName: string): void {
    const roles = this.actorRoles.get(actorId) || [];
    if (!roles.includes(roleName)) {
      roles.push(roleName);
      this.actorRoles.set(actorId, roles);
    }
  }

  revokeRole(actorId: string, roleName: string): void {
    const roles = this.actorRoles.get(actorId) || [];
    this.actorRoles.set(actorId, roles.filter((r) => r !== roleName));
  }

  hasPermission(actor: ActorIdentity, permission: Permission): boolean {
    // System 和 CI actors 有所有权限
    if (actor.type === "system" || actor.type === "ci") return true;

    // 检查 actor 的角色
    const assignedRoles = [
      ...(this.actorRoles.get(actor.id) || []),
      ...actor.roles,
    ];

    for (const roleName of assignedRoles) {
      const role = this.roles.get(roleName);
      if (role?.permissions.includes(permission)) return true;
    }

    return false;
  }

  getActorPermissions(actor: ActorIdentity): Permission[] {
    const permissions = new Set<Permission>();
    const assignedRoles = [
      ...(this.actorRoles.get(actor.id) || []),
      ...actor.roles,
    ];

    for (const roleName of assignedRoles) {
      const role = this.roles.get(roleName);
      if (role) {
        for (const perm of role.permissions) {
          permissions.add(perm);
        }
      }
    }

    return [...permissions];
  }
}

// ============================================================
// Approval Workflow
// ============================================================

export class ApprovalWorkflow {
  private pendingApprovals: Map<string, ApprovalRequest> = new Map();
  private completedApprovals: ApprovalRecord[] = [];
  private autoApproveRules: string[] = [];

  constructor(autoApproveRules: string[] = []) {
    this.autoApproveRules = autoApproveRules;
  }

  requestApproval(request: Omit<ApprovalRequest, "approval_id" | "status" | "requested_at">): ApprovalRequest {
    const approval: ApprovalRequest = {
      ...request,
      approval_id: generateId("appr"),
      status: "pending",
      requested_at: new Date().toISOString(),
    };

    // 自动审批检查
    if (this.shouldAutoApprove(approval)) {
      const record: ApprovalRecord = {
        ...approval,
        status: "approved",
        decision: "approved",
        decided_at: new Date().toISOString(),
        decided_by: "auto",
        comment: "自动审批",
      };
      this.completedApprovals.push(record);
      return { ...approval, status: "approved" };
    }

    this.pendingApprovals.set(approval.approval_id, approval);
    return approval;
  }

  decide(approvalId: string, decision: "approved" | "denied", decidedBy: string, comment?: string): ApprovalRecord | undefined {
    const approval = this.pendingApprovals.get(approvalId);
    if (!approval) return undefined;

    const record: ApprovalRecord = {
      ...approval,
      status: decision,
      decision,
      decided_at: new Date().toISOString(),
      decided_by: decidedBy,
      comment,
    };

    this.pendingApprovals.delete(approvalId);
    this.completedApprovals.push(record);
    return record;
  }

  /**
   * 从持久化存储恢复 pending approval 到内存，支持跨进程恢复
   */
  rehydrate(approval: ApprovalRequest): void {
    if (approval.status === "pending" && !this.pendingApprovals.has(approval.approval_id)) {
      this.pendingApprovals.set(approval.approval_id, approval);
    }
  }

  getPending(): ApprovalRequest[] {
    return [...this.pendingApprovals.values()];
  }

  getHistory(): ApprovalRecord[] {
    return [...this.completedApprovals];
  }

  private shouldAutoApprove(approval: ApprovalRequest): boolean {
    return this.autoApproveRules.some((rule) => {
      if (rule === "all") return true;
      if (rule === approval.action) return true;
      return approval.triggered_rules.includes(rule);
    });
  }
}

// ============================================================
// Human-in-the-loop
// ============================================================

export interface HumanFeedbackRequest {
  run_id: string;
  task_id?: string;
  question: string;
  options?: string[];
  context: string;
  urgency: "low" | "medium" | "high";
}

export interface HumanFeedbackResponse {
  feedback_id: string;
  run_id: string;
  task_id?: string;
  response: string;
  actor: ActorIdentity;
  timestamp: string;
}

export class HumanInteractionManager {
  private pendingRequests: Map<string, HumanFeedbackRequest & { request_id: string }> = new Map();
  private responses: HumanFeedbackResponse[] = [];

  requestFeedback(request: HumanFeedbackRequest): string {
    const requestId = generateId("hfb");
    this.pendingRequests.set(requestId, { ...request, request_id: requestId });
    return requestId;
  }

  submitFeedback(requestId: string, response: string, actor: ActorIdentity): HumanFeedbackResponse | undefined {
    const request = this.pendingRequests.get(requestId);
    if (!request) return undefined;

    const feedback: HumanFeedbackResponse = {
      feedback_id: generateId("fb"),
      run_id: request.run_id,
      task_id: request.task_id,
      response,
      actor,
      timestamp: new Date().toISOString(),
    };

    this.pendingRequests.delete(requestId);
    this.responses.push(feedback);
    return feedback;
  }

  getPendingRequests(): (HumanFeedbackRequest & { request_id: string })[] {
    return [...this.pendingRequests.values()];
  }

  getResponses(runId?: string): HumanFeedbackResponse[] {
    if (runId) return this.responses.filter((r) => r.run_id === runId);
    return [...this.responses];
  }
}
