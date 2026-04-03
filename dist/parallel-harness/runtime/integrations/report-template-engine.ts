/**
 * parallel-harness: Report Template Engine
 *
 * 多模板交付引擎。支持工程版、管理版、审计版、发布版四种报告模板。
 * 每种报告包含: executive_summary, scope, evidence_refs, risk_summary,
 * unresolved_items, rollback_plan。
 */

import type { RunReport, EvidenceReference } from "./report-aggregator";

// ============================================================
// Report Template 类型
// ============================================================

export type ReportType = "engineering" | "management" | "audit" | "release";

export interface StructuredReport {
  report_type: ReportType;
  title: string;
  generated_at: string;
  executive_summary: string;
  scope: ReportScope;
  evidence_refs: EvidenceReference[];
  risk_summary: RiskSummary;
  unresolved_items: UnresolvedItem[];
  rollback_plan: string;
  follow_up_actions: string[];
  sections: ReportSection[];
}

export interface ReportScope {
  run_id: string;
  intent: string;
  affected_modules: string[];
  time_range: { start: string; end: string };
}

export interface RiskSummary {
  overall_risk: "low" | "medium" | "high" | "critical";
  risk_factors: Array<{ factor: string; severity: string; mitigation: string }>;
}

export interface UnresolvedItem {
  id: string;
  description: string;
  severity: "low" | "medium" | "high";
  owner?: string;
  deadline?: string;
}

export interface ReportSection {
  title: string;
  content: string;
  priority: "high" | "medium" | "low";
}

// ============================================================
// Report Template 接口
// ============================================================

export interface ReportTemplate {
  type: ReportType;
  name: string;
  description: string;
  render(report: RunReport, context: ReportContext): StructuredReport;
}

export interface ReportContext {
  run_id: string;
  intent: string;
  affected_modules: string[];
  start_time: string;
  end_time: string;
  task_count: number;
  completed_count: number;
  failed_count: number;
}

// ============================================================
// 工程版报告模板
// ============================================================

export class EngineeringReportTemplate implements ReportTemplate {
  type: ReportType = "engineering";
  name = "工程报告";
  description = "面向开发团队的技术细节报告";

  render(report: RunReport, context: ReportContext): StructuredReport {
    const hardGates = report.evidence_refs.filter(e => e.strength === "hard");
    const signalGates = report.evidence_refs.filter(e => e.strength === "signal");

    return {
      report_type: "engineering",
      title: `工程报告 — Run ${context.run_id}`,
      generated_at: new Date().toISOString(),
      executive_summary: `完成 ${context.completed_count}/${context.task_count} 个任务。${report.quality_summary.overall_grade} 级质量。`,
      scope: {
        run_id: context.run_id,
        intent: context.intent,
        affected_modules: context.affected_modules,
        time_range: { start: context.start_time, end: context.end_time },
      },
      evidence_refs: report.evidence_refs,
      risk_summary: this.assessRisk(report, context),
      unresolved_items: this.extractUnresolved(report, context),
      rollback_plan: `git revert 至 run ${context.run_id} 之前的 commit`,
      follow_up_actions: this.suggestFollowUp(report, context),
      sections: [
        { title: "Gate 检查结果", content: `Hard gates: ${report.quality_summary.hard_gate_summary}\nSignal gates: ${report.quality_summary.signal_gate_summary}`, priority: "high" },
        { title: "成本分析", content: report.quality_summary.cost_summary, priority: "medium" },
        { title: "测试证据", content: `${hardGates.length} 个 hard gate, ${signalGates.length} 个 signal gate`, priority: "high" },
      ],
    };
  }

  private assessRisk(report: RunReport, context: ReportContext): RiskSummary {
    const factors: Array<{ factor: string; severity: string; mitigation: string }> = [];

    if (context.failed_count > 0) {
      factors.push({ factor: `${context.failed_count} 个任务失败`, severity: "high", mitigation: "检查失败任务日志并修复" });
    }

    const overallRisk = factors.some(f => f.severity === "high") ? "high"
      : factors.some(f => f.severity === "medium") ? "medium" : "low";

    return { overall_risk: overallRisk, risk_factors: factors };
  }

  private extractUnresolved(_report: RunReport, context: ReportContext): UnresolvedItem[] {
    const items: UnresolvedItem[] = [];
    if (context.failed_count > 0) {
      items.push({
        id: "unresolved_failures",
        description: `${context.failed_count} 个任务执行失败需要排查`,
        severity: "high",
      });
    }
    return items;
  }

  private suggestFollowUp(_report: RunReport, context: ReportContext): string[] {
    const actions: string[] = [];
    if (context.failed_count > 0) actions.push("排查失败任务并重试");
    actions.push("代码审查合并后的变更");
    return actions;
  }
}

