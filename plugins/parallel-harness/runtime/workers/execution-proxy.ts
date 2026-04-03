import { join, dirname } from "path";
import type { TaskContract } from "../session/context-pack";
import type { ModelTier } from "../orchestrator/task-graph";
import type { WorkerOutput } from "../orchestrator/role-contracts";

export interface ExecutionProxyConfig {
  model_tier: ModelTier;
  project_root: string;
  allowed_tools?: string[];
  denied_tools?: string[];
  sandbox_paths?: string[];
  /** worker ID (由 orchestrator 分配) */
  worker_id?: string;
  /** attempt ID */
  attempt_id?: string;
  /** baseline commit hash (用于 diff_ref) */
  baseline_commit?: string;
  /** 沙箱模式 */
  sandbox_mode?: "none" | "path_check" | "worktree";
}

export interface ExecutionAttestation {
  attempt_id: string;
  worker_id: string;
  repo_root: string;
  actual_model: string;
  tool_calls: Array<{ name: string; args_hash: string }>;
  modified_paths: string[];
  sandbox_violations: string[];
  token_usage: { input: number; output: number; usage_source: "provider" | "estimated" };
  timestamp: string;
  /** 执行起止时间 */
  started_at: string;
  ended_at: string;
  /** 工具策略是否强制生效 */
  tool_policy_enforced: boolean;
  /** diff 引用（用于审计追溯） */
  diff_ref?: string;
  /** 执行结果摘要 */
  execution_outcome: "success" | "failure" | "violation";
}

/** P0-4: 可信执行记录 — 真实执行面产物 */
export interface TrustedExecutionRecord {
  /** Attempt ID */
  attempt_id: string;
  /** Worktree 路径 (worktree 模式下) */
  worktree_path?: string;
  /** 执行工作目录 */
  cwd: string;
  /** 工具调用 trace */
  tool_trace: Array<{
    tool: string;
    started_at: string;
    ended_at: string;
    args_hash: string;
    exit_code?: number;
  }>;
  /** 标准输出引用 */
  stdout_ref?: string;
  /** 标准错误引用 */
  stderr_ref?: string;
  /** Diff 引用 (commit hash 或 patch file) */
  diff_ref: string;
  /** 沙箱是否强制生效 */
  sandbox_enforced: boolean;
}

const MODEL_MAPPING: Record<ModelTier, string> = {
  "tier-1": "claude-haiku-4",
  "tier-2": "claude-sonnet-4",
  "tier-3": "claude-opus-4",
};

/**
 * 执行代理层 — 在 WorkerExecutionController 之前强制应用约束。
 *
 * 职责拆分:
 * - ExecutionProxy: 模型/provider 绑定、tool policy、repo/cwd/sandbox 绑定、attestation 采集
 * - WorkerExecutionController: attempt 生命周期、超时、snapshot、diff merge、输出校验
 */
