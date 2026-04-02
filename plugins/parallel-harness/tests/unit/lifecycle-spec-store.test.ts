import { describe, it, expect } from "bun:test";
import { LifecycleSpecStore, PHASE_ORDER } from "../../runtime/lifecycle/lifecycle-spec-store";
import type { LifecyclePhase, PhaseArtifact } from "../../runtime/lifecycle/lifecycle-spec-store";

describe("LifecycleSpecStore", () => {
  it("初始化包含所有 8 个阶段", () => {
    const store = new LifecycleSpecStore();
    const phases = store.listPhases();
    expect(phases).toHaveLength(8);
    for (const p of phases) {
      expect(p.status).toBe("not_started");
    }
  });

  it("getSpec 返回指定阶段", () => {
    const store = new LifecycleSpecStore();
    const spec = store.getSpec("requirement");
    expect(spec).toBeDefined();
    expect(spec!.phase).toBe("requirement");
    expect(spec!.required_artifacts).toContain("requirement_spec");
  });

  it("getSpec 对未知阶段返回 undefined", () => {
    const store = new LifecycleSpecStore();
    const spec = store.getSpec("nonexistent" as LifecyclePhase);
    expect(spec).toBeUndefined();
  });

  it("setSpec 更新阶段状态", () => {
    const store = new LifecycleSpecStore();
    store.setSpec("requirement", { status: "in_progress" });
    expect(store.getPhaseStatus("requirement")).toBe("in_progress");
  });

  it("setSpec 对未知阶段抛错", () => {
    const store = new LifecycleSpecStore();
    expect(() => store.setSpec("bad" as LifecyclePhase, { status: "in_progress" })).toThrow("未知阶段");
  });

  it("getActivePhase 返回当前活跃阶段", () => {
    const store = new LifecycleSpecStore();
    expect(store.getActivePhase()).toBeUndefined();
    store.setSpec("requirement", { status: "in_progress" });
    expect(store.getActivePhase()).toBe("requirement");
  });

  it("validateTransition 允许正常顺序转换", () => {
    const store = new LifecycleSpecStore();
    store.setSpec("requirement", { status: "completed" });
    const result = store.validateTransition("requirement", "product_design");
    expect(result.valid).toBe(true);
  });

  it("validateTransition 拒绝回退", () => {
    const store = new LifecycleSpecStore();
    store.setSpec("requirement", { status: "completed" });
    store.setSpec("product_design", { status: "completed" });
    const result = store.validateTransition("product_design", "requirement");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("不允许回退");
  });

  it("validateTransition 拒绝跳过未完成的中间阶段", () => {
    const store = new LifecycleSpecStore();
    store.setSpec("requirement", { status: "completed" });
    // product_design 未完成，尝试跳到 tech_plan
    const result = store.validateTransition("requirement", "tech_plan");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("product_design");
  });

  it("validateTransition 允许跳过 skipped 阶段", () => {
    const store = new LifecycleSpecStore();
    store.setSpec("requirement", { status: "completed" });
    store.setSpec("product_design", { status: "skipped" });
    const result = store.validateTransition("requirement", "ui_design");
    expect(result.valid).toBe(true);
  });

  it("checkArtifacts 识别缺失工件", () => {
    const store = new LifecycleSpecStore();
    const check = store.checkArtifacts("requirement");
    expect(check.complete).toBe(false);
    expect(check.missing).toContain("requirement_spec");
  });

  it("checkArtifacts 工件齐全时返回 complete", () => {
    const store = new LifecycleSpecStore();
    const artifact: PhaseArtifact = {
      artifact_id: "art_1",
      name: "需求规格",
      type: "requirement_spec",
      created_at: new Date().toISOString(),
      verified: true,
    };
    store.addArtifact("requirement", artifact);
    const check = store.checkArtifacts("requirement");
    expect(check.complete).toBe(true);
    expect(check.missing).toHaveLength(0);
  });

  it("addEvidenceRef 不重复添加", () => {
    const store = new LifecycleSpecStore();
    store.addEvidenceRef("requirement", "ref_1");
    store.addEvidenceRef("requirement", "ref_1");
    const spec = store.getSpec("requirement")!;
    expect(spec.evidence_refs).toHaveLength(1);
  });

  it("recordTransition 记录合法转换", () => {
    const store = new LifecycleSpecStore();
    store.setSpec("requirement", { status: "completed" });
    store.recordTransition("requirement", "product_design", "需求已确认");
    expect(store.getPhaseStatus("product_design")).toBe("in_progress");
    expect(store.getTransitions()).toHaveLength(1);
  });

  it("recordTransition 拒绝非法转换", () => {
    const store = new LifecycleSpecStore();
    expect(() => store.recordTransition("requirement", "product_design", "test")).toThrow("阶段转换失败");
  });
});
