/**
 * parallel-harness schema 模块统一导出
 *
 * 所有类型定义、接口、工厂函数和验证函数从此入口导出，
 * 外部模块只需 import from './schemas/index.js' 即可获取全部 API。
 */

// ─── 基础类型 ───────────────────────────────────────────
export type {
  ModelTier,
  RiskLevel,
  TaskStatus,
  RoleType,
  VerifierType,
  IntentType,
  SplitStrategy,
  IntentAnalysis,
  OwnershipMapping,
  ConflictInfo,
} from './types.js';

// ─── 任务图 ─────────────────────────────────────────────
export type {
  TaskNode,
  TaskGraph,
  ValidationResult,
} from './task-graph.js';

export {
  createTaskNode,
  createTaskGraph,
  validateTaskGraph,
  getReadyTasks,
  getTopologicalOrder,
} from './task-graph.js';

// ─── 上下文包 ───────────────────────────────────────────
export type {
  ContextFile,
  ContextConstraints,
  ContextPack,
  ContextPackValidation,
} from './context-pack.js';

export {
  createContextPack,
  validateContextPack,
} from './context-pack.js';

// ─── 验证结果 ───────────────────────────────────────────
export type {
  Finding,
  VerifierStatus,
  VerifierResult,
  SynthesizedResult,
} from './verifier-result.js';

export {
  createVerifierResult,
  createSynthesizedResult,
  isPassingResult,
} from './verifier-result.js';

// ─── 角色合同 ───────────────────────────────────────────
export type {
  FailureSemantics,
  ResourceBoundary,
  RoleContract,
  FileChange,
} from './role-contracts.js';

export {
  PLANNER_CONTRACT,
  WORKER_CONTRACT,
  VERIFIER_CONTRACT,
  SYNTHESIZER_CONTRACT,
} from './role-contracts.js';
