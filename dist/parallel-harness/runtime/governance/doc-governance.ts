/**
 * parallel-harness: Document Governance (P2-4)
 *
 * 组织级知识治理与文档校验。
 * - docs/ 作为 source of truth
 * - 文档 freshness 校验
 * - cross-link 验证
 * - owner 追踪
 */

/** 文档元数据 */
export interface DocMetadata {
  path: string;
  title: string;
  owner?: string;
  last_updated: string;
  stage?: string;
  cross_links: string[];
  freshness_days: number;
}

/** 文档校验结果 */
export interface DocValidationResult {
  path: string;
  valid: boolean;
  issues: DocIssue[];
}

export interface DocIssue {
  type: "stale" | "broken_link" | "no_owner" | "incomplete" | "orphan";
  severity: "info" | "warning" | "error";
  message: string;
}

/** 文档校验配置 */
export interface DocGovernanceConfig {
  /** 文档根目录 */
  docs_root: string;
  /** 过期天数阈值 */
  staleness_threshold_days: number;
  /** 是否要求 owner */
  require_owner: boolean;
  /** 是否检查 cross-links */
  check_cross_links: boolean;
}

const DEFAULT_DOC_CONFIG: DocGovernanceConfig = {
  docs_root: "docs",
  staleness_threshold_days: 90,
  require_owner: false,
  check_cross_links: true,
};

/** 文档治理引擎 */
export class DocGovernanceEngine {
  private config: DocGovernanceConfig;

  constructor(config: Partial<DocGovernanceConfig> = {}) {
    this.config = { ...DEFAULT_DOC_CONFIG, ...config };
  }

  /** 校验单个文档 */
  validateDoc(meta: DocMetadata): DocValidationResult {
    const issues: DocIssue[] = [];

    // 检查 freshness
    if (meta.freshness_days > this.config.staleness_threshold_days) {
      issues.push({
        type: "stale",
        severity: "warning",
        message: `文档已 ${meta.freshness_days} 天未更新 (阈值: ${this.config.staleness_threshold_days} 天)`,
      });
    }

    // 检查 owner
    if (this.config.require_owner && !meta.owner) {
      issues.push({
        type: "no_owner",
        severity: "warning",
        message: "文档缺少 owner",
      });
    }

    // 检查 cross-links（简化版：标记空链接）
    if (this.config.check_cross_links && meta.cross_links.length === 0) {
      issues.push({
        type: "orphan",
        severity: "info",
        message: "文档没有交叉引用其他文档",
      });
    }

    return {
      path: meta.path,
      valid: issues.filter(i => i.severity === "error").length === 0,
      issues,
    };
  }

  /** 批量校验 */
  validateAll(docs: DocMetadata[]): DocValidationResult[] {
    return docs.map(d => this.validateDoc(d));
  }

  /** 生成治理报告 */
  generateReport(results: DocValidationResult[]): {
    total_docs: number;
    valid_docs: number;
    issue_counts: Record<DocIssue["type"], number>;
    critical_issues: DocIssue[];
  } {
    const issueCounts: Record<DocIssue["type"], number> = {
      stale: 0,
      broken_link: 0,
      no_owner: 0,
      incomplete: 0,
      orphan: 0,
    };

    const criticalIssues: DocIssue[] = [];

    for (const result of results) {
      for (const issue of result.issues) {
        issueCounts[issue.type]++;
        if (issue.severity === "error") {
          criticalIssues.push(issue);
        }
      }
    }

    return {
      total_docs: results.length,
      valid_docs: results.filter(r => r.valid).length,
      issue_counts: issueCounts,
      critical_issues: criticalIssues,
    };
  }
}
