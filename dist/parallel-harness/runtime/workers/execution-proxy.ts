import { join, dirname } from "path";
import { existsSync, mkdirSync, readFileSync, realpathSync, readdirSync, rmSync, statSync, writeFileSync } from "fs";
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
  /** run ID */
  run_id?: string;
  /** task ID */
  task_id?: string;
  /** baseline commit hash (用于 diff_ref) */
  baseline_commit?: string;
  /** 沙箱模式 */
  sandbox_mode?: "none" | "path_check" | "worktree";
  /** 保留失败 worktree（默认 false） */
  preserve_failed_worktree?: boolean;
  /** janitor 清理 TTL（分钟） */
  worktree_retention_minutes?: number;
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

export interface MergeTargetInspection {
  clean: boolean;
  issues: string[];
}

interface WorktreeDescriptor {
  workspace_id: string;
  worktree_path: string;
  branch_name: string;
}

interface WorktreeRegistryEntry {
  workspace_id: string;
  run_id: string;
  task_id: string;
  attempt_id?: string;
  branch_name: string;
  worktree_path: string;
  status: "active" | "merged" | "recovery_exported" | "cleanup_pending" | "cleaned";
  created_at: string;
  updated_at: string;
  recovery_patch_path?: string;
  recovery_metadata_path?: string;
}

interface WorktreeRegistry {
  version: 1;
  entries: WorktreeRegistryEntry[];
}

export interface MergeWorktreeResult {
  merged: boolean;
  failure_reason?: string;
  recovery_patch_path?: string;
  recovery_metadata_path?: string;
}

