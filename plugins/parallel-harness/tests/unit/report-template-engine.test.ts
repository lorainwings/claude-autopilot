import { describe, it, expect } from "bun:test";
import {
  ReportTemplateEngine,
  EngineeringReportTemplate,
  ManagementReportTemplate,
  AuditReportTemplate,
  ReleaseReportTemplate,
} from "../../runtime/integrations/report-template-engine";
import type { ReportContext } from "../../runtime/integrations/report-template-engine";
import type { RunReport } from "../../runtime/integrations/report-aggregator";

function createMockReport(): RunReport {
  return {
    run_id: "run_test",
    summary: "完成 5 个任务，失败 1 个",
    evidence_refs: [
      { type: "gate", ref_id: "test", description: "test [hard]: 通过", strength: "hard" },
      { type: "gate", ref_id: "review", description: "review [signal]: 通过", strength: "signal" },
      { type: "attestation", ref_id: "att_1", description: "执行证明" },
    ],
    quality_summary: {
      overall_grade: "B",
      gate_summary: "2/2 gates 通过",
      cost_summary: "总成本: 50",
      hard_gate_summary: "1/1 hard gates 通过",
      signal_gate_summary: "1/1 signal gates 通过",
    },
  };
}

function createMockContext(overrides: Partial<ReportContext> = {}): ReportContext {
  return {
    run_id: "run_test",
    intent: "测试功能开发",
    affected_modules: ["module-a", "module-b"],
    start_time: "2026-04-01T10:00:00Z",
    end_time: "2026-04-01T11:00:00Z",
    task_count: 5,
    completed_count: 4,
    failed_count: 1,
    ...overrides,
  };
}

describe("ReportTemplateEngine", () => {
  it("注册了 4 个默认模板", () => {
    const engine = new ReportTemplateEngine();
    const templates = engine.listTemplates();
    expect(templates).toHaveLength(4);
    expect(templates.map(t => t.type)).toContain("engineering");
    expect(templates.map(t => t.type)).toContain("management");
    expect(templates.map(t => t.type)).toContain("audit");
    expect(templates.map(t => t.type)).toContain("release");
  });

  it("render 返回结构化报告", () => {
    const engine = new ReportTemplateEngine();
    const result = engine.render(createMockReport(), createMockContext(), "engineering");
    expect(result.report_type).toBe("engineering");
    expect(result.executive_summary).toBeDefined();
    expect(result.scope.run_id).toBe("run_test");
    expect(result.sections.length).toBeGreaterThan(0);
  });

  it("renderAll 返回所有模板的报告", () => {
    const engine = new ReportTemplateEngine();
    const results = engine.renderAll(createMockReport(), createMockContext());
    expect(results).toHaveLength(4);
  });

  it("未注册模板类型时抛错", () => {
    const engine = new ReportTemplateEngine();
    expect(() => engine.render(createMockReport(), createMockContext(), "unknown" as any)).toThrow("未注册");
  });
});

describe("EngineeringReportTemplate", () => {
  it("包含 gate 检查和成本分析 sections", () => {
    const template = new EngineeringReportTemplate();
    const result = template.render(createMockReport(), createMockContext());
    expect(result.sections.some(s => s.title.includes("Gate"))).toBe(true);
    expect(result.sections.some(s => s.title.includes("成本"))).toBe(true);
  });

  it("失败任务产生高风险评估", () => {
    const template = new EngineeringReportTemplate();
    const result = template.render(createMockReport(), createMockContext({ failed_count: 3 }));
    expect(result.risk_summary.overall_risk).toBe("high");
    expect(result.unresolved_items.length).toBeGreaterThan(0);
  });

  it("无失败时低风险", () => {
    const template = new EngineeringReportTemplate();
    const result = template.render(createMockReport(), createMockContext({ failed_count: 0 }));
    expect(result.risk_summary.overall_risk).toBe("low");
  });
});

describe("ManagementReportTemplate", () => {
  it("包含完成率信息", () => {
    const template = new ManagementReportTemplate();
    const result = template.render(createMockReport(), createMockContext());
    expect(result.executive_summary).toContain("80.0%");
  });
});

describe("AuditReportTemplate", () => {
  it("包含完整证据链", () => {
    const template = new AuditReportTemplate();
    const result = template.render(createMockReport(), createMockContext());
    expect(result.evidence_refs).toHaveLength(3);
    expect(result.sections.some(s => s.title.includes("证据链"))).toBe(true);
  });
});

describe("ReleaseReportTemplate", () => {
  it("所有条件满足时发布就绪", () => {
    const template = new ReleaseReportTemplate();
    const result = template.render(createMockReport(), createMockContext({ failed_count: 0 }));
    expect(result.executive_summary).toContain("发布就绪");
    expect(result.risk_summary.overall_risk).toBe("low");
  });

  it("有失败任务时发布未就绪", () => {
    const template = new ReleaseReportTemplate();
    const result = template.render(createMockReport(), createMockContext({ failed_count: 2 }));
    expect(result.executive_summary).toContain("发布未就绪");
    expect(result.risk_summary.overall_risk).toBe("high");
  });
});
