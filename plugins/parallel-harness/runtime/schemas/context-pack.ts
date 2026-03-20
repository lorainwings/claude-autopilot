/**
 * 上下文包 schema
 *
 * 定义为任务准备的最小上下文结构。
 * 上下文包包含与任务相关的文件、约束条件和引用信息，
 * 用于在发送给模型之前精确控制可见范围和 token 预算。
 */

// ─── 上下文文件 ─────────────────────────────────────────

/** 上下文文件：代表一个被纳入上下文的文件 */
export interface ContextFile {
  /** 文件路径（相对于项目根目录） */
  path: string;
  /** 文件内容（可选，延迟加载时可为空） */
  content?: string;
  /** 相关度评分 0-1，越高越相关 */
  relevance: number;
}

// ─── 上下文约束 ─────────────────────────────────────────

/** 上下文约束条件：限制上下文包的规模和范围 */
export interface ContextConstraints {
  /** 最大文件数量 */
  max_files: number;
  /** 最大 token 数量 */
  max_tokens: number;
  /** 允许包含的文件路径 glob 模式 */
  allowed_paths: string[];
  /** 禁止包含的文件路径 glob 模式 */
  forbidden_paths: string[];
}

// ─── 上下文包 ───────────────────────────────────────────

/** 上下文包：为某个任务打包好的最小上下文 */
export interface ContextPack {
  /** 关联的任务 id */
  task_id: string;
  /** 包含的上下文文件列表 */
  files: ContextFile[];
  /** 约束条件 */
  constraints: ContextConstraints;
  /** 引用的外部资源列表（文档链接、API 地址等） */
  references: string[];
  /** 全局 token 上限覆盖（可选，优先级高于 constraints.max_tokens） */
  max_tokens?: number;
}

// ─── 工厂函数 ───────────────────────────────────────────

/** 默认上下文约束 */
const DEFAULT_CONSTRAINTS: ContextConstraints = {
  max_files: 20,
  max_tokens: 8192,
  allowed_paths: ['**/*'],
  forbidden_paths: ['node_modules/**', '.git/**', 'dist/**'],
};

/**
 * 创建 ContextPack，未指定字段使用合理默认值。
 * @param partial - 部分 ContextPack 字段覆盖
 */
export function createContextPack(partial: Partial<ContextPack> = {}): ContextPack {
  return {
    task_id: partial.task_id ?? '',
    files: partial.files ?? [],
    constraints: partial.constraints ?? { ...DEFAULT_CONSTRAINTS },
    references: partial.references ?? [],
    max_tokens: partial.max_tokens,
  };
}

// ─── 验证函数 ───────────────────────────────────────────

/** 验证结果 */
export interface ContextPackValidation {
  /** 是否合法 */
  valid: boolean;
  /** 错误信息列表 */
  errors: string[];
}

/**
 * 验证 ContextPack 的结构完整性。
 * 检查内容：
 * - task_id 不能为空
 * - 文件路径不能为空
 * - relevance 必须在 0-1 之间
 * - 文件数量不超过 constraints.max_files
 * - constraints 中的 max_tokens 必须为正数
 */
export function validateContextPack(pack: ContextPack): ContextPackValidation {
  const errors: string[] = [];

  // task_id 检查
  if (!pack.task_id || pack.task_id.trim() === '') {
    errors.push('task_id 不能为空');
  }

  // 约束合法性检查
  if (pack.constraints.max_tokens <= 0) {
    errors.push('constraints.max_tokens 必须大于 0');
  }
  if (pack.constraints.max_files <= 0) {
    errors.push('constraints.max_files 必须大于 0');
  }

  // 全局 max_tokens 覆盖检查
  if (pack.max_tokens !== undefined && pack.max_tokens <= 0) {
    errors.push('max_tokens 覆盖值必须大于 0');
  }

  // 文件数量上限检查
  if (pack.files.length > pack.constraints.max_files) {
    errors.push(
      `文件数量 (${pack.files.length}) 超过上限 (${pack.constraints.max_files})`,
    );
  }

  // 逐文件检查
  for (const file of pack.files) {
    if (!file.path || file.path.trim() === '') {
      errors.push('文件路径不能为空');
    }
    if (file.relevance < 0 || file.relevance > 1) {
      errors.push(
        `文件 "${file.path}" 的 relevance (${file.relevance}) 必须在 0-1 之间`,
      );
    }
  }

  return { valid: errors.length === 0, errors };
}
