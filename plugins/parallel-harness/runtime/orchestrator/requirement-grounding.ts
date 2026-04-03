import type { RunRequest } from "../schemas/ga-schemas";
import type { TaskNode } from "./task-graph";

export interface RequirementGrounding {
  request_id: string;
  restated_goal: string;
  acceptance_matrix: Array<{
    category: "functional" | "regression" | "security" | "performance" | "documentation";
    criterion: string;
    blocking: boolean;
  }>;
  ambiguity_items: string[];
  assumptions: string[];
  impacted_modules: string[];
  delivery_artifacts: string[];
  required_approvals: string[];
}

export interface StageContract {
  stage_name: string;
  required_artifacts: string[];
  acceptance_criteria: string[];
  blocking_questions: string[];
  verifier_plan: string[];
}

/**
 * 从 acceptance_matrix 提取下沉到 task contract 的验收标准
 */
export function extractGroundingCriteria(
  grounding: RequirementGrounding
): Array<{ category: string; criterion: string; blocking: boolean }> {
  return grounding.acceptance_matrix.map((item) => ({
    category: item.category,
    criterion: item.criterion,
    blocking: item.blocking,
  }));
}

/**
 * 将 grounding 的 delivery_artifacts 映射为报告所需的 artifact 清单
 */
export function getDeliveryArtifactChecklist(
  grounding: RequirementGrounding
): Array<{ artifact: string; required: boolean }> {
  return grounding.delivery_artifacts.map((a) => ({
    artifact: a,
    required: true,
  }));
}

/**
 * 从 task 的 allowed_paths 推导 domain
 */
function deriveDomain(task: TaskNode): string {
  if (task.allowed_paths.length === 0) return "general";
  const firstPath = task.allowed_paths[0].toLowerCase();
  if (firstPath.includes("test") || firstPath.includes("spec")) return "testing";
  if (firstPath.includes("doc") || firstPath.endsWith(".md")) return "documentation";
  if (firstPath.includes("config") || firstPath.includes("env")) return "config";
  // 使用第一个路径的顶层目录作为 domain
  const parts = firstPath.split("/").filter(Boolean);
  return parts[0] || "general";
}

/**
 * 根据意图关键词推导交付产物列表
 */
export function deriveDeliveryArtifacts(intent: string): string[] {
  const lower = intent.toLowerCase();
  const artifacts = new Set<string>(["code"]);

  const patterns: Record<string, string[]> = {
    tests: ["test", "测试", "spec", "覆盖率", "coverage"],
    docs: ["doc", "文档", "readme", "documentation"],
    config: ["config", "配置", "env", "environment", "settings"],
    api: ["api", "endpoint", "接口", "rest", "graphql"],
    migration: ["migration", "迁移", "migrate", "upgrade", "升级"],
    security: ["security", "安全", "auth", "认证", "鉴权", "acl", "rbac"],
  };

  for (const [artifact, keywords] of Object.entries(patterns)) {
    if (keywords.some(k => lower.includes(k))) {
      artifacts.add(artifact);
    }
  }

  // 默认始终包含 tests
  artifacts.add("tests");

  return [...artifacts];
}

/**
 * 从 grounding + tasks 构建阶段合同
 */
