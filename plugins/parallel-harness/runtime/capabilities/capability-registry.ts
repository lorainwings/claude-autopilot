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

  /** 协议内容 — 从 SKILL.md 文件读取的完整协议文本 */
  protocol_content?: string;
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
// Skill Lifecycle Types — 运行时一等对象
// ============================================================

/** Skill 匹配结果 — resolve 阶段产出 */
export interface SkillMatch {
  /** 匹配到的 Skill ID */
  skill_id: string;
  /** 匹配原因 */
  match_reason: string;
  /** 阶段匹配 */
  phase_match: boolean;
  /** 语言匹配 */
  language_match: boolean;
  /** 路径匹配 */
  path_match: boolean;
  /** 匹配置信度 (0-1) */
  confidence: number;
}

/** Skill 选择来源 */
export type SkillSelectionSource = "explicit" | "phase_default" | "language_default" | "fallback";

/** 选中的 Skill — select 阶段产出 */
export interface SelectedSkill {
  /** Skill ID */
  skill_id: string;
  /** 选择原因 */
  selection_reason: string;
  /** 选择来源 */
  source: SkillSelectionSource;
  /** Skill 版本 */
  version: string;
}

/** Skill 调用状态 */
export type SkillInvocationStatus = "selected" | "injected" | "completed" | "failed" | "observed";

/** Skill 调用记录 — 审计与追踪 */
export interface SkillInvocationRecord {
  /** Run ID */
  run_id: string;
  /** Task ID */
  task_id: string;
  /** Attempt ID */
  attempt_id: string;
  /** 阶段 */
  phase: string;
  /** 选中的 Skill ID */
  selected_skill_id: string;
  /** 注入时间 */
  injected_at?: string;
  /** 完成时间 */
  completed_at?: string;
  /** 调用状态 */
  status: SkillInvocationStatus;
  /** 证据 */
  evidence?: Record<string, unknown>;
}

/** Skill 解析上下文 */
export interface SkillResolutionContext {
  /** 阶段 */
  phase?: string;
  /** 语言 */
  language?: string;
  /** 文件路径 */
  file_path?: string;
  /** 任务标题 */
  task_title?: string;
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

  /**
   * 按 phase/language/path 三维匹配，返回候选 SkillMatch 列表
   */
  resolve(context: SkillResolutionContext): SkillMatch[] {
    const matches: SkillMatch[] = [];

    for (const skill of this.skills.values()) {
      const phaseMatch = context.phase
        ? skill.applicable_phases.includes(context.phase)
        : false;
      const languageMatch = context.language
        ? (!skill.languages || skill.languages.includes(context.language))
        : true;
      const pathMatch = context.file_path && skill.path_patterns
        ? skill.path_patterns.some((p) => this.pathMatches(context.file_path!, p))
        : false;

      // 至少有一维匹配才纳入候选
      if (phaseMatch || (context.language && languageMatch && skill.languages) || pathMatch) {
        const reasons: string[] = [];
        if (phaseMatch) reasons.push(`phase:${context.phase}`);
        if (context.language && languageMatch && skill.languages) reasons.push(`language:${context.language}`);
        if (pathMatch) reasons.push(`path:${context.file_path}`);

        const confidence = (
          (phaseMatch ? 0.4 : 0) +
          (languageMatch && skill.languages ? 0.3 : 0) +
          (pathMatch ? 0.3 : 0)
        );

        matches.push({
          skill_id: skill.id,
          match_reason: reasons.join(", "),
          phase_match: phaseMatch,
          language_match: languageMatch,
          path_match: pathMatch,
          confidence,
        });
      }
    }

    // 按置信度降序排列
    return matches.sort((a, b) => b.confidence - a.confidence);
  }

  /**
   * 从候选列表中选出最佳 Skill
   */
  select(matches: SkillMatch[]): SelectedSkill | undefined {
    if (matches.length === 0) return undefined;

    const best = matches[0];
    const skill = this.skills.get(best.skill_id);
    if (!skill) return undefined;

    let source: SkillSelectionSource = "fallback";
    if (best.phase_match && best.language_match && best.path_match) {
      source = "explicit";
    } else if (best.phase_match) {
      source = "phase_default";
    } else if (best.language_match) {
      source = "language_default";
    }

    return {
      skill_id: best.skill_id,
      selection_reason: best.match_reason,
      source,
      version: skill.version,
    };
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
