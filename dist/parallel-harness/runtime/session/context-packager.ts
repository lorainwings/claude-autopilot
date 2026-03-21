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
 */
export function packContext(
  task: TaskNode,
  availableFiles: FileInfo[],
  config: Partial<PackagerConfig> = {}
): ContextPack {
  const cfg = { ...DEFAULT_CONFIG, ...config };

  // 1. 筛选相关文件
  const relevantFiles = selectRelevantFiles(task, availableFiles);

  // 2. 提取代码片段
  const snippets = extractSnippets(
    task,
    relevantFiles,
    cfg.max_lines_per_file,
    cfg.max_snippets
  );

  // 3. 估算 token 使用量
  const estimatedTokens = estimateTokenUsage(task, relevantFiles, snippets);

  // 4. 如果超预算，压缩
  let finalSnippets = snippets;
  let budget = cfg.default_budget;

  if (estimatedTokens > budget.max_input_tokens && budget.auto_summarize_on_overflow) {
    finalSnippets = compressSnippets(snippets, budget.max_input_tokens);
  }

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

function selectRelevantFiles(
  task: TaskNode,
  files: FileInfo[]
): FileInfo[] {
  return files.filter((f) => {
    // 在允许路径内
    const isAllowed = task.allowed_paths.some(
      (p) => f.path.startsWith(p) || f.path === p
    );

    // 不在禁止路径内
    const isForbidden = task.forbidden_paths.some(
      (p) => f.path.startsWith(p) || f.path === p
    );

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
