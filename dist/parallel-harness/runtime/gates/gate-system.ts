/**
 * parallel-harness: Gate System
 *
 * Verifier Swarm 升级为可阻断的门禁系统。
 * 每类 gate 有输入合同、阈值、结论、证据、阻断级别。
 *
 * 支持 task-level、run-level、PR-level 三层 gate。
 * 支持 incremental review 与 full review。
 *
 * Gate 类型：
 * - test: 测试通过率
 * - lint_type: lint 和类型检查
 * - review: 代码审查
 * - security: 安全扫描
 * - perf: 性能检查
 * - coverage: 测试覆盖率
 * - policy: 策略合规
 * - documentation: 文档完整性
 * - release_readiness: 发布就绪检查
 */

import type { TaskNode } from "../orchestrator/task-graph";
import type { WorkerOutput } from "../orchestrator/role-contracts";
import type { ExecutionContext } from "../engine/orchestrator-runtime";
import { classifyGate } from "./gate-classification";
import {
  generateId,
  SCHEMA_VERSION,
  type GateType,
  type GateLevel,
  type GateResult,
  type GateConclusion,
  type GateFinding,
  type SuggestedPatch,
  type RunPlan,
} from "../schemas/ga-schemas";

// ============================================================
// Gate Contract — 每类 Gate 的输入合同
// ============================================================

export interface GateContract {
  /** Gate 类型 */
  type: GateType;

  /** 阻断级别 */
  blocking: boolean;

  /** 适用层级 */
  levels: GateLevel[];

  /** 阈值配置 */
  thresholds: GateThresholds;
}

export interface GateThresholds {
  /** 最大允许 error 数 */
  max_errors: number;

  /** 最大允许 critical 数 */
  max_criticals: number;

  /** 最低通过率 (0-1) */
  min_pass_rate: number;

  /** 最低覆盖率 (0-1)，仅 coverage gate */
  min_coverage?: number;

  /** 自定义阈值 */
  custom: Record<string, number>;
}

/** 默认 gate 合同 */
export const DEFAULT_GATE_CONTRACTS: GateContract[] = [
  {
    type: "test",
    blocking: true,
    levels: ["task", "run"],
    thresholds: { max_errors: 0, max_criticals: 0, min_pass_rate: 1.0, custom: {} },
  },
  {
    type: "lint_type",
    blocking: true,
    levels: ["task", "run"],
    thresholds: { max_errors: 0, max_criticals: 0, min_pass_rate: 1.0, custom: {} },
  },
  {
    type: "review",
    blocking: false,
    levels: ["task", "run", "pr"],
    thresholds: { max_errors: 3, max_criticals: 0, min_pass_rate: 0.8, custom: {} },
  },
  {
    type: "security",
    blocking: true,
    levels: ["run", "pr"],
    thresholds: { max_errors: 0, max_criticals: 0, min_pass_rate: 1.0, custom: {} },
  },
  {
    type: "perf",
    blocking: false,
    levels: ["task", "run"],
    thresholds: { max_errors: 5, max_criticals: 1, min_pass_rate: 0.7, custom: {} },
  },
  {
    type: "coverage",
    blocking: false,
    levels: ["run", "pr"],
    thresholds: { max_errors: 0, max_criticals: 0, min_pass_rate: 0.8, min_coverage: 0.6, custom: {} },
  },
  {
    type: "policy",
    blocking: true,
    levels: ["task", "run"],
    thresholds: { max_errors: 0, max_criticals: 0, min_pass_rate: 1.0, custom: {} },
  },
  {
    type: "documentation",
    blocking: false,
    levels: ["run", "pr"],
    thresholds: { max_errors: 5, max_criticals: 0, min_pass_rate: 0.7, custom: {} },
  },
  {
    type: "release_readiness",
    blocking: true,
    levels: ["run"],
    thresholds: { max_errors: 0, max_criticals: 0, min_pass_rate: 1.0, custom: {} },
  },
];

// ============================================================
// Gate Evaluator Implementations
// ============================================================

