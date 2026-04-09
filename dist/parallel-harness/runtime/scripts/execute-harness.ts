import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  DEFAULT_RUN_CONFIG,
  SCHEMA_VERSION,
  generateId,
  type RunConfig,
  type RunRequest,
  type RunResult,
} from "../schemas/ga-schemas";
import {
  LocalWorkerAdapter,
  OrchestratorRuntime,
  type WorkerAdapter,
} from "../engine/orchestrator-runtime";
import type { WorkerInput, WorkerOutput } from "../orchestrator/role-contracts";

export type WorkerAdapterMode = "local" | "mock-success" | "mock-fail";

export interface HarnessCliArgs {
  intent?: string;
  intentFile?: string;
  projectRoot: string;
  configPath?: string;
  output: "json" | "text";
  workerAdapterMode: WorkerAdapterMode;
}

export interface HarnessRunSummary {
  ok: boolean;
  run_id?: string;
  final_status?: string;
  completed_tasks?: string[];
  failed_tasks?: Array<{ task_id: string; failure_class?: string; summary?: string }>;
  skipped_tasks?: string[];
  quality_grade?: string;
  budget_utilization?: number;
  recommendations?: string[];
  error?: string;
}

export interface HarnessRunExecutor {
  executeRun(request: RunRequest): Promise<RunResult>;
}

class MockSuccessAdapter implements WorkerAdapter {
  async execute(input: WorkerInput): Promise<WorkerOutput> {
    const paths = input.contract.allowed_paths.length > 0
      ? [input.contract.allowed_paths[0].replace(/\/?$/, "/") + "result.ts"]
      : ["src/result.ts"];
    return {
      status: "ok",
      summary: `完成任务: ${input.contract.goal}`,
      artifacts: [],
      modified_paths: paths,
      tokens_used: 500,
      duration_ms: 50,
      actual_tool_calls: [],
      exit_code: 0,
    };
  }
}

class MockFailAdapter implements WorkerAdapter {
  async execute(_input: WorkerInput): Promise<WorkerOutput> {
    return {
      status: "failed",
      summary: "执行失败：模拟错误",
      artifacts: [],
      modified_paths: [],
      tokens_used: 0,
      duration_ms: 10,
      actual_tool_calls: [],
      exit_code: 1,
    };
  }
}

const SCRIPT_DIR = resolve(fileURLToPath(new URL(".", import.meta.url)));
const PLUGIN_ROOT = resolve(SCRIPT_DIR, "../..");

export function parseHarnessCliArgs(argv: string[]): HarnessCliArgs {
  const parsed: HarnessCliArgs = {
    projectRoot: process.cwd(),
    output: "json",
    workerAdapterMode: "local",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "--intent":
        parsed.intent = argv[i + 1];
        i += 1;
        break;
      case "--intent-file":
        parsed.intentFile = argv[i + 1];
        i += 1;
        break;
      case "--project-root":
        parsed.projectRoot = resolve(argv[i + 1]);
        i += 1;
        break;
      case "--config":
        parsed.configPath = resolve(argv[i + 1]);
        i += 1;
        break;
      case "--output":
        parsed.output = argv[i + 1] === "text" ? "text" : "json";
        i += 1;
        break;
      case "--worker-adapter":
        if (argv[i + 1] === "mock-success" || argv[i + 1] === "mock-fail" || argv[i + 1] === "local") {
          parsed.workerAdapterMode = argv[i + 1] as WorkerAdapterMode;
        }
        i += 1;
        break;
    }
  }

  return parsed;
}

export function detectKnownModules(projectRoot: string): string[] {
  const candidates = ["src", "app", "lib", "packages", "services", "modules"];
  const detected = candidates.filter((candidate) => existsSync(join(projectRoot, candidate)));
  return detected.length > 0 ? detected : ["."];
}

export function loadRunConfig(pluginRoot = PLUGIN_ROOT, configPath?: string): RunConfig {
  const resolvedConfigPath = configPath || resolve(pluginRoot, "config/default-config.json");

  try {
    const parsed = JSON.parse(readFileSync(resolvedConfigPath, "utf-8")) as { run_config?: RunConfig };
    return {
      ...DEFAULT_RUN_CONFIG,
      ...(parsed.run_config || {}),
    };
  } catch {
    return { ...DEFAULT_RUN_CONFIG };
  }
}

