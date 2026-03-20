/**
 * 验证结果 schema
 *
 * 定义验证器产出的结构化结果，包括单条发现（Finding）、
 * 单个验证器的运行结果（VerifierResult）以及多验证器
 * 汇总结果（SynthesizedResult）。
 */

import type { VerifierType } from './types.js';

// ─── 单条发现 ───────────────────────────────────────────

/** 验证器发现的单个问题或信息 */
export interface Finding {
  /** 严重程度 */
  severity: 'error' | 'warning' | 'info';
  /** 问题描述 */
  message: string;
  /** 相关文件路径（可选） */
  file?: string;
  /** 相关行号（可选） */
  line?: number;
  /** 触发的规则名称（可选，如 eslint 规则名） */
  rule?: string;
}

// ─── 验证器结果 ─────────────────────────────────────────

/** 验证器状态 */
export type VerifierStatus = 'pass' | 'fail' | 'warn' | 'skip';

/** 单个验证器的运行结果 */
export interface VerifierResult {
  /** 验证器类型 */
  verifier_type: VerifierType;
  /** 关联的任务 id */
  task_id: string;
  /** 验证状态 */
  status: VerifierStatus;
  /** 质量评分 0-100 */
  score: number;
  /** 发现的问题列表 */
  findings: Finding[];
  /** 验证完成的时间戳（ISO 8601 格式） */
  timestamp: string;
  /** 任意扩展元数据（可选） */
  metadata?: Record<string, unknown>;
}

// ─── 汇总结果 ───────────────────────────────────────────

/** 多验证器汇总后的综合结果 */
export interface SynthesizedResult {
  /** 关联的任务 id */
  task_id: string;
  /** 各验证器的运行结果 */
  results: VerifierResult[];
  /** 综合状态（取所有结果中最严重的状态） */
  overall_status: VerifierStatus;
  /** 综合评分 0-100（各验证器评分的加权平均） */
  overall_score: number;
  /** 人类可读的汇总说明 */
  summary: string;
  /** 汇总完成的时间戳（ISO 8601 格式） */
  timestamp: string;
}

// ─── 工厂函数 ───────────────────────────────────────────

/**
 * 创建 VerifierResult，未指定字段使用合理默认值。
 * @param partial - 部分 VerifierResult 字段覆盖
 */
export function createVerifierResult(
  partial: Partial<VerifierResult> = {},
): VerifierResult {
  return {
    verifier_type: partial.verifier_type ?? 'test',
    task_id: partial.task_id ?? '',
    status: partial.status ?? 'skip',
    score: partial.score ?? 0,
    findings: partial.findings ?? [],
    timestamp: partial.timestamp ?? new Date().toISOString(),
    metadata: partial.metadata,
  };
}

/**
 * 创建 SynthesizedResult，未指定字段使用合理默认值。
 * @param partial - 部分 SynthesizedResult 字段覆盖
 */
export function createSynthesizedResult(
  partial: Partial<SynthesizedResult> = {},
): SynthesizedResult {
  return {
    task_id: partial.task_id ?? '',
    results: partial.results ?? [],
    overall_status: partial.overall_status ?? 'skip',
    overall_score: partial.overall_score ?? 0,
    summary: partial.summary ?? '',
    timestamp: partial.timestamp ?? new Date().toISOString(),
  };
}

// ─── 判断函数 ───────────────────────────────────────────

/**
 * 判断单个验证结果是否视为"通过"。
 * 通过条件：
 * - status 为 'pass' 或 'warn'（警告不阻断流程）
 * - score >= 60（最低及格线）
 */
export function isPassingResult(result: VerifierResult): boolean {
  const passingStatuses: VerifierStatus[] = ['pass', 'warn'];
  return passingStatuses.includes(result.status) && result.score >= 60;
}
