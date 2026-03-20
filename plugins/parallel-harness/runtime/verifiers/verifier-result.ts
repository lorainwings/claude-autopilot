/**
 * parallel-harness: Verifier Result Schema
 *
 * 验证与实现分离是平台的核心原则。
 * 所有 verifier 输出统一结构，由 result-synthesizer 聚合决策。
 *
 * 来源设计：
 * - BMAD-METHOD: verifier 角色契约
 * - Harness: CI/PR 闭环的验证结构
 *
 * 反向增强：
 * - 不只做 PR review 表层，必须接任务历史和验证历史
 * - 每个 verifier 必须输出可操作的修复建议
 */

import type { VerifierType, VerificationDecision } from "../orchestrator/task-graph";

// ============================================================
// 验证结果
// ============================================================

/** 单个验证发现 */
export interface VerifierFinding {
  /** 发现级别 */
  severity: "info" | "warning" | "error" | "critical";

  /** 发现描述 */
  message: string;

  /** 相关文件路径 */
  file_path?: string;

  /** 相关行号 */
  line?: number;

  /** 修复建议 */
  suggestion?: string;

  /** 关联的规则或检查项 ID */
  rule_id?: string;
}

/** 单个 Verifier 的输出 */
export interface VerifierOutput {
  /** 验证器类型 */
  verifier_type: VerifierType;

  /** 是否通过 */
  passed: boolean;

  /** 判定结论 */
  decision: VerificationDecision;

  /** 发现列表 */
  findings: VerifierFinding[];

  /** 摘要 */
  summary: string;

  /** 验证耗时（毫秒） */
  duration_ms: number;

  /** 验证时间戳 */
  verified_at: string;
}

/** 综合验证结果（由 result-synthesizer 生成） */
export interface VerificationResult {
  /** 关联的任务 ID */
  task_id: string;

  /** 各 verifier 输出 */
  verifier_outputs: VerifierOutput[];

  /** 最终决策 */
  final_decision: VerificationDecision;

  /** 决策理由 */
  decision_reasoning: string;

  /** 是否建议重试 */
  should_retry: boolean;

  /** 是否建议降级 */
  should_downgrade: boolean;

  /** 阻断原因（如果 blocked） */
  blocking_reasons: string[];

  /** 综合质量报告 */
  quality_report: QualityReport;
}

/** 质量报告 */
export interface QualityReport {
  /** 测试覆盖评估 */
  test_coverage_assessment: string;

  /** 代码审查评估 */
  code_review_assessment: string;

  /** 安全评估 */
  security_assessment: string;

  /** 性能评估 */
  performance_assessment: string;

  /** 总体质量等级 */
  overall_grade: "A" | "B" | "C" | "D" | "F";
}
