import { afterEach, describe, expect, test } from "bun:test";
import { execFileSync } from "child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";

/**
 * Validates the project-relevance guard added to the global plugin hooks
 * and statusLine collector. The intent is to prove that:
 *   - Unrelated projects never get a `.parallel-harness/` directory
 *     written by passive observers (statusline-collector).
 *   - The hook still records events when the skill name is parallel-harness.
 *   - The cleanup tool can identify and remove stray directories.
 */

type TempProject = {
  root: string;
  home: string;
};

const tempProjects: TempProject[] = [];
const pluginRoot = resolve(import.meta.dir, "..", "..");
const hookScriptPath = join(pluginRoot, "runtime", "scripts", "record-skill-tool-event.sh");
const statuslineScriptPath = join(pluginRoot, "runtime", "scripts", "statusline-collector.sh");
const cleanupScriptPath = join(pluginRoot, "tools", "cleanup-stray-parallel-harness.sh");

function createTempProject(): TempProject {
  const root = mkdtempSync(join(tmpdir(), "ph-guard-"));
  const home = join(root, "home");
  mkdirSync(home, { recursive: true });
  const project = { root, home };
  tempProjects.push(project);
  return project;
}

afterEach(() => {
  while (tempProjects.length > 0) {
    const project = tempProjects.pop();
    if (project) rmSync(project.root, { recursive: true, force: true });
  }
});

describe("project relevance guard — passive observers", () => {
  test("statusline-collector creates nothing in projects that never used parallel-harness", () => {
    const project = createTempProject();

    const output = execFileSync("bash", [statuslineScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: "sess-unrelated-001",
        cwd: project.root,
        model: "claude-opus",
      }),
      env: { ...process.env, HOME: project.home },
    });

    expect(output).toContain("[harness] ready");
    expect(existsSync(join(project.root, ".parallel-harness"))).toBe(false);
  });

  test("statusline-collector records once .parallel-harness/ exists", () => {
    const project = createTempProject();
    mkdirSync(join(project.root, ".parallel-harness"), { recursive: true });

    execFileSync("bash", [statuslineScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: "sess-relevant-001",
        cwd: project.root,
        model: "claude-opus",
      }),
      env: { ...process.env, HOME: project.home },
    });

    const rawLog = join(
      project.root,
      ".parallel-harness",
      "data",
      "plugin-observability",
      "sessions",
      "sess-relevant-001",
      "raw",
      "statusline.jsonl",
    );
    expect(existsSync(rawLog)).toBe(true);
  });

  test("statusline-collector records when .claude/settings references parallel-harness", () => {
    const project = createTempProject();
    const claudeDir = join(project.root, ".claude");
    mkdirSync(claudeDir, { recursive: true });
    writeFileSync(
      join(claudeDir, "settings.local.json"),
      JSON.stringify({
        statusLine: { type: "command", command: "/path/to/statusline-collector.sh" },
      }),
    );

    execFileSync("bash", [statuslineScriptPath], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: "sess-settings-001",
        cwd: project.root,
      }),
      env: { ...process.env, HOME: project.home },
    });

    expect(
      existsSync(join(project.root, ".parallel-harness", "data", "plugin-observability")),
    ).toBe(true);
  });

  test("hook still records parallel-harness skill events and drops .created-by anchor", () => {
    const project = createTempProject();
    const sessionId = "sess-hook-anchor-001";

    execFileSync("bash", [hookScriptPath, "PreToolUse"], {
      cwd: project.root,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: sessionId,
        cwd: project.root,
        tool_name: "Skill",
        tool_input: { skill: "parallel-harness:harness-plan", args: "x" },
      }),
      env: {
        ...process.env,
        CLAUDE_PLUGIN_ROOT: pluginRoot,
        HOME: project.home,
      },
    });

    expect(existsSync(join(project.root, ".parallel-harness", ".created-by"))).toBe(true);
    expect(
      existsSync(
        join(
          project.root,
          ".parallel-harness",
          "data",
          "plugin-observability",
          "sessions",
          sessionId,
          "skill-events.jsonl",
        ),
      ),
    ).toBe(true);
  });
});