export function createHarnessRunRequest(intent: string, projectRoot: string, config: RunConfig): RunRequest {
  return {
    schema_version: SCHEMA_VERSION,
    request_id: generateId("req"),
    intent,
    actor: {
      id: process.env.USER || "parallel-harness",
      type: "user",
      name: process.env.USER || "parallel-harness",
      roles: ["developer"],
    },
    project: {
      root_path: projectRoot,
      known_modules: detectKnownModules(projectRoot),
      scope: {},
    },
    config,
    requested_at: new Date().toISOString(),
  };
}

export function selectWorkerAdapter(mode: WorkerAdapterMode): WorkerAdapter {
  switch (mode) {
    case "mock-success":
      return new MockSuccessAdapter();
    case "mock-fail":
      return new MockFailAdapter();
    case "local":
    default:
      return new LocalWorkerAdapter();
  }
}

function prepareConfig(config: RunConfig, workerAdapterMode: WorkerAdapterMode): RunConfig {
  if (workerAdapterMode === "local") return config;
  return {
    ...config,
    enabled_gates: [],
    auto_approve_rules: ["all"],
    pr_strategy: "none",
  };
}

function resolveIntent(args: HarnessCliArgs): string {
  if (args.intent && args.intent.trim()) return args.intent.trim();
  if (args.intentFile) {
    return readFileSync(args.intentFile, "utf-8").trim();
  }
  throw new Error("missing intent: provide --intent or --intent-file");
}

export async function executeHarnessRun(
  args: HarnessCliArgs,
  runtime?: HarnessRunExecutor,
): Promise<HarnessRunSummary> {
  process.env.CLAUDE_PLUGIN_ROOT ||= PLUGIN_ROOT;

  const intent = resolveIntent(args);
  const config = prepareConfig(loadRunConfig(PLUGIN_ROOT, args.configPath), args.workerAdapterMode);
  const runExecutor = runtime || new OrchestratorRuntime({
    workerAdapter: selectWorkerAdapter(args.workerAdapterMode),
    dataDir: resolve(args.projectRoot, ".parallel-harness/data"),
  });

  const result = await runExecutor.executeRun(createHarnessRunRequest(intent, args.projectRoot, config));

  return {
    ok: true,
    run_id: result.run_id,
    final_status: result.final_status,
    completed_tasks: result.completed_tasks,
    failed_tasks: result.failed_tasks.map((task) => ({
      task_id: task.task_id,
      failure_class: task.failure_class,
      summary: task.message,
    })),
    skipped_tasks: result.skipped_tasks,
    quality_grade: result.quality_report.overall_grade,
    budget_utilization: result.cost_summary.budget_utilization,
    recommendations: result.quality_report.recommendations,
  };
}

function renderText(summary: HarnessRunSummary): string {
  if (!summary.ok) {
    return `parallel-harness run failed: ${summary.error || "unknown error"}`;
  }

  const lines = [
    `run_id: ${summary.run_id}`,
    `final_status: ${summary.final_status}`,
    `completed_tasks: ${summary.completed_tasks?.length || 0}`,
    `failed_tasks: ${summary.failed_tasks?.length || 0}`,
    `skipped_tasks: ${summary.skipped_tasks?.length || 0}`,
    `quality_grade: ${summary.quality_grade || "-"}`,
  ];

  if (summary.recommendations && summary.recommendations.length > 0) {
    lines.push("recommendations:");
    for (const recommendation of summary.recommendations.slice(0, 5)) {
      lines.push(`- ${recommendation}`);
    }
  }

  return lines.join("\n");
}

if (import.meta.main) {
  const args = parseHarnessCliArgs(process.argv.slice(2));

  try {
    const summary = await executeHarnessRun(args);
    const output = args.output === "text"
      ? renderText(summary)
      : JSON.stringify(summary, null, 2);
    process.stdout.write(`${output}\n`);
  } catch (error) {
    const summary: HarnessRunSummary = {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
    process.stderr.write(`${JSON.stringify(summary, null, 2)}\n`);
    process.exitCode = 1;
  }
}