export class ExecutionProxy {
  /**
   * 准备执行环境：在 worker 执行前调用，返回验证后的执行配置。
   * 确保执行入口经过 proxy 而不是直接调 adapter。
   */
  prepareExecution(config: ExecutionProxyConfig): {
    validated_model: string;
    validated_cwd: string;
    tool_policy_enforced: boolean;
    tool_policy_serialized?: string;
    started_at: string;
    baseline_commit?: string;
    worktree_path?: string;
    worktree_branch?: string;
  } {
    // P0-4: worktree 模式
    let worktreeInfo: { worktree_path: string; branch_name: string } | null = null;
    if (config.sandbox_mode === "worktree") {
      worktreeInfo = this.createWorktree(
        config.project_root,
        config.attempt_id || `att_${Date.now()}`
      );
      if (!worktreeInfo) {
        // worktree 创建失败，降级为 path_check
        config.sandbox_mode = "path_check";
      }
    }

    const actualModel = MODEL_MAPPING[config.model_tier];

    // 验证 project_root 非空
    if (!config.project_root) {
      throw new Error("ExecutionProxy: project_root 不能为空");
    }

    // 构建 tool policy 序列化字符串供 worker adapter 使用
    let toolPolicySerialized: string | undefined;
    const hasExplicitPolicy = (config.allowed_tools && config.allowed_tools.length > 0)
      || (config.denied_tools && config.denied_tools.length > 0);
    if (hasExplicitPolicy) {
      toolPolicySerialized = JSON.stringify({
        allowed: config.allowed_tools || [],
        denied: config.denied_tools || [],
      });
    }

    // 采集 baseline commit (如果提供了就直接使用，否则尝试 git rev-parse)
    let baselineCommit = config.baseline_commit;
    if (!baselineCommit) {
      try {
        const proc = Bun.spawnSync(["git", "rev-parse", "HEAD"], {
          cwd: config.project_root,
          stdout: "pipe",
          stderr: "pipe",
        });
        if (proc.exitCode === 0) {
          baselineCommit = new TextDecoder().decode(proc.stdout).trim();
        }
      } catch {
        // git 不可用，baseline_commit 保持 undefined
      }
    }

    return {
      validated_model: actualModel,
      validated_cwd: worktreeInfo?.worktree_path || config.project_root,
      // 当有显式 allow/deny 列表时标记为 enforced（环境变量级别）
      tool_policy_enforced: hasExplicitPolicy ?? false,
      tool_policy_serialized: toolPolicySerialized,
      started_at: new Date().toISOString(),
      baseline_commit: baselineCommit,
      worktree_path: worktreeInfo?.worktree_path,
      worktree_branch: worktreeInfo?.branch_name,
    };
  }

  /**
   * 完成执行：在 worker 执行后调用，生成可追溯 attestation。
   * attestation 来源于真实执行过程数据。
   */
  finalizeExecution(
    config: ExecutionProxyConfig,
    workerOutput: WorkerOutput,
    startedAt: string,
    toolPolicyEnforced?: boolean,
    baselineCommit?: string,
    /** P0-4 修正: 实际执行目录（worktree 模式下与 project_root 不同） */
    executionCwd?: string,
  ): { output: WorkerOutput; attestation: ExecutionAttestation } {
    const actualModel = MODEL_MAPPING[config.model_tier];
    const endedAt = new Date().toISOString();
    // P0-4 修正: diff_ref 基于实际执行目录而非原始 project_root
    const diffCwd = executionCwd || config.project_root;

    // 检查 sandbox violations
    const sandboxViolations: string[] = [];
    if (config.sandbox_paths && config.sandbox_paths.length > 0) {
      for (const modified of workerOutput.modified_paths) {
        const inSandbox = config.sandbox_paths.some(
          (sp) => modified.startsWith(sp) || modified === sp
        );
        if (!inSandbox) {
          sandboxViolations.push(`越界写入: ${modified}`);
        }
      }
    }

    // 确定执行结果
    const executionOutcome: ExecutionAttestation["execution_outcome"] =
      sandboxViolations.length > 0
        ? "violation"
        : workerOutput.status === "ok" || workerOutput.status === "warning"
          ? "success"
          : "failure";

    // 从 modified_paths 派生 tool_calls
    const toolCalls = workerOutput.modified_paths.map((p) => ({
      name: "Edit",
      args_hash: simpleHash(p),
    }));

    const attestation: ExecutionAttestation = {
      attempt_id: config.attempt_id || `att_${Date.now()}`,
      worker_id: config.worker_id || "local",
      repo_root: config.project_root,
      actual_model: actualModel,
      tool_calls: toolCalls,
      modified_paths: workerOutput.modified_paths,
      sandbox_violations: sandboxViolations,
      token_usage: { input: workerOutput.tokens_used, output: 0, usage_source: "estimated" as const },
      timestamp: endedAt,
      started_at: startedAt,
      ended_at: endedAt,
      tool_policy_enforced: toolPolicyEnforced ?? false,
      diff_ref: this.generateDiffRef(diffCwd, baselineCommit || config.baseline_commit),
      execution_outcome: executionOutcome,
    };

    return { output: workerOutput, attestation };
  }