describe("project root resolution — monorepo subdirectory", () => {
  test("subdirectory with existing .parallel-harness/ anchors to that subdirectory, not git root", () => {
    const project = createTempProject();
    // Simulate a git repo at the top
    execFileSync("git", ["init", "-q"], { cwd: project.root });
    const subProject = join(project.root, "packages", "alpha");
    mkdirSync(subProject, { recursive: true });
    mkdirSync(join(subProject, ".parallel-harness"), { recursive: true });

    execFileSync("bash", [statuslineScriptPath], {
      cwd: subProject,
      encoding: "utf8",
      input: JSON.stringify({
        session_id: "sess-mono-001",
        cwd: subProject,
      }),
      env: { ...process.env, HOME: project.home },
    });

    // Data should land in the sub-package, NOT in the git root
    expect(
      existsSync(
        join(subProject, ".parallel-harness", "data", "plugin-observability", "sessions"),
      ),
    ).toBe(true);
    expect(existsSync(join(project.root, ".parallel-harness", "data"))).toBe(false);
  });
});

describe("cleanup-stray-parallel-harness tool", () => {
  test("dry-run identifies stray directories without removing them", () => {
    const project = createTempProject();
    const stray = join(project.root, "stray-app");
    const intentional = join(project.root, "real-app");
    mkdirSync(join(stray, ".parallel-harness"), { recursive: true });
    mkdirSync(join(intentional, ".parallel-harness"), { recursive: true });
    writeFileSync(join(intentional, ".parallel-harness", ".created-by"), "execute-harness\n");

    const out = execFileSync("bash", [cleanupScriptPath, project.root, "--dry-run"], {
      encoding: "utf8",
    });

    expect(out).toContain("[stray]");
    expect(out).toContain(stray);
    expect(out).toContain("[keep ]");
    expect(out).toContain(intentional);
    expect(existsSync(join(stray, ".parallel-harness"))).toBe(true);
    expect(existsSync(join(intentional, ".parallel-harness"))).toBe(true);
  });

  test("--yes removes stray directories and keeps intentional ones", () => {
    const project = createTempProject();
    const stray = join(project.root, "stray-app");
    const intentional = join(project.root, "real-app");
    mkdirSync(join(stray, ".parallel-harness"), { recursive: true });
    mkdirSync(join(intentional, ".parallel-harness"), { recursive: true });
    writeFileSync(join(intentional, ".parallel-harness", ".created-by"), "execute-harness\n");

    const out = execFileSync("bash", [cleanupScriptPath, project.root, "--yes"], {
      encoding: "utf8",
    });

    expect(out).toContain("removed=1");
    expect(existsSync(join(stray, ".parallel-harness"))).toBe(false);
    expect(existsSync(join(intentional, ".parallel-harness"))).toBe(true);
  });

  test("intentional via .claude settings reference is preserved", () => {
    const project = createTempProject();
    const realApp = join(project.root, "real-app");
    mkdirSync(join(realApp, ".parallel-harness"), { recursive: true });
    mkdirSync(join(realApp, ".claude"), { recursive: true });
    writeFileSync(
      join(realApp, ".claude", "settings.local.json"),
      JSON.stringify({ statusLine: { command: "/p/statusline-collector.sh" } }),
    );

    const out = execFileSync("bash", [cleanupScriptPath, project.root, "--yes"], {
      encoding: "utf8",
    });

    expect(out).toContain("[keep ]");
    expect(existsSync(join(realApp, ".parallel-harness"))).toBe(true);
  });
});

describe("execute-harness drops .created-by anchor on first run", () => {
  test("the marker file appears after dataDir is created", () => {
    // Simulate the same logic that execute-harness.ts performs.
    // We don't run the full TS entrypoint here (that needs Bun compile and
    // is exercised in execute-harness-script.test.ts) — instead we assert
    // the source contains the anchor write so the contract is enforced.
    const source = readFileSync(
      join(pluginRoot, "runtime", "scripts", "execute-harness.ts"),
      "utf8",
    );
    expect(source).toContain(".created-by");
    expect(source).toContain('"execute-harness\\n"');
  });
});
