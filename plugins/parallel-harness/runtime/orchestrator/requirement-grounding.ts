import type { RunRequest } from "../schemas/ga-schemas";

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
    delivery_artifacts: ["code", "tests"],
    required_approvals: ambiguityItems.length > 2 ? ["tech_lead"] : [],
  };
}
