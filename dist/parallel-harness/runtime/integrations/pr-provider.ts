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
  /** 本次 run 实际修改的文件路径列表，用于精确 git add（避免 add -A 污染） */
  modified_files?: string[];
  /** 目标仓库根目录，所有 git/gh 操作的显式 cwd */
  repo_root?: string;
  /** 预期的 git remote URL，用于校验 repo identity */
  expected_remote?: string;
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

async function execGh(args: string[], cwd?: string): Promise<{ stdout: string; exitCode: number }> {
  try {
    const proc = Bun.spawn(["gh", ...args], {
      cwd,
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

async function execShellForGit(cmd: string, cwd?: string): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  try {
    const proc = Bun.spawn(["sh", "-c", cmd], {
      cwd,
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

/**
 * Preflight check: 校验目标目录是否是合法的 git 仓库
 */
async function verifyRepoIdentity(
  repoRoot: string,
  expectedRemote?: string
): Promise<{ valid: boolean; error?: string }> {
  // 检查是否是 git 仓库
  const gitCheck = await execShellForGit("git rev-parse --is-inside-work-tree", repoRoot);
  if (gitCheck.exitCode !== 0 || gitCheck.stdout !== "true") {
    return { valid: false, error: `目录 ${repoRoot} 不是 git 仓库` };
  }

  // 检查 remote URL 是否匹配预期
  if (expectedRemote) {
    const remoteCheck = await execShellForGit("git remote get-url origin", repoRoot);
    if (remoteCheck.exitCode !== 0) {
      return { valid: false, error: "无法获取 origin remote URL" };
    }
    if (!remoteCheck.stdout.includes(expectedRemote)) {
      return { valid: false, error: `remote URL ${remoteCheck.stdout} 不匹配预期 ${expectedRemote}` };
    }
  }

  return { valid: true };
}

export class GitHubPRProvider implements PRProvider {
  name = "github";
  /** 当前绑定的 repo_root — 由 createPR 设置，后续操作复用 */
  private repoRoot?: string;

  constructor(repoRoot?: string) {
    this.repoRoot = repoRoot;
  }

  /**
   * 创建 PR：先执行完整 git pipeline (branch → commit → push)，再创建 PR
   * 所有 git/gh 操作显式绑定 repo_root 作为 cwd
   */
  async createPR(request: CreatePRRequest): Promise<PRResult> {
    const cwd = request.repo_root || this.repoRoot;
    // 记住 repo_root 供后续操作复用
    if (cwd) this.repoRoot = cwd;

    // Preflight: 校验 repo identity
    if (cwd) {
      const identity = await verifyRepoIdentity(cwd, request.expected_remote);
      if (!identity.valid) {
        throw new Error(`PR preflight 失败: ${identity.error}`);
      }
    }

    // Step 1: 创建并切换到 head branch（fail-fast）
    const checkoutResult = await execShellForGit(
      `git checkout -b ${request.head_branch} 2>/dev/null || git checkout ${request.head_branch}`,
      cwd
    );
    if (checkoutResult.exitCode !== 0) {
      throw new Error(`git checkout 失败: ${checkoutResult.stderr || checkoutResult.stdout}`);
    }

    // Step 2: 仅暂存 run-owned 文件（避免 add -A 污染无关改动）
    if (request.modified_files && request.modified_files.length > 0) {
      for (const file of request.modified_files) {
        await execShellForGit(`git add -- "${file}"`, cwd);
      }
    } else {
      await execShellForGit("git add -A", cwd);
    }

    // Step 3: 提交（fail-fast，不使用 --allow-empty）
    const commitResult = await execShellForGit(
      `git commit -m "[parallel-harness] ${request.title.replace(/"/g, '\\"')}"`,
      cwd
    );
    if (commitResult.exitCode !== 0) {
      // 无变更可提交时不是致命错误
      if (!commitResult.stdout.includes("nothing to commit")) {
        throw new Error(`git commit 失败: ${commitResult.stderr || commitResult.stdout}`);
      }
    }

    // Step 4: Push 到远端（fail-fast）
    const pushResult = await execShellForGit(
      `git push -u origin ${request.head_branch}`,
      cwd
    );
    if (pushResult.exitCode !== 0) {
      throw new Error(`git push 失败: ${pushResult.stderr || pushResult.stdout}`);
    }

    // Step 5: 创建 PR
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

    const { stdout, exitCode } = await execGh(args, cwd);
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
    const cwd = this.repoRoot;
    // 先获取 commit SHA
    const { stdout: commitId } = await execGh([
      "pr", "view", prId, "--json", "headRefOid", "-q", ".headRefOid",
    ], cwd);
    if (!commitId) throw new Error("无法获取 PR head commit SHA");

    const { exitCode, stdout } = await execGh([
      "api", "-X", "POST",
      `repos/{owner}/{repo}/pulls/${prId}/comments`,
      "-f", `body=${comment.body}`,
      "-f", `path=${comment.file_path}`,
      "-F", `line=${comment.line}`,
      "-f", `side=${comment.side || "RIGHT"}`,
      "-f", `commit_id=${commitId}`,
    ], cwd);
    if (exitCode !== 0) {
      throw new Error(`gh api PR comment 失败: ${stdout}`);
    }
  }

  async setCheckStatus(prId: string, check: CheckStatusRequest): Promise<void> {
    const cwd = this.repoRoot;
    const { stdout: headSha } = await execGh([
      "pr", "view", prId, "--json", "headRefOid", "-q", ".headRefOid",
    ], cwd);
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

    const { exitCode, stdout: result } = await execGh(args, cwd);
    if (exitCode !== 0) {
      throw new Error(`gh api check-runs 失败: ${result}`);
    }
  }

  async getPR(prId: string): Promise<PRInfo> {
    const cwd = this.repoRoot;
    const { stdout, exitCode } = await execGh([
      "pr", "view", prId,
      "--json", "number,url,state,title,headRefName,baseRefName,files",
    ], cwd);

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
    const cwd = this.repoRoot;
    const strategyFlag = strategy === "squash" ? "--squash"
      : strategy === "rebase" ? "--rebase"
      : "--merge";

    const { exitCode, stdout } = await execGh(["pr", "merge", prId, strategyFlag, "--auto"], cwd);
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