/** 单个 Gate 评估器接口 */
export interface SingleGateEvaluator {
  type: GateType;
  evaluate(input: GateInput): Promise<GateResult>;
}

export interface GateInput {
  ctx: ExecutionContext;
  task?: TaskNode;
  workerOutput?: WorkerOutput;
  plan?: RunPlan;
  level: GateLevel;
  contract: GateContract;
}

// ============================================================
// Shell Execution Helper
// ============================================================

async function execShell(cmd: string, cwd?: string): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  try {
    const proc = Bun.spawn(["sh", "-c", cmd], {
      cwd,
      stdout: "pipe",
      stderr: "pipe",
    });
    const [stdout, stderr] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    const exitCode = await proc.exited;
    return { stdout: stdout.trim(), stderr: stderr.trim(), exitCode };
  } catch {
    return { stdout: "", stderr: "command not found or failed", exitCode: 127 };
  }
}

// ============================================================
// Test Gate — 真实执行 bun test
// ============================================================

export class TestGateEvaluator implements SingleGateEvaluator {
  type: GateType = "test";

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings: GateFinding[] = [];
    const cwd = input.ctx.project?.root_path;

    // 真实执行测试
    if (input.workerOutput && input.workerOutput.modified_paths.length > 0) {
      const testResult = await execShell("bun test 2>&1", cwd);

      if (testResult.exitCode !== 0) {
        // 解析失败的测试
        const failMatch = testResult.stdout.match(/(\d+)\s+fail/);
        const failCount = failMatch ? parseInt(failMatch[1]) : 1;

        findings.push({
          severity: "error",
          message: `测试失败: ${failCount} 个测试未通过`,
          rule_id: "TEST-001",
          suggestion: testResult.stderr || testResult.stdout.slice(0, 500),
        });

        // 提取失败文件
        const fileMatches = testResult.stdout.matchAll(/FAIL\s+([\w\-./]+)/g);
        for (const m of fileMatches) {
          findings.push({
            severity: "error",
            message: `测试文件失败: ${m[1]}`,
            file_path: m[1],
            rule_id: "TEST-002",
          });
        }
      } else {
        // 提取通过数
        const passMatch = testResult.stdout.match(/(\d+)\s+pass/);
        if (passMatch) {
          findings.push({
            severity: "info",
            message: `测试通过: ${passMatch[1]} 个`,
            rule_id: "TEST-000",
          });
        }
      }
    }

    // 检查是否有 required_tests 未覆盖
    if (input.task?.required_tests && input.task.required_tests.length > 0) {
      const modifiedTestFiles = (input.workerOutput?.modified_paths || []).filter(
        (p) => p.includes("test") || p.includes("spec")
      );
      if (modifiedTestFiles.length === 0 && input.workerOutput?.status === "ok") {
        findings.push({
          severity: "warning",
          message: "任务要求测试但未修改任何测试文件",
          rule_id: "TEST-003",
        });
      }
    }

    const errorCount = findings.filter((f) => f.severity === "error" || f.severity === "critical").length;
    const passed = errorCount <= input.contract.thresholds.max_errors;

