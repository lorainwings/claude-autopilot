/**
 * 角色合同 schema
 *
 * 定义四种核心角色（Planner / Worker / Verifier / Synthesizer）的
 * 输入输出契约、失败语义和资源边界。
 * 每个角色合同精确描述了该角色"能做什么"和"不能做什么"，
 * 用于在运行时强制执行最小权限原则。
 */

import type { RoleType, VerifierType } from './types.js';
import type { TaskNode, TaskGraph } from './task-graph.js';
import type { ContextPack } from './context-pack.js';
import type { VerifierResult, SynthesizedResult } from './verifier-result.js';

// ─── 失败语义 ───────────────────────────────────────────

/** 角色执行失败时的行为定义 */
export interface FailureSemantics {
  /** 是否允许重试 */
  retry_allowed: boolean;
  /** 最大重试次数（仅当 retry_allowed 为 true 时有效） */
  max_retries: number;
  /** 最终失败时的回退动作 */
  fallback_action: 'skip' | 'escalate' | 'abort';
  /** 错误报告方式 */
  error_reporting: 'inline' | 'event_bus';
}

// ─── 资源边界 ───────────────────────────────────────────

/** 角色可使用的资源限制 */
export interface ResourceBoundary {
  /** 允许访问的文件路径 glob 模式 */
  allowed_paths: string[];
  /** 禁止访问的文件路径 glob 模式 */
  forbidden_paths: string[];
  /** 最大 token 消耗量 */
  max_tokens: number;
  /** 允许使用的工具列表 */
  allowed_tools: string[];
  /** 是否允许网络访问 */
  network_access: boolean;
}

// ─── 角色合同（泛型） ──────────────────────────────────

/**
 * 角色合同泛型接口。
 * TInput 和 TOutput 分别描述该角色的输入和输出类型，
 * 在编译时提供类型安全保障。
 */
export interface RoleContract<TInput = unknown, TOutput = unknown> {
  /** 角色类型 */
  role: RoleType;
  /** 输入类型描述（用于运行时文档和调试） */
  input_schema: string;
  /** 输出类型描述（用于运行时文档和调试） */
  output_schema: string;
  /** 失败语义 */
  failure_semantics: FailureSemantics;
  /** 资源边界 */
  resource_boundary: ResourceBoundary;
  /**
   * 以下两个幻象字段仅用于类型推断，不会在运行时赋值。
   * 通过 TypeScript 的条件类型和 infer 关键字，
   * 可以从 RoleContract 实例推导出 TInput 和 TOutput。
   */
  readonly _input?: TInput;
  readonly _output?: TOutput;
}

// ─── 文件变更描述 ───────────────────────────────────────

/** Worker 角色的输出：文件变更列表 */
export interface FileChange {
  /** 文件路径 */
  path: string;
  /** 变更类型 */
  action: 'create' | 'modify' | 'delete';
  /** 变更后的文件内容（delete 时为空） */
  content?: string;
}

// ─── 预定义角色合同 ────────────────────────────────────

/**
 * Planner 角色合同
 * - 输入：用户意图字符串
 * - 输出：TaskGraph
 * - 可重试 2 次，最终失败时 abort（规划失败意味着无法继续）
 * - 允许读取所有文件以分析代码库结构，但不允许修改任何文件
 */
export const PLANNER_CONTRACT: RoleContract<string, TaskGraph> = {
  role: 'planner',
  input_schema: 'string (用户意图描述)',
  output_schema: 'TaskGraph (任务有向无环图)',
  failure_semantics: {
    retry_allowed: true,
    max_retries: 2,
    fallback_action: 'abort',
    error_reporting: 'event_bus',
  },
  resource_boundary: {
    allowed_paths: ['**/*'],
    forbidden_paths: [],
    max_tokens: 32768,
    allowed_tools: ['read', 'glob', 'grep'],
    network_access: false,
  },
};

/**
 * Worker 角色合同
 * - 输入：TaskNode + ContextPack
 * - 输出：FileChange[]（文件变更列表）
 * - 可重试 3 次，最终失败时 escalate（上报给协调器决策）
 * - 只能访问 TaskNode.allowed_paths 中指定的路径
 */
export const WORKER_CONTRACT: RoleContract<
  { task: TaskNode; context: ContextPack },
  FileChange[]
> = {
  role: 'worker',
  input_schema: '{ task: TaskNode, context: ContextPack }',
  output_schema: 'FileChange[] (文件变更列表)',
  failure_semantics: {
    retry_allowed: true,
    max_retries: 3,
    fallback_action: 'escalate',
    error_reporting: 'event_bus',
  },
  resource_boundary: {
    // 实际路径在运行时由 TaskNode.allowed_paths 动态填充
    allowed_paths: [],
    forbidden_paths: ['node_modules/**', '.git/**'],
    max_tokens: 16384,
    allowed_tools: ['read', 'write', 'bash', 'glob', 'grep'],
    network_access: false,
  },
};

/**
 * Verifier 角色合同
 * - 输入：TaskNode + FileChange[]（待验证的任务和变更）
 * - 输出：VerifierResult
 * - 可重试 1 次，最终失败时 skip（跳过该验证器，不阻塞流程）
 * - 只读访问，不允许修改任何文件
 */
export const VERIFIER_CONTRACT: RoleContract<
  { task: TaskNode; changes: FileChange[] },
  VerifierResult
> = {
  role: 'verifier',
  input_schema: '{ task: TaskNode, changes: FileChange[] }',
  output_schema: 'VerifierResult (验证运行结果)',
  failure_semantics: {
    retry_allowed: true,
    max_retries: 1,
    fallback_action: 'skip',
    error_reporting: 'inline',
  },
  resource_boundary: {
    allowed_paths: ['**/*'],
    forbidden_paths: [],
    max_tokens: 8192,
    allowed_tools: ['read', 'glob', 'grep', 'bash'],
    network_access: false,
  },
};

/**
 * Synthesizer 角色合同
 * - 输入：VerifierResult[]（所有验证器的结果）
 * - 输出：SynthesizedResult（汇总结果）
 * - 不允许重试，最终失败时 escalate（汇总失败需要人工介入）
 * - 只读访问，不允许修改任何文件
 */
export const SYNTHESIZER_CONTRACT: RoleContract<
  VerifierResult[],
  SynthesizedResult
> = {
  role: 'synthesizer',
  input_schema: 'VerifierResult[] (各验证器运行结果)',
  output_schema: 'SynthesizedResult (汇总结果)',
  failure_semantics: {
    retry_allowed: false,
    max_retries: 0,
    fallback_action: 'escalate',
    error_reporting: 'event_bus',
  },
  resource_boundary: {
    allowed_paths: ['**/*'],
    forbidden_paths: [],
    max_tokens: 8192,
    allowed_tools: ['read', 'glob', 'grep'],
    network_access: false,
  },
};