export function buildStageContracts(
  grounding: RequirementGrounding,
  tasks: TaskNode[]
): StageContract[] {
  // 按主路径聚合任务为逻辑阶段
  const domainGroups = new Map<string, TaskNode[]>();
  for (const task of tasks) {
    const domain = deriveDomain(task);
    if (!domainGroups.has(domain)) domainGroups.set(domain, []);
    domainGroups.get(domain)!.push(task);
  }

  const contracts: StageContract[] = [];
  for (const [domain, domainTasks] of domainGroups) {
    const requiredArtifacts = deriveDeliveryArtifacts(
      domainTasks.map(t => t.goal).join(" ")
    );

    const acceptanceCriteria = domainTasks.flatMap(t => t.acceptance_criteria);

    // 从 grounding 的 ambiguity_items 提取 blocking questions
    const blockingQuestions = grounding.ambiguity_items.filter(
      (_, i) => i < 3
    );

    // verifier_plan: 根据 domain 生成验证策略
    const verifierPlan: string[] = [];
    if (requiredArtifacts.includes("tests")) {
      verifierPlan.push("run_test_gate");
    }
    if (requiredArtifacts.includes("security")) {
      verifierPlan.push("run_security_gate");
    }
    verifierPlan.push("run_lint_type_gate");
    verifierPlan.push("run_review_gate");

    contracts.push({
      stage_name: domain,
      required_artifacts: requiredArtifacts,
      acceptance_criteria: acceptanceCriteria,
      blocking_questions: blockingQuestions,
      verifier_plan: verifierPlan,
    });
  }

  return contracts;
}

// ============================================================
// P2-1: GroundingBundle + ClarificationLoop
// ============================================================

/** 澄清问题 */
export interface ClarificationQuestion {
  question_id: string;
  question: string;
  category: "scope" | "acceptance" | "constraint" | "dependency" | "rollout";
  priority: "blocking" | "important" | "nice_to_have";
  suggested_answers?: string[];
  answer?: string;
  answered: boolean;
}

/** 需求 Grounding Bundle — 完整的需求理解包 */
export interface GroundingBundle {
  /** 原始意图 */
  raw_intent: string;
  /** 重述的目标 */
  restated_goal: string;
  /** repo-aware 证据引用 */
  evidence_refs: Array<{
    ref_id: string;
    kind: "file" | "symbol" | "test" | "doc" | "config";
    path: string;
    relevance: string;
  }>;
  /** 澄清问题列表 */
  clarification_questions: ClarificationQuestion[];
  /** 阶段特定验收矩阵 */
  stage_acceptance_matrix: Record<string, Array<{
    criterion: string;
    blocking: boolean;
    verification_method: string;
  }>>;
  /** 受影响模块 */
  affected_modules: string[];
  /** 受影响接口 */
  affected_interfaces: string[];
  /** 上线约束 */
  rollout_constraints: string[];
  /** 是否已完成澄清 */
  clarification_complete: boolean;
}

/** 澄清循环 — 管理澄清问题的迭代 */
export class ClarificationLoop {
  private questions: ClarificationQuestion[] = [];
  private maxRounds = 3;
  private currentRound = 0;

  /** 添加澄清问题 */
  addQuestion(question: Omit<ClarificationQuestion, "question_id" | "answered">): void {
    this.questions.push({
      ...question,
      question_id: `cq_${Date.now()}_${this.questions.length}`,
      answered: false,
    });
  }

  /** 回答澄清问题 */
  answerQuestion(questionId: string, answer: string): void {
    const q = this.questions.find(q => q.question_id === questionId);
    if (q) {
      q.answer = answer;
      q.answered = true;
    }
  }

  /** 获取未回答的 blocking 问题 */
  getPendingBlockingQuestions(): ClarificationQuestion[] {
    return this.questions.filter(q => !q.answered && q.priority === "blocking");
  }

  /** 获取所有问题 */
  getAllQuestions(): ClarificationQuestion[] {
    return [...this.questions];
  }

  /** 推进到下一轮 */
  advanceRound(): boolean {
    if (this.currentRound >= this.maxRounds) return false;
    this.currentRound++;
    return true;
  }

  /** 澄清是否完成 */
  isComplete(): boolean {
    return this.getPendingBlockingQuestions().length === 0 || this.currentRound >= this.maxRounds;
  }

  /** 当前轮次 */
  getCurrentRound(): number {
    return this.currentRound;
  }
}

