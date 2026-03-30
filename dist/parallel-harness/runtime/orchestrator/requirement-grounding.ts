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

  return {
    request_id: request.request_id,
    restated_goal: intent,
    acceptance_matrix: acceptanceMatrix,
    ambiguity_items: ambiguityItems,
    assumptions: [],
    impacted_modules: [],
    delivery_artifacts: ["code", "tests"],
    required_approvals: ambiguityItems.length > 2 ? ["tech_lead"] : [],
  };
}
