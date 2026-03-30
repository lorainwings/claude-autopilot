/**
 * parallel-harness: Capability & Skill Extension Layer
 *
 * 可扩展资产层。对标 Copilot 自定义 agent/hook 和开源 capability-as-code。
 * 支持 repo-level 和 org-level 指令继承。
 */

import type { ModelTier } from "../orchestrator/task-graph";

// ============================================================
// Skill Manifest
// ============================================================

export interface SkillManifest {
  /** Skill ID */
  id: string;

  /** 名称 */
  name: string;

  /** 版本 */
  version: string;

  /** 描述 */
  description: string;

  /** 输入 schema */
  input_schema: Record<string, unknown>;

  /** 输出 schema */
  output_schema: Record<string, unknown>;

  /** 需要的权限 */
  permissions: string[];

  /** 依赖工具 */
  required_tools: string[];

  /** 推荐模型 tier */
  recommended_tier: ModelTier;

  /** 适用阶段 */
  applicable_phases: string[];

  /** 适用语言 */
  languages?: string[];

  /** 路径匹配 */
  path_patterns?: string[];
}

// ============================================================
// Instruction Pack
// ============================================================

export interface InstructionPack {
  /** Pack ID */
  id: string;

  /** 名称 */
  name: string;

  /** 作用域 */
  scope: InstructionScope;

  /** 指令内容 */
  instructions: Instruction[];

  /** 优先级 */
  priority: number;
}

export type InstructionScope =
  | { type: "org"; org_id: string }
  | { type: "repo"; repo_path: string }
  | { type: "path"; path_pattern: string }
  | { type: "language"; language: string };

export interface Instruction {
  /** 指令类型 */
  type: "coding" | "review" | "testing" | "documentation" | "security";

  /** 指令内容 */
  content: string;

  /** 条件 */
  condition?: string;
}

// ============================================================
// Instruction Registry
// ============================================================

export class InstructionRegistry {
  private packs: Map<string, InstructionPack> = new Map();

  register(pack: InstructionPack): void {
    this.packs.set(pack.id, pack);
  }

  /**
   * 获取适用于给定上下文的指令，按优先级排序
   */
  resolve(context: {
    org_id?: string;
    repo_path?: string;
    file_path?: string;
    language?: string;
  }): Instruction[] {
    const matchedPacks: InstructionPack[] = [];

    for (const pack of this.packs.values()) {
      if (this.matchesScope(pack.scope, context)) {
        matchedPacks.push(pack);
      }
    }

    // 按优先级排序（越小越高）
    matchedPacks.sort((a, b) => a.priority - b.priority);

    return matchedPacks.flatMap((p) => p.instructions);
  }

  private matchesScope(
    scope: InstructionScope,
    context: { org_id?: string; repo_path?: string; file_path?: string; language?: string }
  ): boolean {
    switch (scope.type) {
      case "org":
        return context.org_id === scope.org_id;
      case "repo":
        return context.repo_path === scope.repo_path;
      case "path":
        return !!context.file_path && this.pathMatches(context.file_path, scope.path_pattern);
      case "language":
        return context.language === scope.language;
      default:
        return false;
    }
  }

  private pathMatches(path: string, pattern: string): boolean {
    if (pattern.includes("*")) {
      const regex = new RegExp(
        "^" + pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$"
      );
      return regex.test(path);
    }
    return path.startsWith(pattern);
  }

  listAll(): InstructionPack[] {
    return [...this.packs.values()];
  }
}

// ============================================================
// Skill Registry
// ============================================================

export class SkillRegistry {
  private skills: Map<string, SkillManifest> = new Map();

  register(skill: SkillManifest): void {
    this.skills.set(skill.id, skill);
  }

  get(id: string): SkillManifest | undefined {
    return this.skills.get(id);
  }

  findByPhase(phase: string): SkillManifest[] {
    return [...this.skills.values()].filter(
      (s) => s.applicable_phases.includes(phase)
    );
  }

  findByLanguage(language: string): SkillManifest[] {
    return [...this.skills.values()].filter(
      (s) => !s.languages || s.languages.includes(language)
    );
  }

  listAll(): SkillManifest[] {
    return [...this.skills.values()];
  }
}

// ============================================================
// Hook Lifecycle
// ============================================================

export type HookPhase =
  | "pre_plan"
  | "post_plan"
  | "pre_dispatch"
  | "post_dispatch"
  | "pre_verify"
  | "post_verify"
  | "pre_merge"
  | "post_merge"
  | "pre_pr"
  | "post_pr";

export interface HookDefinition {
  id: string;
  name: string;
  phase: HookPhase;
  handler: (context: HookContext) => Promise<HookResult>;
  priority: number;
  enabled: boolean;
}

export interface HookContext {
  run_id: string;
  task_id?: string;
  phase: HookPhase;
  data: Record<string, unknown>;
}

export interface HookResult {
  continue: boolean;
  modified_data?: Record<string, unknown>;
  message?: string;
  /** Hook 产生的 effect — 可以影响主链决策 */
  effects?: HookEffect[];
}

/**
 * Hook Effect：hook 可以通过返回 effects 来影响主链行为。
 * 这使得扩展层从"能注册"升级为"能生效"。
 */
export interface HookEffect {
  type: "add_gate" | "add_contract" | "require_approval" | "reduce_concurrency" | "add_instruction";
  payload: Record<string, unknown>;
}

export class HookRegistry {
  private hooks: Map<string, HookDefinition> = new Map();

  register(hook: HookDefinition): void {
    this.hooks.set(hook.id, hook);
  }

  async executePhase(phase: HookPhase, context: Omit<HookContext, "phase">): Promise<HookResult[]> {
    const phaseHooks = [...this.hooks.values()]
      .filter((h) => h.phase === phase && h.enabled)
      .sort((a, b) => a.priority - b.priority);

    const results: HookResult[] = [];
    for (const hook of phaseHooks) {
      const result = await hook.handler({ ...context, phase });
      results.push(result);
      if (!result.continue) break;
    }

    return results;
  }

  listAll(): HookDefinition[] {
    return [...this.hooks.values()];
  }
}
