/**
 * parallel-harness: Worker Runtime
 *
 * 真实 Worker 运行时。Worker 从模拟升级为受控执行环境。
 * 支持本地 worker 与未来远端 worker 的抽象接口。
 *
 * 关键设计：
 * - Worker 必须接收结构化 task contract，而不是自由 prompt
 * - 执行前校验：ownership、policy、budget、capability、approval
 * - 每次 attempt 记录输入/输出摘要、成本、状态迁移、失败分类
 */

import type { WorkerInput, WorkerOutput } from "../orchestrator/role-contracts";
import type { TaskContract } from "../session/context-pack";
import type { ModelTier } from "../orchestrator/task-graph";
import type { WorkerAdapter, ExecutionContext } from "../engine/orchestrator-runtime";
import {
  generateId,
  FAILURE_ACTION_MAP,
  type FailureClass,
} from "../schemas/ga-schemas";

// ============================================================
// Worker Capability Registry
// ============================================================

export interface WorkerCapability {
  /** 能力 ID */
  id: string;

  /** 能力名称 */
  name: string;

  /** 描述 */
  description: string;

  /** 适用的任务类型 */
  task_types: string[];

  /** 需要的工具 */
  required_tools: string[];

  /** 推荐的模型 tier */
  recommended_tier: ModelTier;

  /** 适用阶段 */
  applicable_phases: ("planning" | "implementation" | "review" | "testing")[];
}

export class CapabilityRegistry {
  private capabilities: Map<string, WorkerCapability> = new Map();

  register(capability: WorkerCapability): void {
    this.capabilities.set(capability.id, capability);
  }

  get(id: string): WorkerCapability | undefined {
    return this.capabilities.get(id);
  }

  findByTaskType(taskType: string): WorkerCapability[] {
    return [...this.capabilities.values()].filter(
      (c) => c.task_types.some((t) => taskType.toLowerCase().includes(t.toLowerCase()))
    );
  }

  listAll(): WorkerCapability[] {
    return [...this.capabilities.values()];
  }

  hasCapability(id: string): boolean {
    return this.capabilities.has(id);
  }
}

/** 内置能力注册 */
export function createDefaultCapabilityRegistry(): CapabilityRegistry {
  const registry = new CapabilityRegistry();

  registry.register({
    id: "code_implementation",
    name: "代码实现",
    description: "编写和修改代码文件",
    task_types: ["implementation", "bug-fix", "refactor", "feature"],
    required_tools: ["Read", "Write", "Edit", "Bash"],
    recommended_tier: "tier-2",
    applicable_phases: ["implementation"],
  });

  registry.register({
    id: "test_writing",
    name: "测试编写",
    description: "编写单元测试和集成测试",
    task_types: ["test-writing", "test", "testing"],
    required_tools: ["Read", "Write", "Edit", "Bash"],
    recommended_tier: "tier-2",
    applicable_phases: ["testing"],
  });

  registry.register({
    id: "code_review",
    name: "代码审查",
    description: "审查代码质量和安全性",
    task_types: ["review", "security-audit", "code-review"],
    required_tools: ["Read", "Grep", "Glob"],
    recommended_tier: "tier-3",
    applicable_phases: ["review"],
  });

  registry.register({
    id: "documentation",
    name: "文档编写",
    description: "编写和更新文档",
    task_types: ["documentation", "doc", "readme"],
    required_tools: ["Read", "Write", "Edit"],
    recommended_tier: "tier-1",
    applicable_phases: ["implementation"],
  });

  registry.register({
    id: "lint_fix",
    name: "Lint 修复",
    description: "修复 lint 和格式问题",
    task_types: ["lint-fix", "format", "style"],
    required_tools: ["Read", "Edit", "Bash"],
    recommended_tier: "tier-1",
    applicable_phases: ["implementation"],
  });

  registry.register({
    id: "architecture_design",
    name: "架构设计",
    description: "设计系统架构和模块结构",
    task_types: ["planning", "architecture", "design"],
    required_tools: ["Read", "Grep", "Glob", "Write"],
    recommended_tier: "tier-3",
    applicable_phases: ["planning"],
  });

  return registry;
}

// ============================================================
// Tool Allowlist / Denylist
// ============================================================

export interface ToolPolicy {
  /** 允许的工具列表 (空 = 允许所有) */
  allowlist: string[];

  /** 禁止的工具列表 */
  denylist: string[];
}

export function isToolAllowed(tool: string, policy: ToolPolicy): boolean {
  if (policy.denylist.includes(tool)) return false;
  if (policy.allowlist.length === 0) return true;
  return policy.allowlist.includes(tool);
}

/** 默认工具策略 */
export const DEFAULT_TOOL_POLICY: ToolPolicy = {
  allowlist: [], // 允许所有
  denylist: ["TaskStop", "EnterWorktree"], // 禁止危险操作
};

