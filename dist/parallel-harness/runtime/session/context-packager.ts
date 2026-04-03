/**
 * parallel-harness: Context Packager
 *
 * 为每个 worker 打包最小上下文。
 * 核心原则：默认不喂全仓，默认不喂无关历史。
 *
 * 来源设计：
 * - get-shit-done: 最小上下文包
 * - superpowers: 低摩擦能力入口
 *
 * 反向增强：
 * - 超预算自动摘要，不是截断
 */

import type { TaskNode } from "../orchestrator/task-graph";
import type {
  ContextPack,
  ContextBudget,
  CodeSnippet,
  TaskContract,
} from "./context-pack";
import { normalizePath } from "../schemas/ga-schemas";

// ============================================================
// 配置
// ============================================================

export interface PackagerConfig {
  /** 默认 token 预算 */
  default_budget: ContextBudget;

  /** 每个文件最大读取行数 */
  max_lines_per_file: number;

  /** 最大片段数 */
  max_snippets: number;
}

const DEFAULT_CONFIG: PackagerConfig = {
  default_budget: {
    max_input_tokens: 30000,
    max_output_tokens: 8000,
    auto_summarize_on_overflow: true,
  },
  max_lines_per_file: 200,
  max_snippets: 10,
};

// ============================================================
// Context Packager 实现
// ============================================================

/**
 * 为任务打包上下文
 * @param task 任务节点
 * @param availableFiles 可用文件列表
 * @param config 打包配置
 * @param externalBudget 外部传入的 context budget（来自 routeModel）
 * @param retryHint 重试次数提示，非零时跳过前 N 个 snippets
 */
export function packContext(
  task: TaskNode,
  availableFiles: FileInfo[],
  config: Partial<PackagerConfig> = {},
  externalBudget?: { max_input_tokens: number },
  retryHint?: number,
  repoRoot?: string
): ContextPack {
  const cfg = { ...DEFAULT_CONFIG, ...config };

  // 使用外部 budget 覆盖默认值（context budget 闭环）
  let budget = cfg.default_budget;
  if (externalBudget && externalBudget.max_input_tokens > 0) {
    budget = {
      ...budget,
      max_input_tokens: externalBudget.max_input_tokens,
    };
  }

  const occupancyThreshold = budget.occupancy_threshold ?? 0.8;
  const role = budget.role;

  // 1. 筛选相关文件 + 角色排序
  let relevantFiles = selectRelevantFiles(task, availableFiles, repoRoot);
  if (role) {
    relevantFiles = sortByRole(relevantFiles, role);
  }

  // 2. 提取代码片段
  let snippets = extractSnippets(
    task,
    relevantFiles,
    cfg.max_lines_per_file,
    cfg.max_snippets
  );

  // 2b. retry offset — 跳过前 N 个 snippets 确保重试上下文不同
  const effectiveRetryHint = retryHint ?? 0;
  if (effectiveRetryHint > 0 && snippets.length > effectiveRetryHint) {
    snippets = snippets.slice(effectiveRetryHint);
  }

  // 3. 估算 token 使用量
  const estimatedTokens = estimateTokenUsage(task, relevantFiles, snippets);

  // 4. occupancy 阈值或超预算时压缩
  let finalSnippets = snippets;
  let compactionPolicy: "none" | "summarize" | "truncate" = "none";

  const occupancyBeforeCompact = budget.max_input_tokens > 0
    ? estimatedTokens / budget.max_input_tokens
    : 0;

  if (
    (occupancyBeforeCompact > occupancyThreshold || estimatedTokens > budget.max_input_tokens) &&
    budget.auto_summarize_on_overflow
  ) {
    finalSnippets = compressSnippets(snippets, budget.max_input_tokens);
    compactionPolicy = "truncate";
  }

  // 5. 计算占用率
  const finalTokens = estimateTokenUsage(task, relevantFiles, finalSnippets);
  const occupancyRatio = budget.max_input_tokens > 0
    ? Math.min(finalTokens / budget.max_input_tokens, 1.0)
    : 0;

  return {
    task_summary: buildTaskSummary(task),
    relevant_files: relevantFiles.map((f) => f.path),
    relevant_snippets: finalSnippets,
    constraints: {
      allowed_paths: task.allowed_paths,
      forbidden_paths: task.forbidden_paths,
      interface_contracts: [],
      coding_standards: [],
    },
    test_requirements: task.required_tests,
    budget,
    occupancy_ratio: occupancyRatio,
    loaded_files_count: relevantFiles.length,
    loaded_snippets_count: finalSnippets.length,
    compaction_policy: compactionPolicy,
    retry_hint: effectiveRetryHint > 0 ? effectiveRetryHint : undefined,
  };
}

/**
 * 生成完整的任务契约
 */
export function buildTaskContract(
  task: TaskNode,
  contextPack: ContextPack
): TaskContract {
  return {
    task_id: task.id,
    goal: task.goal,
    dependencies: task.dependencies,
    allowed_paths: task.allowed_paths,
    forbidden_paths: task.forbidden_paths,
    acceptance_criteria: task.acceptance_criteria,
    test_requirements: task.required_tests,
    preferred_model_tier: task.model_tier,
    retry_policy: task.retry_policy,
    verifier_set: task.verifier_set,
    context: contextPack,
  };
}

