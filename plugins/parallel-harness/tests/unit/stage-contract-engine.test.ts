import { describe, it, expect } from "bun:test";
import { LifecycleSpecStore } from "../../runtime/lifecycle/lifecycle-spec-store";
import { StageContractEngine } from "../../runtime/lifecycle/stage-contract-engine";
import type { PhaseArtifact } from "../../runtime/lifecycle/lifecycle-spec-store";

function createEngine(): StageContractEngine {
  const store = new LifecycleSpecStore();
  return new StageContractEngine(store);
}

describe("StageContractEngine", () => {
  describe("enterStage", () => {
    it("允许进入第一个阶段 (requirement)", () => {
      const engine = createEngine();
      const result = engine.enterStage("requirement");
      expect(result.allowed).toBe(true);
      expect(result.phase).toBe("requirement");
    });

    it("拒绝重复进入已在进行中的阶段", () => {
      const engine = createEngine();
      engine.enterStage("requirement");
      const result = engine.enterStage("requirement");
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain("已在进行中");
    });

    it("拒绝进入前置条件未满足的阶段", () => {
      const engine = createEngine();
      const result = engine.enterStage("implementation");
      expect(result.allowed).toBe(false);
      expect(result.unmet_criteria.length).toBeGreaterThan(0);
    });

    it("前置阶段完成后允许进入下一阶段", () => {
      const engine = createEngine();
      const store = engine.getStore();
      store.setSpec("requirement", { status: "completed" });
      const result = engine.enterStage("product_design");
      expect(result.allowed).toBe(true);
    });
  });

  describe("exitStage", () => {
    it("工件齐全且 gate 通过时允许退出", () => {
      const engine = createEngine();
      const store = engine.getStore();
      engine.enterStage("requirement");

      // 添加必要工件
      store.addArtifact("requirement", {
        artifact_id: "art_1",
        name: "需求规格",
        type: "requirement_spec",
        created_at: new Date().toISOString(),
        verified: true,
      });
      // 记录 gate 通过
      engine.recordGateResult("requirement", "review", true);

      const result = engine.exitStage("requirement");
      expect(result.allowed).toBe(true);
    });

    it("缺少工件时拒绝退出", () => {
      const engine = createEngine();
      engine.enterStage("requirement");
      engine.recordGateResult("requirement", "review", true);

      const result = engine.exitStage("requirement");
      expect(result.allowed).toBe(false);
      expect(result.missing_artifacts).toContain("requirement_spec");
    });

    it("gate 未通过时拒绝退出", () => {
      const engine = createEngine();
      const store = engine.getStore();
      engine.enterStage("requirement");
      store.addArtifact("requirement", {
        artifact_id: "art_1",
        name: "需求规格",
        type: "requirement_spec",
        created_at: new Date().toISOString(),
        verified: true,
      });
      // 不记录 gate 结果

      const result = engine.exitStage("requirement");
      expect(result.allowed).toBe(false);
      expect(result.pending_gates).toContain("review");
    });

    it("非进行中阶段不允许退出", () => {
      const engine = createEngine();
      const result = engine.exitStage("requirement");
      expect(result.allowed).toBe(false);
      expect(result.reason).toContain("不在进行中");
    });
  });

  describe("validateStage", () => {
    it("返回完整验证结果", () => {
      const engine = createEngine();
      engine.enterStage("requirement");
      const result = engine.validateStage("requirement");
      expect(result.phase).toBe("requirement");
      expect(result.artifacts_complete).toBe(false);
      expect(result.gates_passed).toBe(false);
    });
  });

  describe("getFailurePolicy", () => {
    it("返回默认失败策略", () => {
      const engine = createEngine();
      const policy = engine.getFailurePolicy("implementation");
      expect(policy.strategy).toBe("retry");
      expect(policy.max_retries).toBe(3);
    });

    it("requirement 阶段使用 escalate 策略", () => {
      const engine = createEngine();
      const policy = engine.getFailurePolicy("requirement");
      expect(policy.strategy).toBe("escalate");
      expect(policy.escalation_target).toBe("human");
    });
  });

  describe("getActiveStage", () => {
    it("无活跃阶段返回 undefined", () => {
      const engine = createEngine();
      expect(engine.getActiveStage()).toBeUndefined();
    });

    it("返回当前进行中的阶段", () => {
      const engine = createEngine();
      engine.enterStage("requirement");
      expect(engine.getActiveStage()).toBe("requirement");
    });
  });
});