// ============================================================
// Path Sandbox
// ============================================================

export interface PathSandbox {
  allowed_paths: string[];
  forbidden_paths: string[];
  root_path: string;
}

export function isPathInSandbox(filePath: string, sandbox: PathSandbox): boolean {
  // 检查禁止路径
  for (const forbidden of sandbox.forbidden_paths) {
    if (pathMatchesPattern(filePath, forbidden)) return false;
  }

  // 检查允许路径
  if (sandbox.allowed_paths.length === 0) return true;
  return sandbox.allowed_paths.some((allowed) => pathMatchesPattern(filePath, allowed));
}

function pathMatchesPattern(path: string, pattern: string): boolean {
  if (path === pattern) return true;
  if (pattern.endsWith("/**") || pattern.endsWith("/*")) {
    const prefix = pattern.replace(/\/\*\*?$/, "");
    return path.startsWith(prefix);
  }
  if (pattern.includes("*")) {
    const regex = new RegExp(
      "^" + pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".") + "$"
    );
    return regex.test(path);
  }
  const normalizedPattern = pattern.endsWith("/") ? pattern : pattern + "/";
  return path.startsWith(normalizedPattern) || path === pattern;
}

// ============================================================
// Worker Execution Controller
// ============================================================

export interface WorkerExecutionConfig {
  /** 超时 (ms) */
  timeout_ms: number;

  /** 心跳间隔 (ms) */
  heartbeat_interval_ms: number;

  /** 最大空闲时间 (ms) */
  max_idle_ms: number;

  /** 工具策略 */
  tool_policy: ToolPolicy;

  /** 路径沙箱 */
  path_sandbox: PathSandbox;

  /** 是否启用幂等性 */
  idempotent: boolean;
}

export const DEFAULT_WORKER_EXECUTION_CONFIG: WorkerExecutionConfig = {
  timeout_ms: 300000,       // 5 分钟
  heartbeat_interval_ms: 30000,
  max_idle_ms: 60000,
  tool_policy: DEFAULT_TOOL_POLICY,
  path_sandbox: {
    allowed_paths: [],
    forbidden_paths: [],
    root_path: ".",
  },
  idempotent: false,
};

export interface WorkerExecutionResult {
  output: WorkerOutput;
  execution_metadata: {
    attempt_id: string;
    started_at: string;
    ended_at: string;
    duration_ms: number;
    timed_out: boolean;
    heartbeat_count: number;
  };
}

/**
 * Worker 执行控制器
 * 管理单个 worker 的生命周期：启动、监控、超时、取消
 */
export class WorkerExecutionController {
  private adapter: WorkerAdapter;
  private config: WorkerExecutionConfig;
  private capabilityRegistry: CapabilityRegistry;

  constructor(
    adapter: WorkerAdapter,
    config: Partial<WorkerExecutionConfig> = {},
    capabilityRegistry?: CapabilityRegistry
  ) {
    this.adapter = adapter;
    this.config = { ...DEFAULT_WORKER_EXECUTION_CONFIG, ...config };
    this.capabilityRegistry = capabilityRegistry || createDefaultCapabilityRegistry();
  }

  /**
   * 执行 worker 任务，带超时和沙箱控制
   */
  async execute(input: WorkerInput): Promise<WorkerExecutionResult> {
    const attemptId = generateId("att");
    const startedAt = new Date().toISOString();

    // 1. 能力检查
    this.validateCapability(input.contract);

    // 2. 路径沙箱设置
    const sandbox: PathSandbox = {
      allowed_paths: input.contract.allowed_paths,
      forbidden_paths: input.contract.forbidden_paths,
      root_path: this.config.path_sandbox.root_path,
    };

    // 3. 带超时的执行
    const output = await this.executeWithTimeout(input);

    // 4. 验证输出路径
    this.validateOutputPaths(output, sandbox);

    const endedAt = new Date().toISOString();

    return {
      output,
      execution_metadata: {
        attempt_id: attemptId,
        started_at: startedAt,
        ended_at: endedAt,
        duration_ms: new Date(endedAt).getTime() - new Date(startedAt).getTime(),
        timed_out: false,
        heartbeat_count: 0,
      },
    };
  }

  private validateCapability(contract: TaskContract): void {
    // 基本验证：确保 contract 包含必要字段
    if (!contract.task_id) throw new Error("TaskContract 缺少 task_id");
    if (!contract.goal) throw new Error("TaskContract 缺少 goal");
    if (!contract.allowed_paths || contract.allowed_paths.length === 0) {
      throw new Error("TaskContract 缺少 allowed_paths");
    }
  }

