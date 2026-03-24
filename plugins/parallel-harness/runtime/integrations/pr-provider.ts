/**
 * parallel-harness: PR/CI Provider Integration
 *
 * Provider-native 集成层。优先支持 GitHub。
 * 参考 Copilot coding agent 的 PR-first workflow
 * 和 CodeRabbit 的 incremental/full review。
 *
 * 设计为稳定接口层，具体 provider 实现可插拔。
 */

import type {
  GateResult,
  PRArtefacts,
  PRReviewComment,
  RunResult,
  RunPlan,
} from "../schemas/ga-schemas";
import { generateId } from "../schemas/ga-schemas";

// ============================================================
// PR Provider Interface
// ============================================================

export interface PRProvider {
  /** Provider 名称 */
  name: string;

  /** 创建 PR */
  createPR(request: CreatePRRequest): Promise<PRResult>;

  /** 添加 review 评论 */
  addReviewComment(prId: string, comment: ReviewCommentRequest): Promise<void>;

  /** 设置 check status */
  setCheckStatus(prId: string, check: CheckStatusRequest): Promise<void>;

  /** 获取 PR 信息 */
  getPR(prId: string): Promise<PRInfo>;

  /** 合并 PR */
  mergePR(prId: string, strategy: MergeStrategy): Promise<void>;
}

export interface CreatePRRequest {
  title: string;
  body: string;
  head_branch: string;
  base_branch: string;
  labels?: string[];
  reviewers?: string[];
  draft?: boolean;
}

export interface PRResult {
  pr_number: number;
  pr_url: string;
  head_branch: string;
}

export interface ReviewCommentRequest {
  file_path: string;
  line: number;
  body: string;
  side?: "LEFT" | "RIGHT";
}

export interface CheckStatusRequest {
  name: string;
  status: "queued" | "in_progress" | "completed";
  conclusion?: "success" | "failure" | "neutral" | "cancelled";
  output?: {
    title: string;
    summary: string;
    text?: string;
  };
}

export interface PRInfo {
  number: number;
  url: string;
  state: "open" | "closed" | "merged";
  title: string;
  head_branch: string;
  base_branch: string;
  changed_files: string[];
}

export type MergeStrategy = "merge" | "squash" | "rebase";

// ============================================================
// GitHub Provider — 通过 gh CLI 实现
// ============================================================

