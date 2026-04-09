import type { TaskContract } from "../session/context-pack";

export const PARALLEL_HARNESS_PLUGIN_ID = "parallel-harness";

export interface BuildWorkerPromptOptions {
  pluginId?: string;
}

export interface BuildClaudeCliArgsOptions {
  prompt: string;
  claudeBin?: string;
  pluginRoot?: string;
}

export function resolveClaudeSkillSlashCommand(
  skillId?: string,
  pluginId = PARALLEL_HARNESS_PLUGIN_ID,
): string | undefined {
  if (!skillId) return undefined;
  return `/${pluginId}:${skillId}`;
}

export function buildWorkerPrompt(
  contract: Pick<
    TaskContract,
    | "goal"
    | "acceptance_criteria"
    | "allowed_paths"
    | "forbidden_paths"
    | "test_requirements"
    | "context"
    | "selected_skill_id"
    | "skill_protocol_summary"
  >,
  options: BuildWorkerPromptOptions = {},
): string {
  const pluginId = options.pluginId || PARALLEL_HARNESS_PLUGIN_ID;
  const skillSlash = resolveClaudeSkillSlashCommand(contract.selected_skill_id, pluginId);

  const promptParts = [
    skillSlash || "",
    `任务: ${contract.goal}`,
    `验收标准: ${contract.acceptance_criteria.join("; ")}`,
    `允许修改的文件: ${contract.allowed_paths.join(", ")}`,
    `禁止修改的文件: ${contract.forbidden_paths.join(", ")}`,
    contract.test_requirements.length > 0
      ? `测试要求: ${contract.test_requirements.join("; ")}`
      : "",
  ];

  // 没有显式 skill slash 调用时，才回退注入协议摘要。
  if (!skillSlash && contract.skill_protocol_summary) {
    promptParts.push(`\n## 协议约束\n${contract.skill_protocol_summary}`);
  }

  if (contract.context?.relevant_files && contract.context.relevant_files.length > 0) {
    promptParts.push(`\n相关文件:\n${contract.context.relevant_files.map((f) => `- ${f}`).join("\n")}`);
  }
  if (contract.context?.relevant_snippets && contract.context.relevant_snippets.length > 0) {
    promptParts.push(`\n参考代码片段:\n${contract.context.relevant_snippets.map((s) => `--- ${s.file_path} ---\n${s.content}`).join("\n\n")}`);
  }

  promptParts.push(`执行完成后，请在输出中列出所有实际修改的文件路径（每行一个，以 "MODIFIED:" 为前缀）。`);

  return promptParts.filter(Boolean).join("\n");
}

export function buildClaudeCliArgs(options: BuildClaudeCliArgsOptions): string[] {
  const claudeBin = options.claudeBin || "claude";
  const args = [claudeBin];

  if (options.pluginRoot) {
    args.push("--plugin-dir", options.pluginRoot);
  }

  args.push("-p", options.prompt, "--output-format", "json");
  return args;
}