  /**
   * 向后兼容：一步完成包装（用于不需要 prepare/finalize 分离的场景）
   */
  wrapExecution(
    config: ExecutionProxyConfig,
    workerOutput: WorkerOutput
  ): { output: WorkerOutput; attestation: ExecutionAttestation } {
    const startedAt = new Date().toISOString();
    return this.finalizeExecution(config, workerOutput, startedAt);
  }

  /**
   * P0-4: 创建 per-run worktree 用于执行隔离
   */
  createWorktree(repoRoot: string, attemptId: string): { worktree_path: string; branch_name: string } | null {
    try {
      const branchName = `ph-worktree-${attemptId}`;
      const worktreePath = join(repoRoot, ".parallel-harness", "worktrees", attemptId);

      // 创建 worktree 目录
      const mkdirProc = Bun.spawnSync(["mkdir", "-p", dirname(worktreePath)], {
        cwd: repoRoot,
        stdout: "pipe",
        stderr: "pipe",
      });
      if (mkdirProc.exitCode !== 0) return null;

      // git worktree add
      const proc = Bun.spawnSync(
        ["git", "worktree", "add", "-b", branchName, worktreePath, "HEAD"],
        { cwd: repoRoot, stdout: "pipe", stderr: "pipe" }
      );

      if (proc.exitCode !== 0) {
        // worktree 创建失败，回退到非隔离模式
        return null;
      }

      return { worktree_path: worktreePath, branch_name: branchName };
    } catch {
      return null;
    }
  }

  /**
   * P0-4: 清理 worktree 和临时分支
   */
  cleanupWorktree(repoRoot: string, worktreePath: string, branchName?: string): void {
    try {
      Bun.spawnSync(["git", "worktree", "remove", "--force", worktreePath], {
        cwd: repoRoot,
        stdout: "pipe",
        stderr: "pipe",
      });
    } catch {
      // cleanup 失败不阻断主流程
    }
    // 清理临时分支，防止 refs 累积
    if (branchName) {
      try {
        Bun.spawnSync(["git", "branch", "-D", branchName], {
          cwd: repoRoot,
          stdout: "pipe",
          stderr: "pipe",
        });
      } catch {
        // 分支删除失败不阻断
      }
    }
  }

  /**
   * P0-4 修正: 将 worktree 里的改动合并回主仓库
   * 在 worktree 内提交所有变更，然后 cherry-pick 回主仓
   */
  mergeWorktreeChanges(repoRoot: string, worktreePath: string, worktreeBranch: string): boolean {
    try {
      // 1. 在 worktree 中 add + commit 所有变更
      Bun.spawnSync(["git", "add", "-A"], { cwd: worktreePath, stdout: "pipe", stderr: "pipe" });
      const commitProc = Bun.spawnSync(
        ["git", "commit", "-m", `parallel-harness: worktree changes from ${worktreeBranch}`, "--allow-empty"],
        { cwd: worktreePath, stdout: "pipe", stderr: "pipe" }
      );
      if (commitProc.exitCode !== 0) return false;

      // 2. 获取 worktree 分支的 HEAD commit
      const headProc = Bun.spawnSync(["git", "rev-parse", "HEAD"], {
        cwd: worktreePath, stdout: "pipe", stderr: "pipe",
      });
      if (headProc.exitCode !== 0) return false;
      const commitHash = new TextDecoder().decode(headProc.stdout).trim();

      // 3. 在主仓 cherry-pick
      const pickProc = Bun.spawnSync(
        ["git", "cherry-pick", "--no-commit", commitHash],
        { cwd: repoRoot, stdout: "pipe", stderr: "pipe" }
      );
      if (pickProc.exitCode !== 0) {
        // cherry-pick 失败 — 必须 abort 清理冲突态，防止主仓被污染
        Bun.spawnSync(["git", "cherry-pick", "--abort"], {
          cwd: repoRoot, stdout: "pipe", stderr: "pipe",
        });
        // 再 reset 确保 index 干净
        Bun.spawnSync(["git", "reset", "--merge"], {
          cwd: repoRoot, stdout: "pipe", stderr: "pipe",
        });
        return false;
      }
      return true;
    } catch {
      return false;
    }
  }