// ============================================================
// 管理版报告模板
// ============================================================

export class ManagementReportTemplate implements ReportTemplate {
  type: ReportType = "management";
  name = "管理报告";
  description = "面向项目管理层的进度和风险报告";

  render(report: RunReport, context: ReportContext): StructuredReport {
    const successRate = context.task_count > 0
      ? ((context.completed_count / context.task_count) * 100).toFixed(1) : "0";

    return {
      report_type: "management",
      title: `管理报告 — Run ${context.run_id}`,
      generated_at: new Date().toISOString(),
      executive_summary: `任务完成率 ${successRate}%。整体质量等级: ${report.quality_summary.overall_grade}。`,
      scope: {
        run_id: context.run_id,
        intent: context.intent,
        affected_modules: context.affected_modules,
        time_range: { start: context.start_time, end: context.end_time },
      },
      evidence_refs: report.evidence_refs.filter(e => e.strength === "hard"),
      risk_summary: {
        overall_risk: context.failed_count > 0 ? "high" : "low",
        risk_factors: context.failed_count > 0
          ? [{ factor: "任务失败", severity: "high", mitigation: "安排修复迭代" }]
          : [],
      },
      unresolved_items: context.failed_count > 0
        ? [{ id: "failures", description: `${context.failed_count} 个任务待修复`, severity: "high" as const }]
        : [],
      rollback_plan: "回滚至上一个稳定版本",
      follow_up_actions: ["安排下一轮迭代", "更新项目进度"],
      sections: [
        { title: "项目进度", content: `已完成 ${context.completed_count}/${context.task_count} 个任务`, priority: "high" },
        { title: "质量概览", content: report.quality_summary.gate_summary, priority: "medium" },
      ],
    };
  }
}

// ============================================================
// 审计版报告模板
// ============================================================

export class AuditReportTemplate implements ReportTemplate {
  type: ReportType = "audit";
  name = "审计报告";
  description = "面向合规审计的完整证据链报告";

  render(report: RunReport, context: ReportContext): StructuredReport {
    return {
      report_type: "audit",
      title: `审计报告 — Run ${context.run_id}`,
      generated_at: new Date().toISOString(),
      executive_summary: `Run ${context.run_id} 完整审计记录。${report.evidence_refs.length} 项证据。`,
      scope: {
        run_id: context.run_id,
        intent: context.intent,
        affected_modules: context.affected_modules,
        time_range: { start: context.start_time, end: context.end_time },
      },
      evidence_refs: report.evidence_refs,
      risk_summary: {
        overall_risk: "low",
        risk_factors: [],
      },
      unresolved_items: [],
      rollback_plan: "按审计要求执行回滚流程",
      follow_up_actions: ["归档审计记录", "更新合规状态"],
      sections: [
        { title: "完整证据链", content: report.evidence_refs.map(e => `[${e.type}] ${e.ref_id}: ${e.description}`).join("\n"), priority: "high" },
        { title: "Gate 合规检查", content: `${report.quality_summary.hard_gate_summary}\n${report.quality_summary.signal_gate_summary}`, priority: "high" },
        { title: "成本审计", content: report.quality_summary.cost_summary, priority: "medium" },
      ],
    };
  }
}

// ============================================================
// 发布版报告模板
// ============================================================

export class ReleaseReportTemplate implements ReportTemplate {
  type: ReportType = "release";
  name = "发布报告";
  description = "面向发布决策的就绪检查报告";

  render(report: RunReport, context: ReportContext): StructuredReport {
    const allGatesPassed = !report.quality_summary.hard_gate_summary.includes("0/");
    const readiness = allGatesPassed && context.failed_count === 0;

    return {
      report_type: "release",
      title: `发布报告 — Run ${context.run_id}`,
      generated_at: new Date().toISOString(),
      executive_summary: readiness
        ? `发布就绪。所有 hard gates 通过，无失败任务。`
        : `发布未就绪。需解决未通过项。`,
      scope: {
        run_id: context.run_id,
        intent: context.intent,
        affected_modules: context.affected_modules,
        time_range: { start: context.start_time, end: context.end_time },
      },
      evidence_refs: report.evidence_refs,
      risk_summary: {
        overall_risk: readiness ? "low" : "high",
        risk_factors: readiness ? [] : [{ factor: "发布条件未满足", severity: "high", mitigation: "修复未通过项后重新评估" }],
      },
      unresolved_items: readiness ? [] : [{ id: "release_block", description: "发布条件未满足", severity: "high" as const }],
      rollback_plan: "使用 git revert 回滚至发布前状态",
      follow_up_actions: readiness
        ? ["执行发布流程", "通知相关方"]
        : ["修复阻断项", "重新运行发布检查"],
      sections: [
        { title: "发布就绪状态", content: readiness ? "就绪" : "未就绪", priority: "high" },
        { title: "Hard Gate 结果", content: report.quality_summary.hard_gate_summary, priority: "high" },
        { title: "Signal Gate 结果", content: report.quality_summary.signal_gate_summary, priority: "medium" },
      ],
    };
  }
}