    return this.buildResult(input, passed, findings);
  }

  private buildResult(input: GateInput, passed: boolean, findings: GateFinding[]): GateResult {
    return {
      schema_version: SCHEMA_VERSION,
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      task_id: input.task?.id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed ? "测试 gate 通过" : `测试 gate 未通过: ${findings.filter((f) => f.severity === "error").length} 个错误`,
        findings,
        risk: findings.some((f) => f.severity === "critical") ? "critical" : findings.some((f) => f.severity === "error") ? "high" : "low",
        required_actions: findings.filter((f) => f.severity === "error" || f.severity === "critical").map((f) => f.message),
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Lint/Type Gate — 真实执行 tsc / lint
// ============================================================

export class LintTypeGateEvaluator implements SingleGateEvaluator {
  type: GateType = "lint_type";

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings: GateFinding[] = [];
    const cwd = input.ctx.project?.root_path;

    if (input.workerOutput && input.workerOutput.modified_paths.length > 0) {
      const tsFiles = input.workerOutput.modified_paths.filter(
        (p) => p.endsWith(".ts") || p.endsWith(".tsx")
      );

      if (tsFiles.length > 0) {
        // 真实执行 tsc 类型检查
        const tscResult = await execShell("bunx tsc --noEmit 2>&1", cwd);

        if (tscResult.exitCode !== 0 && tscResult.stdout) {
          // 解析 tsc 错误
          const errorLines = tscResult.stdout.split("\n").filter((l) => l.includes("error TS"));
          for (const line of errorLines.slice(0, 20)) {
            const match = line.match(/^(.+?)\((\d+),\d+\):\s*error\s+TS\d+:\s*(.+)/);
            if (match) {
              findings.push({
                severity: "error",
                message: match[3],
                file_path: match[1],
                line: parseInt(match[2]),
                rule_id: "TSC-001",
              });
            }
          }
          if (errorLines.length > 20) {
            findings.push({
              severity: "warning",
              message: `还有 ${errorLines.length - 20} 个类型错误未展示`,
              rule_id: "TSC-002",
            });
          }
        }
      }

      // Python lint（独立于 TypeScript 条件块）
      const pyFiles = input.workerOutput.modified_paths.filter((p) => p.endsWith(".py"));
      if (pyFiles.length > 0) {
        const lintResult = await execShell(`ruff check ${pyFiles.join(" ")} 2>&1`, cwd);
        if (lintResult.exitCode !== 0) {
          findings.push({
            severity: "error",
            message: `Ruff lint 失败: ${lintResult.stdout.slice(0, 200)}`,
            rule_id: "LINT-001",
          });
        }
      }
    }

    const errorCount = findings.filter((f) => f.severity === "error" || f.severity === "critical").length;
    const passed = errorCount <= input.contract.thresholds.max_errors;

    return {
      schema_version: SCHEMA_VERSION,
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      task_id: input.task?.id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed ? "Lint/Type gate 通过" : `Lint/Type gate 未通过: ${errorCount} 个错误`,
        findings,
        risk: errorCount > 0 ? "high" : "low",
        required_actions: findings.filter((f) => f.severity === "error").map((f) => f.message),
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Review Gate
// ============================================================

export interface ReviewMode {
  type: "incremental" | "full";
  base_ref?: string;
}

export class ReviewGateEvaluator implements SingleGateEvaluator {
  type: GateType = "review";

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings: GateFinding[] = [];

    if (input.workerOutput) {
      // 检查输出质量
      if (!input.workerOutput.summary || input.workerOutput.summary.length < 10) {
        findings.push({
          severity: "warning",
          message: "Worker 输出摘要过短，建议补充",
        });
      }

      // 检查修改范围是否合理
      if (input.workerOutput.modified_paths.length > 20) {
        findings.push({
          severity: "warning",
          message: `修改了 ${input.workerOutput.modified_paths.length} 个文件，建议拆分`,
        });
      }

      // 检查是否有对应测试修改
      const hasSrcChanges = input.workerOutput.modified_paths.some((p) => !p.includes("test") && !p.includes("spec"));
      const hasTestChanges = input.workerOutput.modified_paths.some((p) => p.includes("test") || p.includes("spec"));
      if (hasSrcChanges && !hasTestChanges) {
        findings.push({
          severity: "warning",
          message: "修改了源代码但未修改对应测试",
        });
      }
    }

    const errorCount = findings.filter((f) => f.severity === "error" || f.severity === "critical").length;
    const passed = errorCount <= input.contract.thresholds.max_errors;

    return {
      schema_version: SCHEMA_VERSION,
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      task_id: input.task?.id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed
          ? `Review gate 通过 (${findings.length} 个建议)`
          : `Review gate 未通过`,
        findings,
        risk: findings.some((f) => f.severity === "error") ? "high" : "low",
        required_actions: findings.filter((f) => f.severity === "error").map((f) => f.message),
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Security Gate
// ============================================================

export class SecurityGateEvaluator implements SingleGateEvaluator {
  type: GateType = "security";

  /** 敏感文件模式 */
  private sensitivePatterns = [
    /\.env$/,
    /credentials/i,
    /secret/i,
    /password/i,
    /\.pem$/,
    /\.key$/,
    /token/i,
    /apikey/i,
  ];

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings: GateFinding[] = [];

    if (input.workerOutput) {
      for (const path of input.workerOutput.modified_paths) {
        // 检查是否修改了敏感文件
        if (this.sensitivePatterns.some((p) => p.test(path))) {
          findings.push({
            severity: "critical",
            message: `修改了敏感文件: ${path}`,
            file_path: path,
            rule_id: "SEC-001",
            suggestion: "请确认该修改是否必要，是否包含敏感信息",
          });
        }
      }
    }

    const criticalCount = findings.filter((f) => f.severity === "critical").length;
    const passed = criticalCount <= input.contract.thresholds.max_criticals;

    return {
      schema_version: SCHEMA_VERSION,
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      task_id: input.task?.id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed ? "Security gate 通过" : `Security gate 阻断: ${criticalCount} 个安全问题`,
        findings,
        risk: criticalCount > 0 ? "critical" : "low",
        required_actions: findings.filter((f) => f.severity === "critical").map((f) => f.message),
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Coverage Gate
// ============================================================

export class CoverageGateEvaluator implements SingleGateEvaluator {
  type: GateType = "coverage";

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings: GateFinding[] = [];
    const minCoverage = input.contract.thresholds.min_coverage || 0.6;
    const cwd = input.ctx.project?.root_path;

    if (input.workerOutput && input.workerOutput.modified_paths.length > 0) {
      // 尝试执行 bun test --coverage 并解析结果
      const covResult = await execShell("bun test --coverage 2>&1", cwd);

      // 解析覆盖率百分比
      const covMatch = covResult.stdout.match(/(\d+(?:\.\d+)?)\s*%\s*(?:Stmts|Lines|Coverage)/i);
      if (covMatch) {
        const coverage = parseFloat(covMatch[1]) / 100;
        if (coverage < minCoverage) {
          findings.push({
            severity: "error",
            message: `测试覆盖率 ${(coverage * 100).toFixed(1)}% 低于阈值 ${(minCoverage * 100).toFixed(0)}%`,
            rule_id: "COV-001",
          });
        } else {
          findings.push({
            severity: "info",
            message: `测试覆盖率 ${(coverage * 100).toFixed(1)}% 达标 (阈值 ${(minCoverage * 100).toFixed(0)}%)`,
            rule_id: "COV-000",
          });
        }
      } else {
        // 无法解析覆盖率，检查是否有测试文件变更作为启发式
        const hasTestFiles = input.workerOutput.modified_paths.some(
          (p) => p.includes("test") || p.includes("spec")
        );
        if (!hasTestFiles) {
          findings.push({
            severity: "warning",
            message: `未发现测试文件修改，覆盖率可能不足 (目标: ${(minCoverage * 100).toFixed(0)}%)`,
            rule_id: "COV-002",
          });
        }
      }
    }

    const errorCount = findings.filter((f) => f.severity === "error" || f.severity === "critical").length;
    const passed = errorCount === 0;

    return {
      schema_version: SCHEMA_VERSION,
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      task_id: input.task?.id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed ? "Coverage gate 通过" : "Coverage gate 未通过: 覆盖率不足",
        findings,
        risk: errorCount > 0 ? "medium" : "low",
        required_actions: findings.filter((f) => f.severity === "error").map((f) => f.message),
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Policy Gate
// ============================================================

export class PolicyGateEvaluator implements SingleGateEvaluator {
  type: GateType = "policy";

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings: GateFinding[] = [];

    // 通过 policy engine 评估
    const policyResult = input.ctx.policyEngine.evaluate(
      input.ctx,
      input.level === "task" ? "task_gate" : "run_gate",
      {
        task_id: input.task?.id,
        modified_paths: input.workerOutput?.modified_paths || [],
      }
    );

    if (!policyResult.allowed) {
      for (const v of policyResult.violations) {
        findings.push({
          severity: v.severity,
          message: v.message,
          rule_id: v.rule_id,
        });
      }
    }

    const passed = policyResult.allowed;

    return {
      schema_version: SCHEMA_VERSION,
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      task_id: input.task?.id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed ? "Policy gate 通过" : `Policy gate 阻断`,
        findings,
        risk: findings.some((f) => f.severity === "critical") ? "critical" : "low",
        required_actions: findings.filter((f) => f.severity === "error" || f.severity === "critical").map((f) => f.message),
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Documentation Gate
// ============================================================

export class DocumentationGateEvaluator implements SingleGateEvaluator {
  type: GateType = "documentation";

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings: GateFinding[] = [];

    if (input.workerOutput) {
      // 检查是否有需要文档的变更
      const hasNewFiles = input.workerOutput.artifacts.length > 0;
      const hasDocChanges = input.workerOutput.modified_paths.some(
        (p) => p.includes("doc") || p.includes("readme") || p.endsWith(".md")
      );

      if (hasNewFiles && !hasDocChanges) {
        findings.push({
          severity: "info",
          message: "新增了产出物但未更新文档",
          rule_id: "DOC-001",
        });
      }
    }

    const passed = findings.filter((f) => f.severity === "error").length <= input.contract.thresholds.max_errors;

    return {
      schema_version: SCHEMA_VERSION,
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      task_id: input.task?.id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed ? "Documentation gate 通过" : "Documentation gate 未通过",
        findings,
        risk: "low",
        required_actions: [],
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Perf Gate — 性能回归检查
// ============================================================

export class PerfGateEvaluator implements SingleGateEvaluator {
  type: GateType = "perf";

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings: GateFinding[] = [];
    const cwd = input.ctx.project?.root_path;

    if (input.workerOutput && input.workerOutput.modified_paths.length > 0) {
      // 检查是否引入了已知的性能反模式
      for (const path of input.workerOutput.modified_paths) {
        // 检查大文件
        if (input.workerOutput.tokens_used > 50000) {
          findings.push({
            severity: "warning",
            message: `Worker 消耗了 ${input.workerOutput.tokens_used} tokens，可能存在性能问题`,
            file_path: path,
            rule_id: "PERF-001",
          });
        }
      }

      // 执行耗时检查
      if (input.workerOutput.duration_ms > 120000) {
        findings.push({
          severity: "warning",
          message: `执行耗时 ${(input.workerOutput.duration_ms / 1000).toFixed(1)}s，超过 2 分钟阈值`,
          rule_id: "PERF-002",
        });
      }

      // 大量文件修改可能引发性能问题
      if (input.workerOutput.modified_paths.length > 50) {
        findings.push({
          severity: "warning",
          message: `修改了 ${input.workerOutput.modified_paths.length} 个文件，可能引发构建性能问题`,
          rule_id: "PERF-003",
        });
      }
    }

    const errorCount = findings.filter((f) => f.severity === "error" || f.severity === "critical").length;
    const passed = errorCount <= input.contract.thresholds.max_errors;

    return {
      schema_version: SCHEMA_VERSION,
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      task_id: input.task?.id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed ? "Perf gate 通过" : `Perf gate 警告: ${findings.length} 个性能问题`,
        findings,
        risk: findings.length > 3 ? "high" : findings.length > 0 ? "medium" : "low",
        required_actions: findings.filter((f) => f.severity === "error").map((f) => f.message),
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Release Readiness Gate
// ============================================================

export class ReleaseReadinessGateEvaluator implements SingleGateEvaluator {
  type: GateType = "release_readiness";

  async evaluate(input: GateInput): Promise<GateResult> {
    const findings: GateFinding[] = [];

    // Run-level 检查：所有任务是否完成
    if (input.plan) {
      const totalTasks = input.plan.task_graph.tasks.length;
      const completedTasks = input.plan.task_graph.tasks.filter(
        (t) => t.status === "verified" || t.status === "completed"
      ).length;

      if (completedTasks < totalTasks) {
        findings.push({
          severity: "error",
          message: `${totalTasks - completedTasks}/${totalTasks} 个任务未完成`,
          rule_id: "REL-001",
        });
      }
    }

    const passed = findings.filter((f) => f.severity === "error" || f.severity === "critical").length === 0;

    return {
      schema_version: SCHEMA_VERSION,
      gate_id: generateId("gate"),
      gate_type: this.type,
      gate_level: input.level,
      run_id: input.ctx.run_id,
      passed,
      blocking: input.contract.blocking,
      conclusion: {
        summary: passed ? "Release readiness gate 通过" : "Release readiness gate 未通过",
        findings,
        risk: passed ? "low" : "high",
        required_actions: findings.filter((f) => f.severity === "error").map((f) => f.message),
        suggested_patches: [],
      },
      evaluated_at: new Date().toISOString(),
    };
  }
}

// ============================================================
// Gate System — 统一门禁管理器
// ============================================================

export class GateSystem {
  private evaluators: Map<GateType, SingleGateEvaluator> = new Map();
  private contracts: Map<GateType, GateContract> = new Map();

  constructor(contracts: GateContract[] = DEFAULT_GATE_CONTRACTS) {
    // 注册默认评估器
    this.registerEvaluator(new TestGateEvaluator());
    this.registerEvaluator(new LintTypeGateEvaluator());
    this.registerEvaluator(new ReviewGateEvaluator());
    this.registerEvaluator(new SecurityGateEvaluator());
    this.registerEvaluator(new PerfGateEvaluator());
    this.registerEvaluator(new CoverageGateEvaluator());
    this.registerEvaluator(new PolicyGateEvaluator());
    this.registerEvaluator(new DocumentationGateEvaluator());
    this.registerEvaluator(new ReleaseReadinessGateEvaluator());

    for (const c of contracts) {
      this.contracts.set(c.type, c);
    }
  }

  registerEvaluator(evaluator: SingleGateEvaluator): void {
    this.evaluators.set(evaluator.type, evaluator);
  }

  /**
   * 评估指定层级和类型的 gates
   */
  async evaluate(
    input: Omit<GateInput, "contract">,
    enabledTypes: GateType[]
  ): Promise<GateResult[]> {
    const results: GateResult[] = [];

    for (const type of enabledTypes) {
      const evaluator = this.evaluators.get(type);
      const contract = this.contracts.get(type);

      if (!evaluator || !contract) continue;
      if (!contract.levels.includes(input.level)) continue;

      const result = await evaluator.evaluate({ ...input, contract });
      results.push(result);
    }

    return results;
  }

  /**
   * 检查是否有任何阻断性 gate 失败。
   * 结合 gate classification: signal gate 即使标记为 blocking 也不阻断，只有 hard gate 失败才阻断。
   */
  hasBlockingFailure(results: GateResult[]): boolean {
    return results.some((r) => {
      if (!r.blocking || r.passed) return false;
      const classification = classifyGate(r.gate_type);
      // 只有 hard gate 失败才真正阻断
      return classification.is_hard_gate;
    });
  }

  /**
   * 将 gate 结果按 hard/signal 分类，并提取阻断性失败。
   */
  classifyResults(results: GateResult[]): {
    hard_results: GateResult[];
    signal_results: GateResult[];
    blocking_failures: GateResult[];
  } {
    const hard_results: GateResult[] = [];
    const signal_results: GateResult[] = [];
    const blocking_failures: GateResult[] = [];

    for (const r of results) {
      const classification = classifyGate(r.gate_type);
      if (classification.is_hard_gate) {
        hard_results.push(r);
        if (r.blocking && !r.passed) {
          blocking_failures.push(r);
        }
      } else {
        signal_results.push(r);
      }
    }

    return { hard_results, signal_results, blocking_failures };
  }

  /**
   * 获取所有 gate 合同
   */
  getContracts(): GateContract[] {
    return [...this.contracts.values()];
  }

  /**
   * 获取已注册的评估器类型
   */
  getRegisteredTypes(): GateType[] {
    return [...this.evaluators.keys()];
  }
}
