import { describe, test, expect } from "bun:test";
import {
  analyzeTestImpact,
  analyzeTypecheckScope,
  createVerifierBatchPlan,
  type VerifierBatchPlan,
  type TestImpactAnalysis,
  type TypecheckScopeClassifier,
} from "../../runtime/gates/gate-system";

describe("VerifierBatchPlan (P0-3)", () => {
  describe("analyzeTestImpact", () => {
    test("detects affected test files", () => {
      const result = analyzeTestImpact(["src/foo.ts", "tests/foo.test.ts"]);
      expect(result.affected_test_files).toContain("tests/foo.test.ts");
      expect(result.requires_full_suite).toBe(false);
    });

    test("requires full suite when package.json changes", () => {
      const result = analyzeTestImpact(["src/foo.ts", "package.json"]);
      expect(result.requires_full_suite).toBe(true);
      expect(result.reason).toContain("配置文件");
    });

    test("requires full suite when tsconfig changes", () => {
      const result = analyzeTestImpact(["tsconfig.json"]);
      expect(result.requires_full_suite).toBe(true);
    });

    test("requires full suite when shared module changes", () => {
      const result = analyzeTestImpact(["runtime/schemas/ga-schemas.ts"]);
      expect(result.requires_full_suite).toBe(true);
      expect(result.reason).toContain("共享模块");
    });

    test("requires full suite when index.ts changes", () => {
      const result = analyzeTestImpact(["runtime/gates/index.ts"]);
      expect(result.requires_full_suite).toBe(true);
    });

    test("no full suite for isolated changes", () => {
      const result = analyzeTestImpact(["src/components/button.ts"]);
      expect(result.requires_full_suite).toBe(false);
    });
  });

  describe("analyzeTypecheckScope", () => {
    test("requires full typecheck when tsconfig changes", () => {
      const result = analyzeTypecheckScope(["tsconfig.json", "src/foo.ts"]);
      expect(result.requires_full_typecheck).toBe(true);
    });

    test("requires full typecheck when .d.ts changes", () => {
      const result = analyzeTypecheckScope(["src/types/global.d.ts"]);
      expect(result.requires_full_typecheck).toBe(true);
    });

    test("requires full typecheck when types/ directory changes", () => {
      const result = analyzeTypecheckScope(["src/types/api.ts"]);
      expect(result.requires_full_typecheck).toBe(true);
    });

    test("no full typecheck for isolated .ts changes", () => {
      const result = analyzeTypecheckScope(["src/components/button.ts"]);
      expect(result.requires_full_typecheck).toBe(false);
    });

    test("tracks affected ts files", () => {
      const result = analyzeTypecheckScope(["src/a.ts", "src/b.tsx", "README.md"]);
      expect(result.affected_ts_files).toHaveLength(2);
    });
  });

  describe("createVerifierBatchPlan", () => {
    test("task level produces empty commands", () => {
      const plan = createVerifierBatchPlan(
        [{ task_id: "t1", modified_paths: ["src/foo.ts"] }],
        "task"
      );
      expect(plan.scope).toBe("task");
      expect(plan.commands).toHaveLength(0);
    });

    test("run level with config change produces full test command", () => {
      const plan = createVerifierBatchPlan(
        [
          { task_id: "t1", modified_paths: ["src/foo.ts", "package.json"] },
          { task_id: "t2", modified_paths: ["src/bar.ts"] },
        ],
        "run"
      );
      expect(plan.scope).toBe("run");
      expect(plan.commands).toContain("bun test");
    });

    test("run level with isolated changes produces scoped test command", () => {
      const plan = createVerifierBatchPlan(
        [{ task_id: "t1", modified_paths: ["tests/foo.test.ts", "src/foo.ts"] }],
        "run"
      );
      expect(plan.scope).toBe("run");
      const testCmd = plan.commands.find(c => c.startsWith("bun test"));
      if (testCmd) {
        expect(testCmd).toContain("tests/foo.test.ts");
      }
    });

    test("deduplicates modified paths across tasks", () => {
      const plan = createVerifierBatchPlan(
        [
          { task_id: "t1", modified_paths: ["src/shared.ts"] },
          { task_id: "t2", modified_paths: ["src/shared.ts"] },
        ],
        "run"
      );
      expect(plan.impacted_paths).toHaveLength(1);
    });

    test("generates shared evidence refs", () => {
      const plan = createVerifierBatchPlan(
        [
          { task_id: "t1", modified_paths: ["src/a.ts"] },
          { task_id: "t2", modified_paths: ["src/b.ts"] },
        ],
        "run"
      );
      expect(plan.shared_evidence_refs).toContain("evidence:t1");
      expect(plan.shared_evidence_refs).toContain("evidence:t2");
    });
  });
});
