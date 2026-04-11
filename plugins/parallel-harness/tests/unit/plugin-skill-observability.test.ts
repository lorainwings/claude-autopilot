import { afterEach, describe, expect, test } from "bun:test";
import { execFileSync } from "child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";

type TempProject = {
  root: string;
  home: string;
};

const tempProjects: TempProject[] = [];
const pluginRoot = resolve(import.meta.dir, "..", "..");
const hookConfigPath = join(pluginRoot, "hooks", "hooks.json");
const hookScriptPath = join(pluginRoot, "runtime", "scripts", "record-skill-tool-event.sh");
const statuslineScriptPath = join(pluginRoot, "runtime", "scripts", "statusline-collector.sh");
const autoInstallScriptPath = join(pluginRoot, "runtime", "scripts", "auto-install-statusline.sh");
const mainSkillPath = join(pluginRoot, "skills", "harness", "SKILL.md");

function createTempProject(): TempProject {
  const root = mkdtempSync(join(tmpdir(), "ph-skill-hook-"));
  const home = join(root, "home");
  mkdirSync(home, { recursive: true });
  const project = { root, home };
  tempProjects.push(project);
  return project;
}

function readJsonLines(path: string): Array<Record<string, unknown>> {
  return readFileSync(path, "utf8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line) as Record<string, unknown>);
}

function runHook(
  hookName: "PreToolUse" | "PostToolUse" | "PostToolUseFailure",
  project: TempProject,
  payload: Record<string, unknown>,
): void {
  execFileSync("bash", [hookScriptPath, hookName], {
    cwd: project.root,
    encoding: "utf8",
    input: JSON.stringify(payload),
    env: {
      ...process.env,
      CLAUDE_PLUGIN_ROOT: pluginRoot,
      HOME: project.home,
    },
  });
}

afterEach(() => {
  while (tempProjects.length > 0) {
    const project = tempProjects.pop();
    if (project) rmSync(project.root, { recursive: true, force: true });
  }
});

describe("plugin skill observability", () => {
  test("main harness protocol keeps explicit child skill calls visible", () => {
    const content = readFileSync(mainSkillPath, "utf8");
    expect(content).toContain('Skill(skill: "parallel-harness:harness-plan")');
    expect(content).toContain('Skill(skill: "parallel-harness:harness-dispatch")');
    expect(content).toContain('Skill(skill: "parallel-harness:harness-verify")');
    expect(content).toContain("Phase 1/4");
    expect(content).toContain("Phase 2/4");
    expect(content).toContain("Phase 3/4");
  });

  test("hooks.json registers deterministic Skill observers", () => {
    const config = JSON.parse(readFileSync(hookConfigPath, "utf8")) as {
      hooks: Record<string, Array<{ matcher?: string; hooks: Array<{ command: string }> }>>;
    };

    const preSkill = config.hooks.PreToolUse.find((entry) => entry.matcher === "^Skill$");
    const postSkill = config.hooks.PostToolUse.find((entry) => entry.matcher === "^Skill$");
    const postFailure = config.hooks.PostToolUseFailure?.find((entry) => entry.matcher === "^Skill$");
    const sessionStart = config.hooks.SessionStart?.[0];

    expect(preSkill).toBeDefined();
    expect(postSkill).toBeDefined();
    expect(postFailure).toBeDefined();
    expect(sessionStart).toBeDefined();
    expect(preSkill!.hooks[0].command).toContain("record-skill-tool-event.sh PreToolUse");
    expect(postSkill!.hooks[0].command).toContain("record-skill-tool-event.sh PostToolUse");
    expect(postFailure!.hooks[0].command).toContain("record-skill-tool-event.sh PostToolUseFailure");
    expect(sessionStart!.hooks[0].command).toContain("auto-install-statusline.sh");
  });

  test("hook bridge records requested and completed skill events for actual plugin sessions", () => {
    const project = createTempProject();
    const sessionId = "sess-skill-001";
    const transcriptPath = join(project.root, "transcript.md");

    const basePayload = {
      session_id: sessionId,
      cwd: project.root,
      transcript_path: transcriptPath,
      tool_name: "Skill",
      tool_input: {
        skill: "parallel-harness:harness-plan",
        args: "plan the work graph",
      },
    };

    runHook("PreToolUse", project, basePayload);
    runHook("PostToolUse", project, {
      ...basePayload,
      tool_response: {
        status: "ok",
        summary: "planning complete",
      },
    });

    const eventsPath = join(
      project.root,
      ".parallel-harness",
      "data",
      "plugin-observability",
      "sessions",
      sessionId,
      "skill-events.jsonl"
    );

    expect(existsSync(eventsPath)).toBe(true);

    const events = readJsonLines(eventsPath);
    expect(events).toHaveLength(2);
    expect(events[0].event_type).toBe("skill_tool_requested");
    expect(events[1].event_type).toBe("skill_tool_completed");
    expect(events[0].skill_name).toBe("parallel-harness:harness-plan");
    expect(events[0].phase_hint).toBe("planning");
    expect(events[0].is_parallel_harness_skill).toBe(true);
    expect(events[1].completion_status).toBe("completed");
    expect(String(events[0].raw_ref || "")).toContain("raw/hooks.jsonl");

    const rawHooksPath = join(
      project.root,
      ".parallel-harness",
      "data",
      "plugin-observability",
      "sessions",
      sessionId,
      "raw",
      "hooks.jsonl",
    );

    expect(existsSync(rawHooksPath)).toBe(true);
    const rawHooks = readJsonLines(rawHooksPath);
    expect(rawHooks).toHaveLength(2);
    expect(rawHooks[0].hook_name).toBe("PreToolUse");
    expect(rawHooks[1].hook_name).toBe("PostToolUse");
  });

  test("hook bridge ignores non-Skill payloads", () => {
    const project = createTempProject();
    runHook("PostToolUse", project, {
      session_id: "sess-bash-001",
      cwd: project.root,
      tool_name: "Bash",
      tool_input: { command: "echo hi" },
    });

    const eventsPath = join(
      project.root,
      ".parallel-harness",
      "data",
      "plugin-observability",
      "sessions",
      "sess-bash-001",
      "skill-events.jsonl"
    );

    expect(existsSync(eventsPath)).toBe(false);
  });

  test("hook bridge records PostToolUseFailure as skill_tool_failed event", () => {
    const project = createTempProject();
    const sessionId = "sess-skill-fail-001";

    runHook("PreToolUse", project, {
      session_id: sessionId,
      cwd: project.root,
      tool_name: "Skill",
      tool_input: {
        skill: "parallel-harness:harness-dispatch",
        args: "dispatch batch 1",
      },
    });

    runHook("PostToolUseFailure", project, {
      session_id: sessionId,
      cwd: project.root,
      tool_name: "Skill",
      tool_input: {
        skill: "parallel-harness:harness-dispatch",
        args: "dispatch batch 1",
      },
      error: "Skill execution timed out after 600s",
      is_interrupt: false,
    });

    const eventsPath = join(
      project.root,
      ".parallel-harness",
      "data",
      "plugin-observability",
      "sessions",
      sessionId,
      "skill-events.jsonl"
    );

    expect(existsSync(eventsPath)).toBe(true);

    const events = readJsonLines(eventsPath);
    expect(events).toHaveLength(2);
    expect(events[0].event_type).toBe("skill_tool_requested");
    expect(events[1].event_type).toBe("skill_tool_failed");
    expect(events[1].skill_name).toBe("parallel-harness:harness-dispatch");
    expect(events[1].phase_hint).toBe("dispatch");
    expect(events[1].completion_status).toBe("failed");
    expect(events[1].error_message).toBe("Skill execution timed out after 600s");
    expect(events[1].is_interrupt).toBe(false);
  });

  test("status line shows the latest observed skill and auto-install creates a local bridge", () => {
    const project = createTempProject();
    const sessionId = "sess-statusline-001";

    runHook("PostToolUse", project, {
      session_id: sessionId,
      cwd: project.root,
      tool_name: "Skill",
      tool_input: {
        skill: "parallel-harness:harness-dispatch",
        args: "dispatch batch 1",
      },
      tool_response: {
        status: "ok",
        summary: "dispatch finished",
      },
    });

    const statusOutput = execFileSync("bash", [statuslineScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: sessionId,
        cwd: project.root,
        model: "claude-opus",
      }),
      env: {
        ...process.env,
        HOME: project.home,
      },
    });

    expect(statusOutput).toContain("[harness] skill harness-dispatch");

    execFileSync("bash", [autoInstallScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: sessionId,
        cwd: project.root,
      }),
      env: {
        ...process.env,
        HOME: project.home,
      },
    });

    const settingsPath = join(project.root, ".claude", "settings.local.json");
    const bridgePath = join(project.root, ".claude", "statusline-parallel-harness.sh");

    expect(existsSync(settingsPath)).toBe(true);
    expect(existsSync(bridgePath)).toBe(true);

    const settings = JSON.parse(readFileSync(settingsPath, "utf8")) as {
      statusLine?: { command?: string };
    };
    expect(settings.statusLine?.command).toBe(bridgePath);
  });

  test("auto-install chains with existing user-level statusLine instead of skipping", () => {
    const project = createTempProject();
    const sessionId = "sess-chain-001";

    // Pre-configure a user-level statusLine to simulate existing config
    const userClaudeDir = join(project.home, ".claude");
    mkdirSync(userClaudeDir, { recursive: true });
    const userSettings = join(userClaudeDir, "settings.json");
    const existingCmd = join(project.home, "my-custom-statusline.sh");
    writeFileSync(existingCmd, '#!/usr/bin/env bash\nprintf "custom status"', { mode: 0o755 });
    writeFileSync(userSettings, JSON.stringify({
      statusLine: { type: "command", command: existingCmd, padding: 1 },
    }));

    // Run auto-install — should NOT skip, should chain
    execFileSync("bash", [autoInstallScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: sessionId,
        cwd: project.root,
      }),
      env: {
        ...process.env,
        HOME: project.home,
      },
    });

    const localSettingsPath = join(project.root, ".claude", "settings.local.json");
    const bridgePath = join(project.root, ".claude", "statusline-parallel-harness.sh");

    // Bridge should be installed despite existing user-level statusLine
    expect(existsSync(localSettingsPath)).toBe(true);
    expect(existsSync(bridgePath)).toBe(true);

    const localSettings = JSON.parse(readFileSync(localSettingsPath, "utf8")) as {
      statusLine?: { command?: string };
    };
    expect(localSettings.statusLine?.command).toBe(bridgePath);

    // Bridge script should contain chain reference to the original command
    const bridgeContent = readFileSync(bridgePath, "utf8");
    expect(bridgeContent).toContain(existingCmd);
    expect(bridgeContent).toContain("statusline-collector.sh");
  });

  test("auto-install chains correctly when existing statusLine command has spaces and arguments", () => {
    const project = createTempProject();
    const sessionId = "sess-chain-spaces-001";

    // Create a directory with spaces in the name
    const dirWithSpaces = join(project.home, "my custom scripts");
    mkdirSync(dirWithSpaces, { recursive: true });

    // Create a statusline script inside the directory with spaces
    const existingScript = join(dirWithSpaces, "statusline.sh");
    writeFileSync(existingScript, '#!/usr/bin/env bash\nprintf "custom status"', { mode: 0o755 });

    // Command with a path containing spaces AND an argument
    const existingCmd = `${existingScript} --flag value`;

    const userClaudeDir = join(project.home, ".claude");
    mkdirSync(userClaudeDir, { recursive: true });
    const userSettings = join(userClaudeDir, "settings.json");
    writeFileSync(userSettings, JSON.stringify({
      statusLine: { type: "command", command: existingCmd, padding: 1 },
    }));

    // Run auto-install — must NOT silently exit without installing
    execFileSync("bash", [autoInstallScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: sessionId,
        cwd: project.root,
      }),
      env: {
        ...process.env,
        HOME: project.home,
      },
    });

    const localSettingsPath = join(project.root, ".claude", "settings.local.json");
    const bridgePath = join(project.root, ".claude", "statusline-parallel-harness.sh");

    // Bridge must be installed (the original bug: silently exited without installing)
    expect(existsSync(localSettingsPath)).toBe(true);
    expect(existsSync(bridgePath)).toBe(true);

    const localSettings = JSON.parse(readFileSync(localSettingsPath, "utf8")) as {
      statusLine?: { command?: string };
    };
    expect(localSettings.statusLine?.command).toBe(bridgePath);

    // Bridge should chain with the original command via bash -c, not bash "$path"
    const bridgeContent = readFileSync(bridgePath, "utf8");
    expect(bridgeContent).toContain("bash -c");
    expect(bridgeContent).toContain("statusline-collector.sh");
    expect(bridgeContent).toContain(existingScript);
  });

  test("auto-install skips if harness bridge is already at local scope and upstream unchanged", () => {
    const project = createTempProject();
    const sessionId = "sess-skip-001";

    // First install
    execFileSync("bash", [autoInstallScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({ session_id: sessionId, cwd: project.root }),
      env: { ...process.env, HOME: project.home },
    });

    const bridgePath = join(project.root, ".claude", "statusline-parallel-harness.sh");
    expect(existsSync(bridgePath)).toBe(true);
    const bridgeMtime = Bun.file(bridgePath).lastModified;

    // Wait a tick to detect mtime change
    Bun.sleepSync(50);

    // Second install should skip (bridge already exists, no upstream change)
    execFileSync("bash", [autoInstallScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({ session_id: sessionId, cwd: project.root }),
      env: { ...process.env, HOME: project.home },
    });

    // Bridge file should not have been re-written
    expect(Bun.file(bridgePath).lastModified).toBe(bridgeMtime);
  });

  test("auto-install refreshes bridge when user adds a custom statusLine after initial install", () => {
    const project = createTempProject();
    const sessionId = "sess-refresh-001";

    // First install: no upstream statusLine → plain bridge (no chain)
    execFileSync("bash", [autoInstallScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({ session_id: sessionId, cwd: project.root }),
      env: { ...process.env, HOME: project.home },
    });

    const bridgePath = join(project.root, ".claude", "statusline-parallel-harness.sh");
    expect(existsSync(bridgePath)).toBe(true);
    const initialBridge = readFileSync(bridgePath, "utf8");
    expect(initialBridge).toContain("chain-target:");
    expect(initialBridge).not.toContain("bash -c");

    // User later adds a user-level statusLine
    const userClaudeDir = join(project.home, ".claude");
    mkdirSync(userClaudeDir, { recursive: true });
    const userSettings = join(userClaudeDir, "settings.json");
    writeFileSync(userSettings, JSON.stringify({
      statusLine: { type: "command", command: "/bin/echo custom status", padding: 1 },
    }));

    // Re-run auto-install — must detect the new upstream and refresh the bridge
    execFileSync("bash", [autoInstallScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({ session_id: sessionId, cwd: project.root }),
      env: { ...process.env, HOME: project.home },
    });

    const refreshedBridge = readFileSync(bridgePath, "utf8");
    expect(refreshedBridge).toContain("chain-target: /bin/echo custom status");
    expect(refreshedBridge).toContain("bash -c");
    expect(refreshedBridge).toContain("/bin/echo custom status");
    expect(refreshedBridge).toContain("statusline-collector.sh");
  });

  test("auto-install refreshes bridge when upstream statusLine is removed", () => {
    const project = createTempProject();
    const sessionId = "sess-refresh-remove-001";

    // Pre-configure user-level statusLine
    const userClaudeDir = join(project.home, ".claude");
    mkdirSync(userClaudeDir, { recursive: true });
    const userSettings = join(userClaudeDir, "settings.json");
    const existingCmd = join(project.home, "my-statusline.sh");
    writeFileSync(existingCmd, '#!/usr/bin/env bash\nprintf "custom"', { mode: 0o755 });
    writeFileSync(userSettings, JSON.stringify({
      statusLine: { type: "command", command: existingCmd, padding: 1 },
    }));

    // First install: chains with existing command
    execFileSync("bash", [autoInstallScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({ session_id: sessionId, cwd: project.root }),
      env: { ...process.env, HOME: project.home },
    });

    const bridgePath = join(project.root, ".claude", "statusline-parallel-harness.sh");
    const chainedBridge = readFileSync(bridgePath, "utf8");
    expect(chainedBridge).toContain(existingCmd);
    expect(chainedBridge).toContain("bash -c");

    // User removes their custom statusLine
    writeFileSync(userSettings, JSON.stringify({}));

    // Re-run auto-install — must detect upstream removal and refresh to non-chain
    execFileSync("bash", [autoInstallScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({ session_id: sessionId, cwd: project.root }),
      env: { ...process.env, HOME: project.home },
    });

    const refreshedBridge = readFileSync(bridgePath, "utf8");
    expect(refreshedBridge).not.toContain("bash -c");
    expect(refreshedBridge).not.toContain(existingCmd);
    expect(refreshedBridge).toContain("chain-target:");
    expect(refreshedBridge).toContain("statusline-collector.sh");
  });

  test("status line shows failed skill from PostToolUseFailure event", () => {
    const project = createTempProject();
    const sessionId = "sess-statusline-fail-001";

    runHook("PostToolUseFailure", project, {
      session_id: sessionId,
      cwd: project.root,
      tool_name: "Skill",
      tool_input: { skill: "parallel-harness:harness-verify" },
      error: "verification gate timed out",
      is_interrupt: false,
    });

    const statusOutput = execFileSync("bash", [statuslineScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: sessionId,
        cwd: project.root,
        model: "claude-opus",
      }),
      env: { ...process.env, HOME: project.home },
    });

    expect(statusOutput).toContain("[harness] skill harness-verify failed");
  });
});
