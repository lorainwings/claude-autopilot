/**
 * parallel-harness 基础类型定义
 *
 * 所有 schema 模块共享的原子类型在此统一定义，
 * 避免循环依赖和重复声明。
 */

// ─── 模型层级 ───────────────────────────────────────────
// tier-1: 最强模型（如 opus），用于规划和复杂推理
// tier-2: 中等模型（如 sonnet），用于常规编码任务
// tier-3: 轻量模型（如 haiku），用于简单验证和格式化
export type ModelTier = 'tier-1' | 'tier-2' | 'tier-3';

// ─── 风险级别 ───────────────────────────────────────────
// 决定任务执行时的审查强度和验证要求
export type RiskLevel = 'low' | 'medium' | 'high' | 'critical';

// ─── 任务状态 ───────────────────────────────────────────
// pending     → 等待依赖完成
// ready       → 依赖已满足，可被调度
// in_progress → 正在执行
// completed   → 执行成功
// failed      → 执行失败
// blocked     → 被外部因素阻塞
export type TaskStatus =
  | 'pending'
  | 'ready'
  | 'in_progress'
  | 'completed'
  | 'failed'
  | 'blocked';

// ─── 角色类型 ───────────────────────────────────────────
// planner     → 分解用户意图为任务图
// worker      → 执行具体编码任务
// verifier    → 验证任务产出物
// synthesizer → 汇总验证结果
export type RoleType = 'planner' | 'worker' | 'verifier' | 'synthesizer';

// ─── 验证器类型 ─────────────────────────────────────────
// test     → 单元/集成测试验证
// review   → 代码审查
// security → 安全扫描
// perf     → 性能基准测试
export type VerifierType = 'test' | 'review' | 'security' | 'perf';

// ─── 意图分析相关类型 ───────────────────────────────────
// 用于 Planner 阶段的意图识别和任务拆分策略

/** 意图类型：用户请求的大类 */
export type IntentType = 'feature' | 'bugfix' | 'refactor' | 'test' | 'docs' | 'unknown';

/** 拆分策略：决定如何将意图拆分为多个并行任务 */
export type SplitStrategy = 'file-based' | 'layer-based' | 'feature-based';

/** 意图分析结果 */
export interface IntentAnalysis {
  /** 意图类型 */
  type: IntentType;
  /** 影响范围（文件或模块列表） */
  scope: string[];
  /** 复杂度评估 */
  complexity: 'low' | 'medium' | 'high';
  /** 推荐的模型层级 */
  recommended_model_tier: ModelTier;
  /** 推荐的拆分策略 */
  split_strategy: SplitStrategy;
  /** 意图的自然语言描述 */
  description: string;
}

// ─── 所有权映射 ─────────────────────────────────────────
// 用于追踪任务与文件路径之间的所有权关系

/** 所有权映射：记录任务对文件路径的独占/共享访问权 */
export interface OwnershipMapping {
  /** 关联的任务 id */
  task_id: string;
  /** 分配的角色 */
  role: string;
  /** 允许访问的文件路径 */
  allowed_paths: string[];
  /** 禁止访问的文件路径 */
  forbidden_paths: string[];
}

/** 路径冲突信息：两个或多个任务尝试修改同一文件时的冲突描述 */
export interface ConflictInfo {
  /** 冲突的文件路径 */
  path: string;
  /** 涉及冲突的任务 id 列表 */
  tasks: string[];
  /** 解决策略 */
  resolution: 'serialize' | 'split' | 'merge';
}
