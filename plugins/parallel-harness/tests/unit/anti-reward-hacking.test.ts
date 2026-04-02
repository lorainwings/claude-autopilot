import { describe, it, expect } from "bun:test";
import {
  detectSuspiciousPatches,
  auditTestFileChanges,
  auditGateFileChanges,
} from "../../runtime/guards/anti-reward-hacking";

describe("detectSuspiciousPatches", () => {
  it("检测删除断言", () => {
    const diff = `--- a/test.ts
+++ b/test.ts
@@ -1,3 +1,2 @@
-    expect(result).toBe(true);
     console.log("done");`;

    const result = detectSuspiciousPatches(diff);
    expect(result.suspicious).toBe(true);
    expect(result.severity).toBe("high");
    expect(result.findings.some(f => f.type === "assertion_removed" || f.type === "expect_removed")).toBe(true);
  });

  it("检测添加 skip 标记", () => {
    const diff = `--- a/test.ts
+++ b/test.ts
@@ -1,3 +1,3 @@
-  it("should work", () => {
+  it.skip("should work", () => {`;

    const result = detectSuspiciousPatches(diff);
    expect(result.suspicious).toBe(true);
    expect(result.findings.some(f => f.type === "skip_added")).toBe(true);
  });

  it("检测降低阈值", () => {
    const diff = `--- a/config.ts
+++ b/config.ts
@@ -1,3 +1,3 @@
-  min_pass_rate: 0.95,
+  min_pass_rate: 0.1,`;

    const result = detectSuspiciousPatches(diff);
    expect(result.suspicious).toBe(true);
    expect(result.findings.some(f => f.type === "threshold_lowered")).toBe(true);
  });

  it("检测将 blocking gate 改为非阻断", () => {
    const diff = `--- a/gate.ts
+++ b/gate.ts
@@ -1,3 +1,3 @@
-  blocking: true,
+  blocking: false,`;

    const result = detectSuspiciousPatches(diff);
    expect(result.suspicious).toBe(true);
    expect(result.findings.some(f => f.type === "gate_weakened")).toBe(true);
  });

  it("正常 diff 不触发", () => {
    const diff = `--- a/src/main.ts
+++ b/src/main.ts
@@ -1,3 +1,4 @@
 function hello() {
+  console.log("hello");
   return true;
 }`;

    const result = detectSuspiciousPatches(diff);
    expect(result.suspicious).toBe(false);
    expect(result.severity).toBe("none");
  });

  it("空 diff 不触发", () => {
    const result = detectSuspiciousPatches("");
    expect(result.suspicious).toBe(false);
  });
});

describe("auditTestFileChanges", () => {
  it("检测测试文件变更", () => {
    const result = auditTestFileChanges(["src/main.ts", "tests/unit/main.test.ts"]);
    expect(result.requires_review).toBe(true);
    expect(result.test_files_changed).toHaveLength(1);
  });

  it("无测试文件变更时不需要审查", () => {
    const result = auditTestFileChanges(["src/main.ts", "src/utils.ts"]);
    expect(result.requires_review).toBe(false);
    expect(result.test_files_changed).toHaveLength(0);
  });

  it("spec 文件也被检测", () => {
    const result = auditTestFileChanges(["component.spec.tsx"]);
    expect(result.requires_review).toBe(true);
  });
});

describe("auditGateFileChanges", () => {
  it("检测 gate 文件变更", () => {
    const result = auditGateFileChanges(["runtime/gates/gate-system.ts"]);
    expect(result.requires_review).toBe(true);
    expect(result.gate_files_changed).toHaveLength(1);
  });

  it("检测 verifier 文件变更", () => {
    const result = auditGateFileChanges(["runtime/verifiers/custom.ts"]);
    expect(result.requires_review).toBe(true);
  });

  it("普通文件不触发", () => {
    const result = auditGateFileChanges(["src/main.ts"]);
    expect(result.requires_review).toBe(false);
  });
});