export interface WorktreeJanitorResult {
  scanned: number;
  removed_worktrees: string[];
  removed_branches: string[];
  skipped_active: string[];
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
        config.run_id,
        config.task_id,
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
  createWorktree(
    repoRoot: string,
    runId?: string,
    taskId?: string,
    attemptId?: string,
  ): { worktree_path: string; branch_name: string } | null {
    try {
      const descriptor = this.buildWorktreeDescriptor(repoRoot, runId, taskId, attemptId);
      const registry = this.readRegistry(repoRoot);
      const knownEntry = registry.entries.find((entry) => entry.workspace_id === descriptor.workspace_id);
      const activeMap = this.listManagedWorktrees(repoRoot);

      mkdirSync(dirname(descriptor.worktree_path), { recursive: true });

      const activeWorktree = activeMap.get(descriptor.worktree_path);
      if (activeWorktree && existsSync(descriptor.worktree_path)) {
        this.resetWorktree(descriptor.worktree_path);
        this.upsertRegistryEntry(repoRoot, {
          workspace_id: descriptor.workspace_id,
          run_id: runId || "unknown-run",
          task_id: taskId || attemptId || "unknown-task",
          attempt_id: attemptId,
          branch_name: descriptor.branch_name,
          worktree_path: descriptor.worktree_path,
          status: "active",
          created_at: knownEntry?.created_at || new Date().toISOString(),
          updated_at: new Date().toISOString(),
          recovery_patch_path: knownEntry?.recovery_patch_path,
          recovery_metadata_path: knownEntry?.recovery_metadata_path,
        });
        return { worktree_path: descriptor.worktree_path, branch_name: descriptor.branch_name };
      }

      if (existsSync(descriptor.worktree_path) && !activeWorktree) {
        rmSync(descriptor.worktree_path, { recursive: true, force: true });
      }

      this.deleteBranchIfExists(repoRoot, descriptor.branch_name);

      const proc = Bun.spawnSync(
        ["git", "worktree", "add", "-b", descriptor.branch_name, descriptor.worktree_path, "HEAD"],
        { cwd: repoRoot, stdout: "pipe", stderr: "pipe" }
      );
      if (proc.exitCode !== 0) {
        return null;
      }

      this.upsertRegistryEntry(repoRoot, {
        workspace_id: descriptor.workspace_id,
        run_id: runId || "unknown-run",
        task_id: taskId || attemptId || "unknown-task",
        attempt_id: attemptId,
        branch_name: descriptor.branch_name,
        worktree_path: descriptor.worktree_path,
        status: "active",
        created_at: knownEntry?.created_at || new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });

      return { worktree_path: descriptor.worktree_path, branch_name: descriptor.branch_name };
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
    this.markRegistryByPath(repoRoot, worktreePath, "cleaned");
    try {
      Bun.spawnSync(["git", "worktree", "prune"], {
        cwd: repoRoot,
        stdout: "pipe",
        stderr: "pipe",
      });
    } catch {
      // prune 失败不阻断
    }
  }

  /**
   * P0-4 修正: 将 worktree 里的改动合并回主仓库
   * 在 worktree 内提交所有变更，然后 cherry-pick 回主仓
   */
  mergeWorktreeChanges(
    repoRoot: string,
    worktreePath: string,
    worktreeBranch: string,
    options: { preserve_failed_worktree?: boolean; attempt_id?: string; run_id?: string; task_id?: string } = {},
  ): MergeWorktreeResult {
    try {
      const targetState = inspectMergeTargetCleanliness(repoRoot);
      if (!targetState.clean) {
        const exported = this.exportRecoveryArtifact(repoRoot, worktreePath, {
          run_id: options.run_id,
          task_id: options.task_id,
          attempt_id: options.attempt_id,
          branch_name: worktreeBranch,
          preserve_failed_worktree: options.preserve_failed_worktree ?? false,
          failure_reason: targetState.issues.join("; "),
        });
        this.markRegistryByPath(repoRoot, worktreePath, "recovery_exported", exported);
        return {
          merged: false,
          failure_reason: targetState.issues.join("; "),
          recovery_patch_path: exported.recovery_patch_path,
          recovery_metadata_path: exported.recovery_metadata_path,
        };
      }

      // 1. 在 worktree 中 add + commit 所有变更
      Bun.spawnSync(["git", "add", "-A"], { cwd: worktreePath, stdout: "pipe", stderr: "pipe" });
      const commitProc = Bun.spawnSync(
        ["git", "commit", "-m", `parallel-harness: worktree changes from ${worktreeBranch}`, "--allow-empty"],
        { cwd: worktreePath, stdout: "pipe", stderr: "pipe" }
      );
      if (commitProc.exitCode !== 0) {
        return { merged: false, failure_reason: "git commit failed in worktree" };
      }

      // 2. 获取 worktree 分支的 HEAD commit
      const headProc = Bun.spawnSync(["git", "rev-parse", "HEAD"], {
        cwd: worktreePath, stdout: "pipe", stderr: "pipe",
      });
      if (headProc.exitCode !== 0) {
        return { merged: false, failure_reason: "git rev-parse failed in worktree" };
      }
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
        const exported = this.exportRecoveryArtifact(repoRoot, worktreePath, {
          run_id: options.run_id,
          task_id: options.task_id,
          attempt_id: options.attempt_id,
          branch_name: worktreeBranch,
          preserve_failed_worktree: options.preserve_failed_worktree ?? false,
          failure_reason: "git cherry-pick failed",
          commit_hash: commitHash,
        });
        this.markRegistryByPath(repoRoot, worktreePath, "recovery_exported", exported);
        return {
          merged: false,
          failure_reason: "git cherry-pick failed",
          recovery_patch_path: exported.recovery_patch_path,
          recovery_metadata_path: exported.recovery_metadata_path,
        };
      }
      this.markRegistryByPath(repoRoot, worktreePath, "merged");
      return { merged: true };
    } catch {
      return { merged: false, failure_reason: "unexpected merge failure" };
    }
  }