async function execGh(args: string[]): Promise<{ stdout: string; exitCode: number }> {
  try {
    const proc = Bun.spawn(["gh", ...args], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const stdout = await new Response(proc.stdout).text();
    const exitCode = await proc.exited;
    return { stdout: stdout.trim(), exitCode };
  } catch {
    return { stdout: "", exitCode: 1 };
  }
}

async function execShellForGit(cmd: string): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  try {
    const proc = Bun.spawn(["sh", "-c", cmd], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const [stdout, stderr] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    const exitCode = await proc.exited;
    return { stdout: stdout.trim(), stderr: stderr.trim(), exitCode };
  } catch {
    return { stdout: "", stderr: "command failed", exitCode: 127 };
  }
}

export class GitHubPRProvider implements PRProvider {
  name = "github";

  /**
   * 创建 PR：先执行完整 git pipeline (branch → commit → push)，再创建 PR
   */
  async createPR(request: CreatePRRequest): Promise<PRResult> {
    // Step 1: 创建并切换到 head branch
    await execShellForGit(
      `git checkout -b ${request.head_branch} 2>/dev/null || git checkout ${request.head_branch}`
    );

    // Step 2: 暂存所有变更并提交
    await execShellForGit("git add -A");
    await execShellForGit(
      `git commit -m "[parallel-harness] ${request.title}" --allow-empty`
    );

    // Step 3: Push 到远端
    const pushResult = await execShellForGit(
      `git push -u origin ${request.head_branch}`
    );
    if (pushResult.exitCode !== 0) {
      throw new Error(`git push 失败: ${pushResult.stderr || pushResult.stdout}`);
    }

    // Step 4: 创建 PR
    const args = [
      "pr", "create",
      "--title", request.title,
      "--body", request.body,
      "--head", request.head_branch,
      "--base", request.base_branch,
    ];
    if (request.draft) args.push("--draft");
    if (request.labels?.length) {
      for (const label of request.labels) args.push("--label", label);
    }
    if (request.reviewers?.length) {
      for (const reviewer of request.reviewers) args.push("--reviewer", reviewer);
    }

    const { stdout, exitCode } = await execGh(args);
    if (exitCode !== 0) {
      throw new Error(`gh pr create 失败: ${stdout}`);
    }

    // gh pr create 返回 PR URL
    const prUrl = stdout;
    const prMatch = prUrl.match(/\/pull\/(\d+)/);
    const prNumber = prMatch ? parseInt(prMatch[1], 10) : 0;

    return {
      pr_number: prNumber,
      pr_url: prUrl,
      head_branch: request.head_branch,
    };
  }

  async addReviewComment(prId: string, comment: ReviewCommentRequest): Promise<void> {
    // 先获取 commit SHA
    const { stdout: commitId } = await execGh([
      "pr", "view", prId, "--json", "headRefOid", "-q", ".headRefOid",
    ]);
    if (!commitId) throw new Error("无法获取 PR head commit SHA");

    const { exitCode, stdout } = await execGh([
      "api", "-X", "POST",
      `repos/{owner}/{repo}/pulls/${prId}/comments`,
      "-f", `body=${comment.body}`,
      "-f", `path=${comment.file_path}`,
      "-F", `line=${comment.line}`,
      "-f", `side=${comment.side || "RIGHT"}`,
      "-f", `commit_id=${commitId}`,
    ]);
    if (exitCode !== 0) {
      throw new Error(`gh api PR comment 失败: ${stdout}`);
    }
  }

  async setCheckStatus(prId: string, check: CheckStatusRequest): Promise<void> {
    const { stdout: headSha } = await execGh([
      "pr", "view", prId, "--json", "headRefOid", "-q", ".headRefOid",
    ]);
    if (!headSha) throw new Error("无法获取 PR head SHA");

    const args = [
      "api", "-X", "POST",
      "repos/{owner}/{repo}/check-runs",
      "-f", `name=${check.name}`,
      "-f", `head_sha=${headSha}`,
      "-f", `status=${check.status}`,
    ];
    if (check.conclusion) args.push("-f", `conclusion=${check.conclusion}`);
    if (check.output) {
      args.push("-f", `output[title]=${check.output.title}`);
      args.push("-f", `output[summary]=${check.output.summary}`);
    }

    const { exitCode, stdout: result } = await execGh(args);
    if (exitCode !== 0) {
      throw new Error(`gh api check-runs 失败: ${result}`);
    }
  }

  async getPR(prId: string): Promise<PRInfo> {
    const { stdout, exitCode } = await execGh([
      "pr", "view", prId,
      "--json", "number,url,state,title,headRefName,baseRefName,files",
    ]);

    if (exitCode !== 0) {
      throw new Error(`gh pr view 失败: ${stdout}`);
    }

    try {
      const data = JSON.parse(stdout);
      return {
        number: data.number || 0,
        url: data.url || "",
        state: data.state?.toLowerCase() === "merged" ? "merged"
          : data.state?.toLowerCase() === "closed" ? "closed"
          : "open",
        title: data.title || "",
        head_branch: data.headRefName || "",
        base_branch: data.baseRefName || "main",
        changed_files: (data.files || []).map((f: { path: string }) => f.path),
      };
    } catch {
      return {
        number: 0, url: "", state: "open", title: "",
        head_branch: "", base_branch: "main", changed_files: [],
      };
    }
  }

  async mergePR(prId: string, strategy: MergeStrategy): Promise<void> {
    const strategyFlag = strategy === "squash" ? "--squash"
      : strategy === "rebase" ? "--rebase"
      : "--merge";

    const { exitCode, stdout } = await execGh(["pr", "merge", prId, strategyFlag, "--auto"]);
    if (exitCode !== 0) {
      throw new Error(`gh pr merge 失败: ${stdout}`);
    }
  }
}

// ============================================================
// PR Summary Renderer
// ============================================================

export interface PRSummaryOptions {
  include_walkthrough: boolean;
  include_gate_results: boolean;
  include_cost_summary: boolean;
  include_file_changes: boolean;
  max_findings: number;
}

export const DEFAULT_PR_SUMMARY_OPTIONS: PRSummaryOptions = {
  include_walkthrough: true,
  include_gate_results: true,
  include_cost_summary: true,
  include_file_changes: true,
  max_findings: 20,
};

export function renderPRSummary(
  result: RunResult,
  plan: RunPlan,
  gateResults: GateResult[],
  options: Partial<PRSummaryOptions> = {}
): string {
  const opts = { ...DEFAULT_PR_SUMMARY_OPTIONS, ...options };
  const sections: string[] = [];

  // Header
  sections.push(`## parallel-harness Run Summary`);
  sections.push("");
  sections.push(`**Run ID**: \`${result.run_id}\``);
  sections.push(`**Status**: ${statusEmoji(result.final_status)} ${result.final_status}`);
  sections.push(`**Duration**: ${formatDuration(result.total_duration_ms)}`);
  sections.push("");

  // Task Summary
  sections.push(`### Tasks`);
  sections.push(`| Status | Count |`);
  sections.push(`|--------|-------|`);
  sections.push(`| Completed | ${result.completed_tasks.length} |`);
  sections.push(`| Failed | ${result.failed_tasks.length} |`);
  sections.push(`| Skipped | ${result.skipped_tasks.length} |`);
  sections.push("");

  // Walkthrough
  if (opts.include_walkthrough && plan) {
    sections.push(`### Walkthrough`);
    for (const task of plan.task_graph.tasks) {
      const status = result.completed_tasks.includes(task.id) ? "done" : "pending";
      const icon = status === "done" ? "check" : "x";
      sections.push(`- :${icon}: **${task.title}** — ${task.goal}`);
    }
    sections.push("");
  }

  // Gate Results
  if (opts.include_gate_results && gateResults.length > 0) {
    sections.push(`### Gate Results`);
    sections.push(`| Gate | Status | Blocking | Findings |`);
    sections.push(`|------|--------|----------|----------|`);
    for (const gate of gateResults) {
      const icon = gate.passed ? "pass" : "fail";
      sections.push(
        `| ${gate.gate_type} | ${icon} | ${gate.blocking ? "Yes" : "No"} | ${gate.conclusion.findings.length} |`
      );
    }
    sections.push("");
  }

  // Cost Summary
  if (opts.include_cost_summary) {
    sections.push(`### Cost Summary`);
    sections.push(`- **Total Tokens**: ${result.cost_summary.total_tokens.toLocaleString()}`);
    sections.push(`- **Total Cost**: ${result.cost_summary.total_cost.toFixed(2)}`);
    sections.push(`- **Budget Utilization**: ${(result.cost_summary.budget_utilization * 100).toFixed(1)}%`);
    sections.push(`- **Retries**: ${result.cost_summary.total_retries}`);
    sections.push("");
  }

  // Failed Tasks
  if (result.failed_tasks.length > 0) {
    sections.push(`### Failed Tasks`);
    for (const failed of result.failed_tasks) {
      sections.push(`- **${failed.task_id}**: ${failed.failure_class} — ${failed.message}`);
    }
    sections.push("");
  }

  // Footer
  sections.push(`---`);
  sections.push(`*Generated by parallel-harness v${plan?.schema_version || "1.0.0"}*`);

  return sections.join("\n");
}

export function renderReviewComments(
  gateResults: GateResult[],
  maxComments: number = 20
): PRReviewComment[] {
  const comments: PRReviewComment[] = [];

  for (const gate of gateResults) {
    for (const finding of gate.conclusion.findings) {
      if (comments.length >= maxComments) break;
      if (!finding.file_path || !finding.line) continue;

      comments.push({
        file_path: finding.file_path,
        line: finding.line,
        body: `**[${gate.gate_type}]** ${finding.severity.toUpperCase()}: ${finding.message}${finding.suggestion ? `\n\n> Suggestion: ${finding.suggestion}` : ""}`,
        severity: finding.severity === "critical" || finding.severity === "error" ? "error" : finding.severity === "warning" ? "warning" : "info",
      });
    }
  }

  return comments;
}

// ============================================================
// CI Failure Ingest
// ============================================================

export interface CIFailure {
  ci_provider: string;
  job_name: string;
  step_name?: string;
  error_message: string;
  log_url?: string;
  affected_files: string[];
  failure_type: "build" | "test" | "lint" | "type_check" | "deploy" | "unknown";
}

export function parseCIFailure(rawLog: string): CIFailure {
  const failure: CIFailure = {
    ci_provider: "unknown",
    job_name: "unknown",
    error_message: rawLog.slice(0, 500),
    affected_files: [],
    failure_type: "unknown",
  };

  // 简单启发式解析
  if (rawLog.includes("FAIL") && (rawLog.includes("test") || rawLog.includes("spec"))) {
    failure.failure_type = "test";
  } else if (rawLog.includes("error TS") || rawLog.includes("type error")) {
    failure.failure_type = "type_check";
  } else if (rawLog.includes("lint") || rawLog.includes("eslint") || rawLog.includes("ruff")) {
    failure.failure_type = "lint";
  } else if (rawLog.includes("build") || rawLog.includes("compile")) {
    failure.failure_type = "build";
  }

  // 提取文件路径
  const filePattern = /(?:^|\s)([\w\-./]+\.\w{1,5})(?::\d+)?/gm;
  let match;
  while ((match = filePattern.exec(rawLog)) !== null) {
    if (match[1] && !failure.affected_files.includes(match[1])) {
      failure.affected_files.push(match[1]);
    }
  }

  return failure;
}

// ============================================================
// Issue/PR/Run Mapping
// ============================================================

export interface RunMapping {
  run_id: string;
  issue_number?: number;
  pr_number?: number;
  ci_run_id?: string;
  branch_name?: string;
  created_at: string;
}

export class RunMappingRegistry {
  private mappings: Map<string, RunMapping> = new Map();

  register(mapping: RunMapping): void {
    this.mappings.set(mapping.run_id, mapping);
  }

  getByRunId(run_id: string): RunMapping | undefined {
    return this.mappings.get(run_id);
  }

  getByPR(pr_number: number): RunMapping | undefined {
    return [...this.mappings.values()].find((m) => m.pr_number === pr_number);
  }

  getByIssue(issue_number: number): RunMapping | undefined {
    return [...this.mappings.values()].find((m) => m.issue_number === issue_number);
  }

  listAll(): RunMapping[] {
    return [...this.mappings.values()];
  }
}

// ============================================================
// Helpers
// ============================================================

function statusEmoji(status: string): string {
  const map: Record<string, string> = {
    succeeded: "pass",
    failed: "fail",
    partially_failed: "warn",
    cancelled: "cancel",
    blocked: "block",
  };
  return map[status] || status;
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  return `${(ms / 60000).toFixed(1)}m`;
}
