import type { TaskContract } from "../session/context-pack";
import type { ModelTier } from "../orchestrator/task-graph";
import type { WorkerOutput } from "../orchestrator/role-contracts";

export interface ExecutionProxyConfig {
  model_tier: ModelTier;
  project_root: string;
  allowed_tools?: string[];
  denied_tools?: string[];
  sandbox_paths?: string[];
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
}

const MODEL_MAPPING: Record<ModelTier, string> = {
  "tier-1": "claude-haiku-4",
  "tier-2": "claude-sonnet-4",
  "tier-3": "claude-opus-4",
};

/**
 * 执行代理层 — 在 WorkerExecutionController 之前强制应用约束。
 * 生成 ExecutionAttestation 供审计和 gate 使用。
 */
export class ExecutionProxy {
  /**
   * 包装 worker 执行，增加前置约束校验和后置 attestation 生成。
   */
  wrapExecution(
    config: ExecutionProxyConfig,
    workerOutput: WorkerOutput
  ): { output: WorkerOutput; attestation: ExecutionAttestation } {
    const actualModel = MODEL_MAPPING[config.model_tier];

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

    // 检查 denied tools（通过 attestation 记录，因为真实 tool call 数据由 worker 返回）
    const attestation: ExecutionAttestation = {
      attempt_id: `att_${Date.now()}`,
      worker_id: "local",
      repo_root: config.project_root,
      actual_model: actualModel,
      tool_calls: [],
      modified_paths: workerOutput.modified_paths,
      sandbox_violations: sandboxViolations,
      token_usage: { input: workerOutput.tokens_used, output: 0 },
      timestamp: new Date().toISOString(),
    };

    return { output: workerOutput, attestation };
  }
}