// ============================================================
// 数据结构
// ============================================================

/** 文件信息 */
export interface FileInfo {
  /** 文件路径 */
  path: string;

  /** 文件内容（可选，大文件只传路径） */
  content?: string;

  /** 文件大小（字节） */
  size: number;

  /** 文件类型 */
  type: string;
}

// ============================================================
// 辅助函数
// ============================================================

/**
 * 按角色排序文件：verifier 优先 test 文件，planner 优先 md/config
 */
function sortByRole(files: FileInfo[], role: "planner" | "author" | "verifier"): FileInfo[] {
  return [...files].sort((a, b) => {
    const scoreA = roleFileScore(a.path, role);
    const scoreB = roleFileScore(b.path, role);
    return scoreB - scoreA;
  });
}

function roleFileScore(path: string, role: "planner" | "author" | "verifier"): number {
  const lower = path.toLowerCase();
  if (role === "verifier") {
    if (lower.includes("test") || lower.includes("spec")) return 10;
    if (lower.endsWith(".ts") || lower.endsWith(".js")) return 5;
    return 1;
  }
  if (role === "planner") {
    if (lower.endsWith(".md") || lower.endsWith(".json") || lower.includes("config")) return 10;
    if (lower.endsWith(".ts")) return 5;
    return 1;
  }
  // author — source first
  if (lower.includes("test") || lower.includes("spec")) return 3;
  if (lower.endsWith(".ts") || lower.endsWith(".js")) return 10;
  return 1;
}

function selectRelevantFiles(
  task: TaskNode,
  files: FileInfo[],
  repoRoot?: string
): FileInfo[] {
  const root = repoRoot || process.cwd();
  return files.filter((f) => {
    // 归一化比较：支持绝对/相对/root 路径
    const isAllowed = task.allowed_paths.length === 0 || task.allowed_paths.some((p) => {
      if (p === "." || p === "./") return true; // repo_root 匹配所有
      const np = normalizePath(p, root);
      const fp = normalizePath(f.path, root);
      return fp.repo_relative.startsWith(np.repo_relative) || fp.repo_relative === np.repo_relative;
    });

    const isForbidden = task.forbidden_paths.some((p) => {
      const np = normalizePath(p, root);
      const fp = normalizePath(f.path, root);
      return fp.repo_relative.startsWith(np.repo_relative) || fp.repo_relative === np.repo_relative;
    });

    return isAllowed && !isForbidden;
  });
}

function extractSnippets(
  task: TaskNode,
  files: FileInfo[],
  maxLinesPerFile: number,
  maxSnippets: number
): CodeSnippet[] {
  const snippets: CodeSnippet[] = [];

  for (const file of files) {
    if (snippets.length >= maxSnippets) break;
    if (!file.content) continue;

    const lines = file.content.split("\n");
    const endLine = Math.min(lines.length, maxLinesPerFile);

    snippets.push({
      file_path: file.path,
      start_line: 1,
      end_line: endLine,
      content: lines.slice(0, endLine).join("\n"),
      relevance: `在任务 ${task.id} 的所有权范围内`,
    });
  }

  return snippets;
}

function estimateTokenUsage(
  task: TaskNode,
  _files: FileInfo[],
  snippets: CodeSnippet[]
): number {
  // 粗略估算：1 token ~= 4 字符
  let totalChars = 0;

  // 任务描述
  totalChars += task.goal.length;
  totalChars += task.acceptance_criteria.join(" ").length;
  totalChars += task.required_tests.join(" ").length;

  // 代码片段
  for (const s of snippets) {
    totalChars += s.content.length;
  }

  return Math.ceil(totalChars / 4);
}

function compressSnippets(
  snippets: CodeSnippet[],
  maxTokens: number
): CodeSnippet[] {
  // 按相关性排序后截取
  const compressed: CodeSnippet[] = [];
  let currentTokens = 0;

  for (const snippet of snippets) {
    const snippetTokens = Math.ceil(snippet.content.length / 4);
    if (currentTokens + snippetTokens > maxTokens * 0.8) {
      // 超预算：只保留前 50 行
      const lines = snippet.content.split("\n").slice(0, 50);
      compressed.push({
        ...snippet,
        content: lines.join("\n") + "\n// ... (已摘要，完整文件请查看源码)",
        end_line: Math.min(snippet.end_line, snippet.start_line + 49),
      });
      break;
    }
    compressed.push(snippet);
    currentTokens += snippetTokens;
  }

  return compressed;
}

function buildTaskSummary(task: TaskNode): string {
  const parts: string[] = [];
  parts.push(`任务: ${task.title}`);
  parts.push(`目标: ${task.goal}`);
  if (task.acceptance_criteria.length > 0) {
    parts.push(`验收标准: ${task.acceptance_criteria.join("; ")}`);
  }
  parts.push(`复杂度: ${task.complexity.level} (${task.complexity.score}/100)`);
  parts.push(`模型 Tier: ${task.model_tier}`);
  return parts.join("\n");
}
