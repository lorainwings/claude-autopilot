import { describe, test, expect } from "bun:test";
import { ExecutionProxy, type TrustedExecutionRecord, type ExecutionAttestation } from "../../runtime/workers/execution-proxy";

describe("TrustedExecutionRecord (P0-4)", () => {
  const proxy = new ExecutionProxy();

  test("TrustedExecutionRecord has required fields", () => {
    const record: TrustedExecutionRecord = {
      attempt_id: "att_test_1",
      cwd: "/tmp/test",
      tool_trace: [
        {
          tool: "Edit",
          started_at: "2024-01-01T00:00:00Z",
          ended_at: "2024-01-01T00:00:01Z",
          args_hash: "h_abc",
        },
      ],
      diff_ref: "commit:abc123",
      sandbox_enforced: true,
    };
    expect(record.attempt_id).toBe("att_test_1");
    expect(record.tool_trace).toHaveLength(1);
    expect(record.diff_ref).toStartWith("commit:");
  });

  test("TrustedExecutionRecord supports worktree path", () => {
    const record: TrustedExecutionRecord = {
      attempt_id: "att_test_2",
      worktree_path: "/tmp/repo/.parallel-harness/worktrees/att_test_2",
      cwd: "/tmp/repo/.parallel-harness/worktrees/att_test_2",
      tool_trace: [],
      diff_ref: "diff:abc123..HEAD:h_xyz",
      sandbox_enforced: true,
    };
    expect(record.worktree_path).toBeDefined();
    expect(record.diff_ref).toContain("diff:");
  });

  test("prepareExecution no longer throws for worktree mode (degrades if git fails)", () => {
    // In non-git environment, worktree creation should degrade gracefully
    expect(() => {
      proxy.prepareExecution({
        model_tier: "tier-2",
        project_root: "/tmp/nonexistent-for-test",
        sandbox_mode: "worktree",
        attempt_id: "test_att",
      });
    }).not.toThrow();
  });

  test("prepareExecution returns validated config for path_check mode", () => {
    const result = proxy.prepareExecution({
      model_tier: "tier-1",
      project_root: "/tmp/test-root",
      sandbox_mode: "path_check",
    });
    expect(result.validated_model).toBe("claude-haiku-4");
    expect(result.validated_cwd).toBe("/tmp/test-root");
  });

  test("prepareExecution returns validated config for none mode", () => {
    const result = proxy.prepareExecution({
      model_tier: "tier-3",
      project_root: "/tmp/test-root",
      sandbox_mode: "none",
    });
    expect(result.validated_model).toBe("claude-opus-4");
  });

  test("generateDiffRef returns no-diff-ref for non-git directory", () => {
    const ref = proxy.generateDiffRef("/tmp/nonexistent");
    expect(ref).toBe("no-diff-ref");
  });

  test("buildTrustedRecord constructs from attestation", () => {
    const attestation: ExecutionAttestation = {
      attempt_id: "att_1",
      worker_id: "w1",
      repo_root: "/tmp/repo",
      actual_model: "claude-sonnet-4",
      tool_calls: [{ name: "Edit", args_hash: "h_abc" }],
      modified_paths: ["src/foo.ts"],
      sandbox_violations: [],
      token_usage: { input: 1000, output: 500, usage_source: "estimated" },
      timestamp: "2024-01-01T00:00:01Z",
      started_at: "2024-01-01T00:00:00Z",
      ended_at: "2024-01-01T00:00:01Z",
      tool_policy_enforced: true,
      diff_ref: "commit:abc123",
      execution_outcome: "success",
    };

    const record = proxy.buildTrustedRecord(attestation, "/tmp/repo");
    expect(record.attempt_id).toBe("att_1");
    expect(record.tool_trace).toHaveLength(1);
    expect(record.tool_trace[0].tool).toBe("Edit");
    expect(record.diff_ref).toBe("commit:abc123");
    expect(record.sandbox_enforced).toBe(true);
    expect(record.worktree_path).toBeUndefined();
  });

  test("buildTrustedRecord includes worktree path when provided", () => {
    const attestation: ExecutionAttestation = {
      attempt_id: "att_2",
      worker_id: "w2",
      repo_root: "/tmp/repo",
      actual_model: "claude-haiku-4",
      tool_calls: [],
      modified_paths: [],
      sandbox_violations: [],
      token_usage: { input: 0, output: 0, usage_source: "estimated" },
      timestamp: "2024-01-01T00:00:01Z",
      started_at: "2024-01-01T00:00:00Z",
      ended_at: "2024-01-01T00:00:01Z",
      tool_policy_enforced: false,
      diff_ref: "no-diff-ref",
      execution_outcome: "success",
    };

    const record = proxy.buildTrustedRecord(
      attestation,
      "/tmp/repo/.parallel-harness/worktrees/att_2",
      "/tmp/repo/.parallel-harness/worktrees/att_2"
    );
    expect(record.worktree_path).toBe("/tmp/repo/.parallel-harness/worktrees/att_2");
  });

  test("finalizeExecution generates attestation with real diff ref format", () => {
    const result = proxy.finalizeExecution(
      {
        model_tier: "tier-2",
        project_root: "/tmp/test-root",
      },
      {
        status: "ok",
        summary: "test output",
        modified_paths: ["src/test.ts"],
        artifacts: [],
        tokens_used: 1000,
        duration_ms: 5000,
        actual_tool_calls: [],
        exit_code: 0,
      },
      "2024-01-01T00:00:00Z",
      false,
    );
    expect(result.attestation.diff_ref).toBeDefined();
    expect(result.attestation.execution_outcome).toBe("success");
  });
});
