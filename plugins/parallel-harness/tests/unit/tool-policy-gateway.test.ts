import { describe, it, expect } from "bun:test";
import {
  validateToolCall,
  ToolPolicyViolationError,
} from "../../runtime/workers/execution-proxy";
import type { ExecutionProxyConfig } from "../../runtime/workers/execution-proxy";

function createConfig(overrides: Partial<ExecutionProxyConfig> = {}): ExecutionProxyConfig {
  return {
    model_tier: "tier-2",
    project_root: "/tmp/test",
    allowed_tools: [],
    denied_tools: [],
    ...overrides,
  };
}

describe("validateToolCall", () => {
  it("无策略时默认放行", () => {
    const config = createConfig();
    expect(validateToolCall("any_tool", config)).toBe(true);
  });

  it("allowed 列表内的 tool 通过", () => {
    const config = createConfig({ allowed_tools: ["read", "write", "edit"] });
    expect(validateToolCall("read", config)).toBe(true);
    expect(validateToolCall("write", config)).toBe(true);
  });

  it("不在 allowed 列表中的 tool 被拦截", () => {
    const config = createConfig({ allowed_tools: ["read", "write"] });
    expect(validateToolCall("delete", config)).toBe(false);
  });

  it("denied 列表中的 tool 被拦截", () => {
    const config = createConfig({ denied_tools: ["rm", "format"] });
    expect(validateToolCall("rm", config)).toBe(false);
    expect(validateToolCall("format", config)).toBe(false);
  });

  it("denied 优先于 allowed", () => {
    const config = createConfig({
      allowed_tools: ["read", "write", "delete"],
      denied_tools: ["delete"],
    });
    expect(validateToolCall("delete", config)).toBe(false);
    expect(validateToolCall("read", config)).toBe(true);
  });

  it("denied 列表不影响其他 tool", () => {
    const config = createConfig({ denied_tools: ["rm"] });
    expect(validateToolCall("read", config)).toBe(true);
  });
});

describe("ToolPolicyViolationError", () => {
  it("包含正确的 tool_name 和 policy", () => {
    const err = new ToolPolicyViolationError("dangerous_tool", {
      allowed: ["safe_tool"],
      denied: ["dangerous_tool"],
    });
    expect(err.name).toBe("ToolPolicyViolationError");
    expect(err.tool_name).toBe("dangerous_tool");
    expect(err.policy.denied).toContain("dangerous_tool");
    expect(err.message).toContain("dangerous_tool");
  });

  it("是 Error 的子类", () => {
    const err = new ToolPolicyViolationError("x", { allowed: [], denied: [] });
    expect(err).toBeInstanceOf(Error);
  });
});
