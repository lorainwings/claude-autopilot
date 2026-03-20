/**
 * base-verifier.ts — 验证器抽象基类
 *
 * 定义所有验证器的通用接口和辅助方法。
 * 各具体验证器（test / review / security / perf）均继承此类。
 */

import type {
  VerifierType,
  VerifierResult,
  Finding,
  TaskNode,
} from '../schemas';
import { createVerifierResult } from '../schemas';

// ---------------------------------------------------------------------------
// 类型定义
// ---------------------------------------------------------------------------

/** 验证器配置 */
export interface VerifierConfig {
  /** 是否启用该验证器 */
  enabled: boolean;
  /** 超时毫秒数 */
  timeout_ms: number;
  /** 最低报告严重级别（低于此级别的发现将被忽略） */
  severity_threshold: 'error' | 'warning' | 'info';
}

/** 文件变更描述 */
export interface FileChange {
  /** 文件路径 */
  path: string;
  /** 变更类型 */
  type: 'add' | 'modify' | 'delete';
  /** 文件完整内容（仅 add / modify 时提供） */
  content?: string;
  /** diff 文本（仅 modify 时提供） */
  diff?: string;
}

// ---------------------------------------------------------------------------
// 默认配置
// ---------------------------------------------------------------------------

/** 默认验证器配置 */
const DEFAULT_CONFIG: VerifierConfig = {
  enabled: true,
  timeout_ms: 30_000,
  severity_threshold: 'info',
};

// ---------------------------------------------------------------------------
// 抽象基类
// ---------------------------------------------------------------------------

/**
 * BaseVerifier — 验证器抽象基类
 *
 * 子类需要实现:
 *   - readonly type: VerifierType
 *   - verify(node, changes): Promise<VerifierResult>
 */
export abstract class BaseVerifier {
  /** 验证器类型标识 */
  abstract readonly type: VerifierType;

  /** 当前配置（可被子类 / 外部覆盖） */
  protected config: VerifierConfig;

  constructor(config?: Partial<VerifierConfig>) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  // -----------------------------------------------------------------------
  // 抽象方法
  // -----------------------------------------------------------------------

  /**
   * 执行验证
   * @param node   当前任务节点
   * @param changes 本次变更的文件列表
   * @returns 验证结果
   */
  abstract verify(
    node: TaskNode,
    changes: FileChange[],
  ): Promise<VerifierResult>;

  // -----------------------------------------------------------------------
  // 辅助方法
  // -----------------------------------------------------------------------

  /**
   * 使用工厂函数创建标准化的 VerifierResult
   * 自动填入 verifier_type 和 timestamp
   */
  protected createResult(partial: Partial<VerifierResult>): VerifierResult {
    return createVerifierResult({
      verifier_type: this.type,
      timestamp: new Date().toISOString(),
      ...partial,
    });
  }

  /**
   * 创建单条 Finding 对象
   */
  protected createFinding(
    severity: Finding['severity'],
    message: string,
    file?: string,
    line?: number,
    rule?: string,
  ): Finding {
    const finding: Finding = { severity, message };
    if (file !== undefined) finding.file = file;
    if (line !== undefined) finding.line = line;
    if (rule !== undefined) finding.rule = rule;
    return finding;
  }

  /** 当前验证器是否启用 */
  isEnabled(): boolean {
    return this.config.enabled;
  }

  /** 获取当前验证器配置的副本 */
  getConfig(): VerifierConfig {
    return { ...this.config };
  }
}