// ============================================================
// Report Template Engine
// ============================================================

export class ReportTemplateEngine {
  private templates: Map<ReportType, ReportTemplate> = new Map();

  constructor() {
    this.registerDefaults();
  }

  private registerDefaults(): void {
    this.register(new EngineeringReportTemplate());
    this.register(new ManagementReportTemplate());
    this.register(new AuditReportTemplate());
    this.register(new ReleaseReportTemplate());
  }

  register(template: ReportTemplate): void {
    this.templates.set(template.type, template);
  }

  render(report: RunReport, context: ReportContext, type: ReportType): StructuredReport {
    const template = this.templates.get(type);
    if (!template) throw new Error(`未注册的报告模板类型: ${type}`);
    return template.render(report, context);
  }

  renderAll(report: RunReport, context: ReportContext): StructuredReport[] {
    return Array.from(this.templates.values()).map(t => t.render(report, context));
  }

  listTemplates(): Array<{ type: ReportType; name: string; description: string }> {
    return Array.from(this.templates.values()).map(t => ({
      type: t.type,
      name: t.name,
      description: t.description,
    }));
  }
}

// ============================================================
// P1-3: Report 主链化 — 接入 finalize 流程
// ============================================================

/** 在 finalize 阶段生成所有报告 */
export function generateFinalReports(
  engine: ReportTemplateEngine,
  data: {
    run_id: string;
    run_result: import("../schemas/ga-schemas").RunResult;
    evidence_refs: Array<{ ref_id: string; kind: string; description: string }>;
    gate_results: import("../schemas/ga-schemas").GateResult[];
    grounding_refs?: Array<{ category: string; criterion: string; met: boolean }>;
    risk_items?: Array<{ severity: string; description: string; mitigation?: string }>;
  }
): Map<string, StructuredReport> {
  const reports = new Map<string, StructuredReport>();
  const templates = engine.listTemplates();

  // 按 hard/signal 分类 gate 结果
  const hardGates = data.gate_results.filter(g => g.blocking);
  const signalGates = data.gate_results.filter(g => !g.blocking);

  // 构建 RunReport — 保留原始 evidence 类型和强度
  const runReport: RunReport = {
    run_id: data.run_id,
    summary: `完成 ${data.run_result.completed_tasks.length} 个任务，失败 ${data.run_result.failed_tasks.length} 个`,
    evidence_refs: data.evidence_refs.map(ref => {
      // 从 kind 映射到 EvidenceReference.type，保留原始语义
      const typeMap: Record<string, EvidenceReference["type"]> = {
        gate: "gate", attestation: "attestation", artifact: "artifact",
        test: "gate", file: "artifact", doc: "artifact",
      };
      return {
        type: typeMap[ref.kind] || "artifact",
        ref_id: ref.ref_id,
        description: ref.description,
        // 不强行标记 strength — 由 gate_results 分类决定
      };
    }),
    quality_summary: {
      overall_grade: data.run_result.quality_report.overall_grade,
      gate_summary: `${data.gate_results.filter(g => g.passed).length}/${data.gate_results.length} gates 通过`,
      cost_summary: `总成本: ${data.run_result.cost_summary.total_cost}`,
      hard_gate_summary: `${hardGates.filter(g => g.passed).length}/${hardGates.length} hard gates 通过`,
      signal_gate_summary: `${signalGates.filter(g => g.passed).length}/${signalGates.length} signal gates 通过`,
    },
  };

  // 构建 ReportContext — 使用 run 真实起止时间
  const startTime = data.run_result.completed_at
    ? new Date(new Date(data.run_result.completed_at).getTime() - data.run_result.total_duration_ms).toISOString()
    : new Date().toISOString();

  const context: ReportContext = {
    run_id: data.run_id,
    intent: "finalize",
    affected_modules: [],
    start_time: startTime,
    end_time: data.run_result.completed_at,
    task_count: data.run_result.completed_tasks.length + data.run_result.failed_tasks.length + data.run_result.skipped_tasks.length,
    completed_count: data.run_result.completed_tasks.length,
    failed_count: data.run_result.failed_tasks.length,
  };

  for (const tmpl of templates) {
    try {
      const report = engine.render(runReport, context, tmpl.type);
      reports.set(tmpl.type, report);
    } catch {
      // 单个模板渲染失败不阻断其他模板
    }
  }

  return reports;
}