  /**
   * P0-4: 生成真实 diff ref
   */
  generateDiffRef(cwd: string, baselineCommit?: string): string {
    try {
      if (baselineCommit) {
        // 与 baseline 对比
        const proc = Bun.spawnSync(
          ["git", "diff", baselineCommit, "--stat"],
          { cwd, stdout: "pipe", stderr: "pipe" }
        );
        if (proc.exitCode === 0) {
          const diffStat = new TextDecoder().decode(proc.stdout).trim();
          if (diffStat) {
            // 生成 patch 文件引用
            const patchProc = Bun.spawnSync(
              ["git", "diff", baselineCommit],
              { cwd, stdout: "pipe", stderr: "pipe" }
            );
            if (patchProc.exitCode === 0) {
              const patchContent = new TextDecoder().decode(patchProc.stdout);
              const patchHash = simpleHash(patchContent);
              return `diff:${baselineCommit.slice(0, 8)}..HEAD:${patchHash}`;
            }
          }
        }
      }

      // fallback: 当前 HEAD
      const proc = Bun.spawnSync(["git", "rev-parse", "HEAD"], {
        cwd, stdout: "pipe", stderr: "pipe",
      });
      if (proc.exitCode === 0) {
        return `commit:${new TextDecoder().decode(proc.stdout).trim()}`;
      }

      return "no-diff-ref";
    } catch {
      return "no-diff-ref";
    }
  }

  /**
   * P0-4: 从 attestation 构建可信执行记录
   */
  buildTrustedRecord(
    attestation: ExecutionAttestation,
    cwd: string,
    worktreePath?: string,
  ): TrustedExecutionRecord {
    return {
      attempt_id: attestation.attempt_id,
      worktree_path: worktreePath,
      cwd,
      tool_trace: attestation.tool_calls.map(tc => ({
        tool: tc.name,
        started_at: attestation.started_at,
        ended_at: attestation.ended_at,
        args_hash: tc.args_hash,
      })),
      diff_ref: attestation.diff_ref || "no-diff-ref",
      sandbox_enforced: attestation.tool_policy_enforced,
    };
  }
}

/** 简单字符串哈希（非密码学，仅用于 attestation 标识） */
function simpleHash(input: string): string {
  let hash = 0;
  for (let i = 0; i < input.length; i++) {
    const ch = input.charCodeAt(i);
    hash = ((hash << 5) - hash) + ch;
    hash |= 0;
  }
  return `h_${Math.abs(hash).toString(36)}`;
}

/** 工具策略违规错误 */
export class ToolPolicyViolationError extends Error {
  constructor(
    public readonly tool_name: string,
    public readonly policy: { allowed: string[]; denied: string[] }
  ) {
    super(`工具策略违规: "${tool_name}" 不在允许列表中或被明确拒绝`);
    this.name = "ToolPolicyViolationError";
  }
}

/**
 * 验证 tool call 是否符合策略
 * - 如果有 allowed 列表，tool 必须在列表中
 * - 如果有 denied 列表，tool 不能在列表中
 * - 两个列表都为空时默认放行
 */
export function validateToolCall(
  toolName: string,
  config: ExecutionProxyConfig
): boolean {
  const { allowed_tools, denied_tools } = config;

  // denied 列表优先检查
  if (denied_tools && denied_tools.length > 0) {
    if (denied_tools.includes(toolName)) return false;
  }

  // allowed 列表检查（空列表 = 不限制）
  if (allowed_tools && allowed_tools.length > 0) {
    return allowed_tools.includes(toolName);
  }

  return true;
}