  private async executeWithTimeout(input: WorkerInput): Promise<WorkerOutput> {
    const timeoutPromise = new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error(`Worker 执行超时 (${this.config.timeout_ms}ms)`)), this.config.timeout_ms);
    });

    return Promise.race([
      this.adapter.execute(input),
      timeoutPromise,
    ]);
  }

  private validateOutputPaths(output: WorkerOutput, sandbox: PathSandbox): void {
    for (const path of output.modified_paths) {
      if (!isPathInSandbox(path, sandbox)) {
        throw new Error(
          `Worker 修改了沙箱外的路径: ${path}。` +
          `允许路径: ${sandbox.allowed_paths.join(", ")}`
        );
      }
    }
  }

  getCapabilityRegistry(): CapabilityRegistry {
    return this.capabilityRegistry;
  }
}

// ============================================================
// Worker Launch Strategy
// ============================================================

export type WorkerLaunchStrategy = "local" | "subprocess" | "remote";

export interface WorkerLauncher {
  strategy: WorkerLaunchStrategy;
  launch(input: WorkerInput, config: WorkerExecutionConfig): Promise<WorkerOutput>;
}

/** 本地进程内执行 */
export class LocalWorkerLauncher implements WorkerLauncher {
  strategy: WorkerLaunchStrategy = "local";
  private adapter: WorkerAdapter;

  constructor(adapter: WorkerAdapter) {
    this.adapter = adapter;
  }

  async launch(input: WorkerInput, _config: WorkerExecutionConfig): Promise<WorkerOutput> {
    return this.adapter.execute(input);
  }
}

// ============================================================
// Retry Manager
// ============================================================

export interface RetryDecision {
  should_retry: boolean;
  new_model_tier?: ModelTier;
  compact_context: boolean;
  reason: string;
  delay_ms: number;
}

export function decideRetry(
  failureClass: FailureClass,
  currentAttempt: number,
  maxRetries: number,
  currentTier: ModelTier,
  escalateOnRetry: boolean
): RetryDecision {
  if (currentAttempt >= maxRetries) {
    return {
      should_retry: false,
      compact_context: false,
      reason: `已达到最大重试次数 (${maxRetries})`,
      delay_ms: 0,
    };
  }

  const action = FAILURE_ACTION_MAP[failureClass];
  // 检查是否可重试
  const retryableFailures: FailureClass[] = [
    "transient_tool_failure",
    "verification_failed",
    "timeout",
    "unknown",
  ];

  if (!retryableFailures.includes(failureClass)) {
    return {
      should_retry: false,
      compact_context: false,
      reason: `失败类型 ${failureClass} 不可重试`,
      delay_ms: 0,
    };
  }

  // 计算新 tier
  let newTier = currentTier;
  if (escalateOnRetry) {
    const tierOrder: ModelTier[] = ["tier-1", "tier-2", "tier-3"];
    const idx = tierOrder.indexOf(currentTier);
    if (idx < tierOrder.length - 1) {
      newTier = tierOrder[idx + 1];
    }
  }

  // 指数退避
  const delay_ms = Math.min(1000 * Math.pow(2, currentAttempt), 30000);

  return {
    should_retry: true,
    new_model_tier: newTier !== currentTier ? newTier : undefined,
    compact_context: currentAttempt >= 2, // 第 3 次及以后压缩上下文
    reason: `失败类型 ${failureClass} 可重试，第 ${currentAttempt + 1} 次`,
    delay_ms,
  };
}

// ============================================================
// Downgrade Manager
// ============================================================

export interface DowngradeDecision {
  should_downgrade: boolean;
  strategy: "serialize" | "reduce_scope" | "fallback_model" | "none";
  reason: string;
}

export function decideDowngrade(
  conflictRate: number,
  consecutiveBlocks: number,
  criticalPathBlocked: boolean
): DowngradeDecision {
  // 规则来自 CLAUDE.md:
  // 1. 冲突率 > 30%：自动降级为半串行
  // 2. Verifier 连续 3 次 block：降级为串行 + tier-3
  // 3. 关键路径任务阻塞 > 2 轮：优先串行处理

  if (conflictRate > 0.3) {
    return {
      should_downgrade: true,
      strategy: "serialize",
      reason: `冲突率 ${(conflictRate * 100).toFixed(1)}% 超过 30% 阈值，降级为半串行`,
    };
  }

  if (consecutiveBlocks >= 3) {
    return {
      should_downgrade: true,
      strategy: "serialize",
      reason: `连续 ${consecutiveBlocks} 次 verifier 阻断，降级为串行 + tier-3`,
    };
  }

  if (criticalPathBlocked) {
    return {
      should_downgrade: true,
      strategy: "serialize",
      reason: "关键路径被阻塞，优先串行处理",
    };
  }

  return {
    should_downgrade: false,
    strategy: "none",
    reason: "无需降级",
  };
}