  cleanupStaleWorktrees(repoRoot: string, ttlMinutes = 240): WorktreeJanitorResult {
    const result: WorktreeJanitorResult = {
      scanned: 0,
      removed_worktrees: [],
      removed_branches: [],
      skipped_active: [],
    };
    const activeMap = this.listManagedWorktrees(repoRoot);
    const activeBranches = new Set(activeMap.values());
    const registry = this.readRegistry(repoRoot);
    const now = Date.now();
    const ttlMs = ttlMinutes * 60 * 1000;

    for (const [worktreePath, branchName] of activeMap.entries()) {
      result.scanned += 1;
      const statMtime = existsSync(worktreePath) ? statSync(worktreePath).mtimeMs : 0;
      const ageMs = statMtime > 0 ? Math.max(0, now - statMtime) : Number.MAX_SAFE_INTEGER;
      const entry = registry.entries.find((item) => item.worktree_path === worktreePath || item.branch_name === branchName);
      const isActive = entry?.status === "active";
      if (isActive && ageMs <= ttlMs) {
        result.skipped_active.push(worktreePath);
        continue;
      }
      if (ageMs < ttlMs) continue;

      try {
        Bun.spawnSync(["git", "worktree", "unlock", worktreePath], {
          cwd: repoRoot,
          stdout: "pipe",
          stderr: "pipe",
        });
      } catch {
        // unlock 失败不阻断
      }

      this.cleanupWorktree(repoRoot, worktreePath, branchName);
      result.removed_worktrees.push(worktreePath);
      result.removed_branches.push(branchName);
    }

    for (const orphanPath of this.listOrphanedWorkspacePaths(repoRoot, activeMap)) {
      result.scanned += 1;
      try {
        rmSync(orphanPath, { recursive: true, force: true });
        result.removed_worktrees.push(orphanPath);
      } catch {
        // orphan path cleanup failure is non-blocking
      }
    }

    const currentBranch = this.getCurrentBranch(repoRoot);
    for (const branchName of this.listManagedBranches(repoRoot)) {
      result.scanned += 1;
      if (activeBranches.has(branchName) || branchName === currentBranch) continue;
      this.deleteBranchIfExists(repoRoot, branchName);
      result.removed_branches.push(branchName);
    }

    return result;
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

  private buildWorktreeDescriptor(
    repoRoot: string,
    runId?: string,
    taskId?: string,
    attemptId?: string,
  ): WorktreeDescriptor {
    const canonicalRoot = canonicalizePath(repoRoot);
    const workspaceSeed = [runId || "run", taskId || attemptId || "task"].join(":");
    const workspaceId = `ws_${simpleHash(workspaceSeed).replace(/^h_/, "")}`;
    return {
      workspace_id: workspaceId,
      worktree_path: join(canonicalRoot, ".parallel-harness", "worktrees", workspaceId),
      branch_name: `ph-worktree-${workspaceId}`,
    };
  }

  private exportRecoveryArtifact(
    repoRoot: string,
    worktreePath: string,
    metadata: Record<string, unknown>,
  ): { recovery_patch_path: string; recovery_metadata_path: string } {
    const recoveryDir = join(repoRoot, ".parallel-harness", "recovery");
    mkdirSync(recoveryDir, { recursive: true });
    const stamp = `${Date.now()}_${simpleHash(worktreePath).replace(/^h_/, "")}`;
    const patchPath = join(recoveryDir, `${stamp}.patch`);
    const metadataPath = join(recoveryDir, `${stamp}.json`);

    let patchContent = "";
    const headProc = Bun.spawnSync(["git", "rev-parse", "HEAD"], {
      cwd: worktreePath,
      stdout: "pipe",
      stderr: "pipe",
    });
    if (headProc.exitCode === 0) {
      const commitHash = new TextDecoder().decode(headProc.stdout).trim();
      const patchProc = Bun.spawnSync(["git", "format-patch", "-1", commitHash, "--stdout"], {
        cwd: worktreePath,
        stdout: "pipe",
        stderr: "pipe",
      });
      if (patchProc.exitCode === 0) {
        patchContent = new TextDecoder().decode(patchProc.stdout);
      }
    }

    if (!patchContent) {
      const diffProc = Bun.spawnSync(["git", "diff", "HEAD"], {
        cwd: worktreePath,
        stdout: "pipe",
        stderr: "pipe",
      });
      if (diffProc.exitCode === 0) {
        patchContent = new TextDecoder().decode(diffProc.stdout);
      }
    }

    writeFileSync(patchPath, patchContent, "utf8");
    writeFileSync(metadataPath, JSON.stringify({
      created_at: new Date().toISOString(),
      worktree_path: worktreePath,
      ...metadata,
      recovery_patch_path: patchPath,
    }, null, 2), "utf8");

    return {
      recovery_patch_path: patchPath,
      recovery_metadata_path: metadataPath,
    };
  }

  private listManagedWorktrees(repoRoot: string): Map<string, string> {
    const map = new Map<string, string>();
    try {
      const proc = Bun.spawnSync(["git", "worktree", "list", "--porcelain"], {
        cwd: repoRoot,
        stdout: "pipe",
        stderr: "pipe",
      });
      if (proc.exitCode !== 0) return map;
      const lines = new TextDecoder().decode(proc.stdout).split("\n");
      let currentPath = "";
      for (const line of lines) {
        if (line.startsWith("worktree ")) {
          currentPath = canonicalizePath(line.slice("worktree ".length).trim());
        } else if (line.startsWith("branch ")) {
          const branchRef = line.slice("branch ".length).trim();
          const branchName = branchRef.replace(/^refs\/heads\//, "");
          if (branchName.startsWith("ph-worktree-") && currentPath) {
            map.set(currentPath, branchName);
          }
        }
      }
    } catch {
      return map;
    }
    return map;
  }

  private listManagedBranches(repoRoot: string): string[] {
    try {
      const proc = Bun.spawnSync(["git", "branch", "--format=%(refname:short)", "--list", "ph-worktree-*"], {
        cwd: repoRoot,
        stdout: "pipe",
        stderr: "pipe",
      });
      if (proc.exitCode !== 0) return [];
      return new TextDecoder().decode(proc.stdout).split("\n").map((line) => line.trim()).filter(Boolean);
    } catch {
      return [];
    }
  }

  private listOrphanedWorkspacePaths(repoRoot: string, activeMap: Map<string, string>): string[] {
    const worktreeRoot = join(canonicalizePath(repoRoot), ".parallel-harness", "worktrees");
    if (!existsSync(worktreeRoot)) return [];
    try {
      return readdirSync(worktreeRoot, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => canonicalizePath(join(worktreeRoot, entry.name)))
        .filter((worktreePath) => !activeMap.has(worktreePath));
    } catch {
      return [];
    }
  }

  private getCurrentBranch(repoRoot: string): string | undefined {
    try {
      const proc = Bun.spawnSync(["git", "branch", "--show-current"], {
        cwd: repoRoot,
        stdout: "pipe",
        stderr: "pipe",
      });
      if (proc.exitCode !== 0) return undefined;
      const branchName = new TextDecoder().decode(proc.stdout).trim();
      return branchName || undefined;
    } catch {
      return undefined;
    }
  }

  private deleteBranchIfExists(repoRoot: string, branchName: string): void {
    try {
      const verify = Bun.spawnSync(["git", "rev-parse", "--verify", `refs/heads/${branchName}`], {
        cwd: repoRoot,
        stdout: "pipe",
        stderr: "pipe",
      });
      if (verify.exitCode === 0) {
        Bun.spawnSync(["git", "branch", "-D", branchName], {
          cwd: repoRoot,
          stdout: "pipe",
          stderr: "pipe",
        });
      }
    } catch {
      // ignore
    }
  }

  private resetWorktree(worktreePath: string): void {
    try {
      Bun.spawnSync(["git", "reset", "--hard", "HEAD"], {
        cwd: worktreePath,
        stdout: "pipe",
        stderr: "pipe",
      });
      Bun.spawnSync(["git", "clean", "-fd"], {
        cwd: worktreePath,
        stdout: "pipe",
        stderr: "pipe",
      });
    } catch {
      // ignore
    }
  }

  private readRegistry(repoRoot: string): WorktreeRegistry {
    const registryPath = join(repoRoot, ".parallel-harness", "data", "worktree-registry.json");
    mkdirSync(dirname(registryPath), { recursive: true });
    if (!existsSync(registryPath)) {
      return { version: 1, entries: [] };
    }
    try {
      const parsed = JSON.parse(readFileSync(registryPath, "utf8")) as WorktreeRegistry;
      if (parsed.version === 1 && Array.isArray(parsed.entries)) {
        return parsed;
      }
    } catch {
      // ignore broken registry, rewrite below
    }
    return { version: 1, entries: [] };
  }

  private writeRegistry(repoRoot: string, registry: WorktreeRegistry): void {
    const registryPath = join(repoRoot, ".parallel-harness", "data", "worktree-registry.json");
    mkdirSync(dirname(registryPath), { recursive: true });
    writeFileSync(registryPath, JSON.stringify(registry, null, 2), "utf8");
  }

  private upsertRegistryEntry(repoRoot: string, entry: WorktreeRegistryEntry): void {
    const registry = this.readRegistry(repoRoot);
    const idx = registry.entries.findIndex((item) => item.workspace_id === entry.workspace_id);
    if (idx >= 0) registry.entries[idx] = entry;
    else registry.entries.push(entry);
    this.writeRegistry(repoRoot, registry);
  }

  private markRegistryByPath(
    repoRoot: string,
    worktreePath: string,
    status: WorktreeRegistryEntry["status"],
    extra?: Partial<Pick<WorktreeRegistryEntry, "recovery_patch_path" | "recovery_metadata_path">>,
  ): void {
    const registry = this.readRegistry(repoRoot);
    const canonicalPath = canonicalizePath(worktreePath);
    const idx = registry.entries.findIndex((entry) => canonicalizePath(entry.worktree_path) === canonicalPath);
    if (idx < 0) return;
    registry.entries[idx] = {
      ...registry.entries[idx],
      status,
      updated_at: new Date().toISOString(),
      ...extra,
    };
    this.writeRegistry(repoRoot, registry);
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

export function inspectMergeTargetCleanliness(repoRoot: string): MergeTargetInspection {
  try {
    const statusProc = Bun.spawnSync(["git", "status", "--porcelain"], {
      cwd: repoRoot,
      stdout: "pipe",
      stderr: "pipe",
    });
    const issues: string[] = [];
    if (statusProc.exitCode !== 0) {
      return { clean: false, issues: ["git status failed"] };
    }

    const statusLines = new TextDecoder().decode(statusProc.stdout).split("\n").map((line) => line.trim()).filter(Boolean);
    if (statusLines.length > 0) {
      issues.push(`merge target has ${statusLines.length} uncommitted change(s)`);
    }

    const statePaths = [
      ".git/MERGE_HEAD",
      ".git/CHERRY_PICK_HEAD",
      ".git/REVERT_HEAD",
      ".git/rebase-merge",
      ".git/rebase-apply",
    ];
    for (const rel of statePaths) {
      if (existsSync(join(repoRoot, rel))) {
        issues.push(`merge target has in-progress git state: ${rel}`);
      }
    }

    return { clean: issues.length === 0, issues };
  } catch {
    return { clean: false, issues: ["merge target inspection failed"] };
  }
}

function canonicalizePath(path: string): string {
  try {
    if (existsSync(path)) {
      return realpathSync.native(path);
    }
    const parent = dirname(path);
    if (existsSync(parent)) {
      return join(realpathSync.native(parent), path.slice(parent.length + 1));
    }
  } catch {
    // fall through
  }
  return path;
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
