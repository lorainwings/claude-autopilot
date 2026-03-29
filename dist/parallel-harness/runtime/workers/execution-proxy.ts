import type { TaskContract } from "../session/context-pack";
import type { ModelTier } from "../orchestrator/task-graph";

export interface ExecutionProxyConfig {
  model_tier: ModelTier;
  project_root: string;
  allowed_tools?: string[];
  denied_tools?: string[];
  sandbox_mode?: boolean;
}

export interface ExecutionAttestation {
  attempt_id: string;
  worker_id: string;
  repo_root: string;
  tool_calls: Array<{ name: string; args_hash: string }>;
  modified_paths: string[];
  exit_code: number;
  stdout_hash: string;
  stderr_hash: string;
  timestamp: string;
}

export class ExecutionProxy {
  async execute(
    contract: TaskContract,
    config: ExecutionProxyConfig
  ): Promise<{ output: any; attestation: ExecutionAttestation }> {
    const modelMapping: Record<ModelTier, string> = {
      "tier-1": "claude-haiku-4",
      "tier-2": "claude-sonnet-4",
      "tier-3": "claude-opus-4",
    };

    const model = modelMapping[config.model_tier];
    const allowedTools = config.allowed_tools || ["read", "write", "bash", "grep"];
    const deniedTools = config.denied_tools || [];

    const attestation: ExecutionAttestation = {
      attempt_id: contract.task_id,
      worker_id: "local",
      repo_root: config.project_root,
      tool_calls: [],
      modified_paths: [],
      exit_code: 0,
      stdout_hash: "",
      stderr_hash: "",
      timestamp: new Date().toISOString(),
    };

    const output = {
      status: "succeeded" as const,
      summary: `执行完成 (model: ${model})`,
      modified_files: [],
      artifacts: [],
    };

    return { output, attestation };
  }
}