/** 构建 GroundingBundle */
export function buildGroundingBundle(
  intent: string,
  grounding: Omit<RequirementGrounding, "request_id">,
  clarificationLoop: ClarificationLoop,
  repoEvidence?: Array<{ path: string; kind: string; relevance: string }>
): GroundingBundle {
  return {
    raw_intent: intent,
    restated_goal: grounding.restated_goal,
    evidence_refs: (repoEvidence || []).map((e, i) => ({
      ref_id: `gnd_ref_${i}`,
      kind: e.kind as GroundingBundle["evidence_refs"][0]["kind"],
      path: e.path,
      relevance: e.relevance,
    })),
    clarification_questions: clarificationLoop.getAllQuestions(),
    stage_acceptance_matrix: Object.fromEntries(
      grounding.acceptance_matrix.map(item => [
        item.category,
        [{ criterion: item.criterion, blocking: item.blocking, verification_method: "automated" }],
      ])
    ),
    affected_modules: grounding.impacted_modules,
    affected_interfaces: [],
    rollout_constraints: [],
    clarification_complete: clarificationLoop.isComplete(),
  };
}

export function groundRequirement(request: RunRequest): RequirementGrounding {
  const intent = request.intent;
  const words = intent.toLowerCase().split(/\s+/);

  const ambiguityItems: string[] = [];

  // 不确定性词汇检测
  const uncertainWords = ["maybe", "perhaps", "possibly", "might", "could", "或许", "可能", "大概"];
  if (words.some(w => uncertainWords.includes(w))) {
    ambiguityItems.push("请求包含不确定性词汇");
  }

  // 过于简短
  if (intent.length < 20) {
    ambiguityItems.push("需求描述过于简短，可能缺少关键细节");
  }

  // 没有明确动作动词
  const actionVerbs = ["实现", "修复", "添加", "删除", "重构", "优化", "测试", "创建",
    "implement", "fix", "add", "remove", "refactor", "optimize", "test", "create", "update", "build"];
  if (!words.some(w => actionVerbs.includes(w))) {
    ambiguityItems.push("需求缺少明确的动作动词");
  }

  // 构建验收矩阵
  const acceptanceMatrix: RequirementGrounding["acceptance_matrix"] = [
    {
      category: "functional",
      criterion: "实现符合需求描述的核心功能",
      blocking: true,
    },
  ];

  if (words.some(w => ["test", "测试", "tests"].includes(w))) {
    acceptanceMatrix.push({
      category: "regression",
      criterion: "新增或更新相关测试",
      blocking: true,
    });
  }

  if (words.some(w => ["security", "安全", "auth", "认证", "鉴权"].includes(w))) {
    acceptanceMatrix.push({
      category: "security",
      criterion: "通过安全审查",
      blocking: true,
    });
  }

  if (words.some(w => ["perf", "性能", "performance", "优化"].includes(w))) {
    acceptanceMatrix.push({
      category: "performance",
      criterion: "性能指标不低于基线",
      blocking: false,
    });
  }

  // 推断 impacted_modules（基于 intent 关键词）
  const impactedModules: string[] = [];
  const moduleKeywords: Record<string, string[]> = {
    "runtime/engine": ["orchestrator", "runtime", "engine", "编排"],
    "runtime/workers": ["worker", "执行", "execute"],
    "runtime/gates": ["gate", "验证", "verify", "门禁"],
    "runtime/models": ["model", "router", "路由", "模型"],
    "runtime/session": ["context", "session", "上下文", "会话"],
    "runtime/integrations": ["pr", "github", "ci", "集成"],
    "runtime/persistence": ["persist", "store", "持久化", "存储"],
    "runtime/governance": ["rbac", "approval", "审批", "权限"],
  };
  for (const [mod, keywords] of Object.entries(moduleKeywords)) {
    if (words.some(w => keywords.includes(w))) {
      impactedModules.push(mod);
    }
  }

  return {
    request_id: request.request_id,
    restated_goal: intent,
    acceptance_matrix: acceptanceMatrix,
    ambiguity_items: ambiguityItems,
    assumptions: [],
    impacted_modules: impactedModules,
    delivery_artifacts: deriveDeliveryArtifacts(intent),
    required_approvals: ambiguityItems.length > 2 ? ["tech_lead"] : [],
  };
}
