import { describe, it, expect } from "bun:test";
import {
  detectTestOrGateChanges,
  isSensitivePath,
  buildApprovalReason,
} from "../../runtime/guards/test-change-guard";

describe("detectTestOrGateChanges", () => {
  it("检测测试文件变更", () => {
    const result = detectTestOrGateChanges([
      "src/foo.ts",
      "tests/unit/foo.test.ts",
      "src/bar.spec.ts",
    ]);
    expect(result.has_sensitive_changes).toBe(true);
    expect(result.categories.test_files).toHaveLength(2);
    expect(result.categories.gate_files).toHaveLength(0);
  });

  it("检测 gate 脚本变更", () => {
    const result = detectTestOrGateChanges([
      "runtime/gates/gate-system.ts",
      "runtime/gates/new-gate.ts",
    ]);
    expect(result.has_sensitive_changes).toBe(true);
    expect(result.categories.gate_files).toHaveLength(2);
  });

  it("检测 verifier 脚本变更", () => {
    const result = detectTestOrGateChanges([
      "runtime/verifiers/verifier-result.ts",
      "runtime/verifiers/custom-verifier.ts",
    ]);
    expect(result.has_sensitive_changes).toBe(true);
    expect(result.categories.verifier_files).toHaveLength(2);
  });

  it("普通代码文件不触发", () => {
    const result = detectTestOrGateChanges([
      "src/foo.ts",
      "src/bar.ts",
      "runtime/engine/orchestrator-runtime.ts",
    ]);
    expect(result.has_sensitive_changes).toBe(false);
    expect(result.sensitive_paths).toHaveLength(0);
  });

  it("空数组不触发", () => {
    const result = detectTestOrGateChanges([]);
    expect(result.has_sensitive_changes).toBe(false);
  });

  it("混合路径正确分类", () => {
    const result = detectTestOrGateChanges([
      "src/main.ts",
      "tests/unit/main.test.ts",
      "runtime/gates/policy-gate.ts",
      "runtime/verifiers/security.ts",
    ]);
    expect(result.has_sensitive_changes).toBe(true);
    expect(result.categories.test_files).toHaveLength(1);
    expect(result.categories.gate_files).toHaveLength(1);
    expect(result.categories.verifier_files).toHaveLength(1);
    expect(result.sensitive_paths).toHaveLength(3);
  });
});

describe("isSensitivePath", () => {
  it("测试文件路径为敏感", () => {
    expect(isSensitivePath("src/foo.test.ts")).toBe(true);
    expect(isSensitivePath("foo.spec.tsx")).toBe(true);
  });

  it("普通代码路径非敏感", () => {
    expect(isSensitivePath("src/foo.ts")).toBe(false);
    expect(isSensitivePath("runtime/engine/main.ts")).toBe(false);
  });
});

describe("buildApprovalReason", () => {
  it("正确生成审批原因", () => {
    const result = detectTestOrGateChanges([
      "tests/foo.test.ts",
      "tests/bar.test.ts",
      "runtime/gates/gate.ts",
    ]);
    const reason = buildApprovalReason(result);
    expect(reason).toContain("测试文件变更 (2 个)");
    expect(reason).toContain("Gate 脚本变更 (1 个)");
  });
});
