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
  if (words.some(w => ["maybe", "perhaps", "possibly", "might"].includes(w))) {
    ambiguityItems.push("请求包含不确定性词汇");
  }
  if (intent.length < 20) {
    ambiguityItems.push("需求描述过于简短");
  }

  const acceptanceMatrix: RequirementGrounding["acceptance_matrix"] = [
    {
      category: "functional",
      criterion: "实现符合需求描述的核心功能",
      blocking: true,
    },
  ];

  if (words.some(w => ["test", "测试"].includes(w))) {
    acceptanceMatrix.push({
      category: "regression",
      criterion: "新增或更新相关测试",
      blocking: true,
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
