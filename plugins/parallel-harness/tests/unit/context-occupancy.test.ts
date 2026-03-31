/**
 * P0-2: Context Occupancy 策略化测试
 */
import { describe, expect, it } from "bun:test";
import { packContext } from "../../runtime/session/context-packager";
import type { FileInfo } from "../../runtime/session/context-packager";
import type { TaskNode } from "../../runtime/orchestrator/task-graph";

function createMockTask(overrides: Partial<TaskNode> = {}): TaskNode {
  return {
    id: "task-1",
    title: "测试任务",
    description: "测试任务描述",
    goal: "完成测试任务",
    type: "implementation",
    status: "pending",
    phase: "implementation",
    domain: "backend",
    dependencies: [],
    allowed_paths: overrides.allowed_paths || ["src/"],
    forbidden_paths: overrides.forbidden_paths || [],
    acceptance_criteria: ["功能正常"],
    required_tests: [],
    risk_level: "medium",
    model_tier: "tier-2",
    complexity: { level: "moderate", score: 5, factors: [] },
    retry_policy: { max_retries: 2, backoff_strategy: "linear", retry_on: ["transient_tool_failure"] },
    verifier_set: ["test"],
    verification_requirements: [],
    ...(overrides as any),
  };
}

function createMockFiles(count: number, prefix: string = "src/"): FileInfo[] {
  return Array.from({ length: count }, (_, i) => ({
    path: `${prefix}file-${i}.ts`,
    content: `// file ${i}\n` + "const x = 1;\n".repeat(50),
    size: 500,
    type: "ts",
  }));
}

describe("Context Occupancy 策略化", () => {
  it("occupancy_threshold 默认为 0.8", () => {
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    const pack = packContext(task, [], {});
    // 空文件列表 occupancy 极低
    expect(pack.occupancy_ratio).toBeLessThan(0.01);
    expect(pack.compaction_policy).toBe("none");
  });

  it("occupancy 超过阈值时触发 compaction", () => {
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    // 创建大量文件让 occupancy 超过阈值
    const files = createMockFiles(20);
    const pack = packContext(task, files, {
      default_budget: {
        max_input_tokens: 100,  // 极小 budget
        max_output_tokens: 100,
        auto_summarize_on_overflow: true,
        occupancy_threshold: 0.5,
      },
      max_snippets: 20,
    });
    expect(pack.compaction_policy).toBe("truncate");
  });

  it("verifier 角色优先 test 文件", () => {
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    const files: FileInfo[] = [
      { path: "src/main.ts", content: "const a = 1;", size: 20, type: "ts" },
      { path: "src/test.spec.ts", content: "test('x', () => {});", size: 30, type: "ts" },
      { path: "src/config.json", content: "{}", size: 10, type: "json" },
    ];
    const pack = packContext(task, files, {
      default_budget: {
        max_input_tokens: 30000,
        max_output_tokens: 8000,
        auto_summarize_on_overflow: true,
        role: "verifier",
      },
    });
    // verifier 角色下 test 文件应排在前面
    expect(pack.relevant_files[0]).toContain("test");
  });

  it("retry_hint 跳过前 N 个 snippets", () => {
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    const files = createMockFiles(5);

    const pack0 = packContext(task, files, {}, undefined, 0);
    const pack1 = packContext(task, files, {}, undefined, 2);

    // retryHint=2 时应跳过前 2 个 snippet
    expect(pack1.loaded_snippets_count).toBeLessThan(pack0.loaded_snippets_count);
    expect(pack1.retry_hint).toBe(2);
    expect(pack0.retry_hint).toBeUndefined();
  });

  it("planner 角色优先 md/config 文件", () => {
    const task = createMockTask({ allowed_paths: ["src/"], forbidden_paths: [] });
    const files: FileInfo[] = [
      { path: "src/impl.ts", content: "const a = 1;", size: 20, type: "ts" },
      { path: "src/README.md", content: "# Readme", size: 10, type: "md" },
      { path: "src/config.json", content: "{}", size: 10, type: "json" },
    ];
    const pack = packContext(task, files, {
      default_budget: {
        max_input_tokens: 30000,
        max_output_tokens: 8000,
        auto_summarize_on_overflow: true,
        role: "planner",
      },
    });
    // planner 角色下 md/config 文件应排在前面
    const firstFile = pack.relevant_files[0];
    expect(firstFile.endsWith(".md") || firstFile.includes("config")).toBe(true);
  });
});
