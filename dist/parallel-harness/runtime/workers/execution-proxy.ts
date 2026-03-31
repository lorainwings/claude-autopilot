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
  token_usage: { input: number; output: number };
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
  } {
    // worktree 模式暂未实现
    if (config.sandbox_mode === "worktree") {
      throw new Error("ExecutionProxy: sandbox_mode 'worktree' 尚未实现 (future feature)");
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
      validated_cwd: config.project_root,
      // 当有显式 allow/deny 列表时标记为 enforced（环境变量级别）
      tool_policy_enforced: hasExplicitPolicy ?? false,
      tool_policy_serialized: toolPolicySerialized,
      started_at: new Date().toISOString(),
      baseline_commit: baselineCommit,
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
  ): { output: WorkerOutput; attestation: ExecutionAttestation } {
    const actualModel = MODEL_MAPPING[config.model_tier];
    const endedAt = new Date().toISOString();

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
      token_usage: { input: workerOutput.tokens_used, output: 0 },
      timestamp: endedAt,
      started_at: startedAt,
      ended_at: endedAt,
      tool_policy_enforced: toolPolicyEnforced ?? false,
      diff_ref: baselineCommit || config.baseline_commit,
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
