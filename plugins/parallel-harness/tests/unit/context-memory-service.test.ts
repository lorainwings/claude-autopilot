import { describe, it, expect } from "bun:test";
import { ContextMemoryService } from "../../runtime/session/context-memory-service";
import type { FailureMemory, PhaseSummary, DependencyIndex } from "../../runtime/session/context-memory-service";

describe("ContextMemoryService", () => {
  describe("写入与检索", () => {
    it("添加 working 记忆并检索", () => {
      const svc = new ContextMemoryService();
      svc.addWorkingMemory("task_1", "实现用户登录功能", "task_1", ["auth"]);
      const results = svc.retrieveForRole("author");
      expect(results.length).toBeGreaterThan(0);
      expect(results[0].content).toContain("登录");
    });

    it("添加 episodic 记忆", () => {
      const svc = new ContextMemoryService();
      svc.addEpisodicMemory("phase_design", "设计阶段完成：确定了 REST API 方案", "design", ["design"]);
      const results = svc.retrieveForRole("planner");
      expect(results.some(r => r.content.includes("REST API"))).toBe(true);
    });

    it("添加 semantic 记忆", () => {
      const svc = new ContextMemoryService();
      svc.addSemanticMemory("dep_output", "任务 A 输出了 user-service.ts", ["dependency"]);
      const results = svc.retrieveForRole("verifier");
      expect(results.some(r => r.content.includes("user-service"))).toBe(true);
    });
  });

  describe("role-aware 检索", () => {
    it("author 优先获取 working 层", () => {
      const svc = new ContextMemoryService();
      svc.addWorkingMemory("w1", "working 内容");
      svc.addEpisodicMemory("e1", "episodic 内容");
      const results = svc.retrieveForRole("author");
      // working 层在前
      const workingIdx = results.findIndex(r => r.layer === "working");
      const episodicIdx = results.findIndex(r => r.layer === "episodic");
      if (workingIdx !== -1 && episodicIdx !== -1) {
        expect(workingIdx).toBeLessThan(episodicIdx);
      }
    });

    it("planner 优先获取 episodic 层", () => {
      const svc = new ContextMemoryService();
      svc.addWorkingMemory("w1", "working 内容");
      svc.addEpisodicMemory("e1", "episodic 内容");
      const results = svc.retrieveForRole("planner");
      const episodicIdx = results.findIndex(r => r.layer === "episodic");
      const workingIdx = results.findIndex(r => r.layer === "working");
      if (workingIdx !== -1 && episodicIdx !== -1) {
        expect(episodicIdx).toBeLessThan(workingIdx);
      }
    });
  });

  describe("失败记忆", () => {
    it("记录并检索失败原因", () => {
      const svc = new ContextMemoryService();
      const failure: FailureMemory = {
        task_id: "task_1",
        failure_reason: "类型检查失败",
        failure_class: "type_error",
        resolved: false,
        recorded_at: new Date().toISOString(),
      };
      svc.recordFailure(failure);
      expect(svc.getFailures()).toHaveLength(1);
      expect(svc.getFailures(false)).toHaveLength(1);
      expect(svc.getFailures(true)).toHaveLength(0);
    });
  });

  describe("阶段摘要", () => {
    it("记录并检索阶段摘要", () => {
      const svc = new ContextMemoryService();
      const summary: PhaseSummary = {
        phase: "implementation",
        summary: "实现阶段完成，新增 3 个模块",
        key_decisions: ["使用 TypeScript strict"],
        artifacts_produced: ["src/auth.ts"],
        issues_encountered: ["类型兼容性问题"],
        tokens_estimate: 100,
        created_at: new Date().toISOString(),
      };
      svc.recordPhaseSummary(summary);
      expect(svc.getPhaseSummary("implementation")).toBeDefined();
      expect(svc.getPhaseSummary("implementation")!.summary).toContain("3 个模块");
    });
  });

  describe("依赖索引", () => {
    it("记录并检索依赖输出", () => {
      const svc = new ContextMemoryService();
      const dep: DependencyIndex = {
        task_id: "task_1",
        output_summary: "新增 auth 模块",
        modified_paths: ["src/auth.ts", "src/auth.test.ts"],
        key_exports: ["AuthService", "AuthConfig"],
        tokens_estimate: 50,
      };
      svc.recordDependencyOutput(dep);
      expect(svc.getDependencyOutput("task_1")).toBeDefined();
      expect(svc.getDependencyOutput("task_1")!.modified_paths).toContain("src/auth.ts");
    });
  });

  describe("搜索", () => {
    it("按关键词搜索记忆", () => {
      const svc = new ContextMemoryService();
      svc.addWorkingMemory("w1", "用户认证模块实现", undefined, ["auth"]);
      svc.addWorkingMemory("w2", "数据库连接池配置", undefined, ["db"]);
      svc.addEpisodicMemory("e1", "认证设计方案确认");

      const results = svc.search("认证");
      expect(results.length).toBeGreaterThanOrEqual(2);
    });

    it("按 tag 搜索", () => {
      const svc = new ContextMemoryService();
      svc.addWorkingMemory("w1", "内容", undefined, ["auth"]);
      svc.addWorkingMemory("w2", "内容2", undefined, ["db"]);

      const results = svc.search("auth");
      expect(results).toHaveLength(1);
    });
  });

  describe("容量管理", () => {
    it("getOccupancy 返回正确比率", () => {
      const svc = new ContextMemoryService({ max_total_tokens: 1000 });
      // 每个字符约 0.25 token，添加大量内容
      svc.addWorkingMemory("w1", "a".repeat(400)); // ~100 tokens
      expect(svc.getOccupancy()).toBeGreaterThan(0);
      expect(svc.getOccupancy()).toBeLessThan(1);
    });

    it("超出 occupancy 阈值时自动压缩", () => {
      const svc = new ContextMemoryService({
        max_total_tokens: 100,
        occupancy_threshold: 0.5,
        max_entries_per_layer: 100,
      });

      // 添加大量内容触发压缩
      for (let i = 0; i < 20; i++) {
        svc.addWorkingMemory(`w${i}`, "a".repeat(100));
      }

      expect(svc.getOccupancy()).toBeLessThanOrEqual(1);
    });

    it("clearWorking 清空 working 层", () => {
      const svc = new ContextMemoryService();
      svc.addWorkingMemory("w1", "内容1");
      svc.addWorkingMemory("w2", "内容2");
      svc.clearWorking();
      const stats = svc.getLayerStats();
      expect(stats.working.entries).toBe(0);
    });

    it("getLayerStats 返回各层统计", () => {
      const svc = new ContextMemoryService();
      svc.addWorkingMemory("w1", "working");
      svc.addEpisodicMemory("e1", "episodic");
      svc.addSemanticMemory("s1", "semantic");

      const stats = svc.getLayerStats();
      expect(stats.working.entries).toBe(1);
      expect(stats.episodic.entries).toBe(1);
      expect(stats.semantic.entries).toBe(1);
    });

    it("needsCompaction 在低 occupancy 时返回 false", () => {
      const svc = new ContextMemoryService({ max_total_tokens: 100000 });
      svc.addWorkingMemory("w1", "小内容");
      expect(svc.needsCompaction()).toBe(false);
    });
  });
});
