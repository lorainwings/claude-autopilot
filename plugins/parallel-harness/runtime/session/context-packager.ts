/**
 * 上下文打包器
 *
 * 为每个任务构建最小化的上下文包 (ContextPack)。
 * 根据 allowed_paths / forbidden_paths 过滤文件，按相关度排序，
 * 并截断到 token 限制以内。
 */

import type { TaskNode } from '../schemas/task-graph.js';
import type {
  ContextFile,
  ContextPack,
  ContextConstraints,
} from '../schemas/context-pack.js';

// ─── 打包选项 ───────────────────────────────────────────────

/** 上下文打包器的配置选项 */
export interface PackagingOptions {
  /** 最大文件数量 */
  max_files: number;
  /** 最大 token 数量 */
  max_tokens: number;
  /** 是否包含测试文件 */
  include_tests: boolean;
  /** 是否包含文档文件 */
  include_docs: boolean;
  /** 相关度阈值，低于此分数的文件将被过滤 */
  relevance_threshold: number;
}

/** 默认打包选项 */
const DEFAULT_OPTIONS: PackagingOptions = {
  max_files: 20,
  max_tokens: 50_000,
  include_tests: true,
  include_docs: false,
  relevance_threshold: 0.3,
};

// ─── 文件类别模式 ───────────────────────────────────────────

/** 测试文件路径模式 */
const TEST_PATTERNS = [
  /\.test\.[jt]sx?$/,
  /\.spec\.[jt]sx?$/,
  /__tests__\//,
  /tests?\//,
];

/** 文档文件路径模式 */
const DOC_PATTERNS = [
  /\.md$/i,
  /\.mdx$/i,
  /\.rst$/i,
  /docs?\//i,
  /README/i,
  /CHANGELOG/i,
];

// ─── 上下文打包器实现 ───────────────────────────────────────

export class ContextPackager {
  /** 当前生效的打包选项 */
  private readonly options: PackagingOptions;

  constructor(options?: Partial<PackagingOptions>) {
    this.options = { ...DEFAULT_OPTIONS, ...options };
  }

  /**
   * 为一个任务节点打包上下文
   *
   * 流程：
   *   1. 基于 allowed_paths / forbidden_paths 过滤可用文件
   *   2. 按选项过滤测试/文档文件
   *   3. 计算每个文件的相关度分数
   *   4. 按相关度阈值过滤
   *   5. 按相关度降序排序
   *   6. 截断到最大文件数和最大 token 数
   *
   * @param node 任务节点
   * @param availableFiles 当前项目中可用的文件路径列表
   * @returns 打包好的上下文包
   */
  pack(node: TaskNode, availableFiles: string[] = []): ContextPack {
    // 1. 路径过滤
    let filtered = this.filterByPaths(
      availableFiles,
      node.allowed_paths,
      node.forbidden_paths,
    );

    // 2. 按选项过滤测试和文档文件
    if (!this.options.include_tests) {
      filtered = filtered.filter(
        (f) => !TEST_PATTERNS.some((p) => p.test(f)),
      );
    }

    if (!this.options.include_docs) {
      filtered = filtered.filter(
        (f) => !DOC_PATTERNS.some((p) => p.test(f)),
      );
    }

    // 3. 计算相关度并构建 ContextFile 列表
    const contextFiles: ContextFile[] = filtered.map((filePath) => ({
      path: filePath,
      relevance: this.estimateRelevance(filePath, node),
    }));

    // 4. 按相关度阈值过滤
    const relevant = contextFiles.filter(
      (f) => f.relevance >= this.options.relevance_threshold,
    );

    // 5. 按相关度降序排序
    relevant.sort((a, b) => b.relevance - a.relevance);

    // 6. 截断到最大文件数
    const truncatedByCount = relevant.slice(0, this.options.max_files);

    // 构建初始 ContextPack
    const constraints: ContextConstraints = {
      max_files: this.options.max_files,
      max_tokens: this.options.max_tokens,
      allowed_paths: node.allowed_paths,
      forbidden_paths: node.forbidden_paths,
    };

    // 提取参考信息：验收标准 + 必要测试
    const references = [
      ...node.acceptance_criteria.map((c) => `验收标准: ${c}`),
      ...node.required_tests.map((t) => `必要测试: ${t}`),
    ];

    const pack: ContextPack = {
      task_id: node.id,
      files: truncatedByCount,
      constraints,
      references,
      max_tokens: this.options.max_tokens,
    };

    // 7. 按 token 限制截断
    return this.truncateToLimit(pack, this.options.max_tokens);
  }

  /**
   * 估算文件与任务的相关度（0-1 分）
   *
   * 打分策略：
   *   - 路径与 allowed_paths 匹配：基础 0.4 分
   *   - 文件名包含任务标题关键词：+0.3 分
   *   - 文件扩展名与任务目标中提到的技术相关：+0.2 分
   *   - 文件位于项目根目录附近（配置文件等）：+0.1 分
   */
  estimateRelevance(filePath: string, node: TaskNode): number {
    let score = 0;
    const normalizedPath = filePath.toLowerCase();

    // 1. 路径与 allowed_paths 的匹配程度
    if (node.allowed_paths.length > 0) {
      const pathMatch = node.allowed_paths.some((allowedPath) =>
        normalizedPath.startsWith(allowedPath.toLowerCase()),
      );
      if (pathMatch) score += 0.4;
    } else {
      // 如果没有指定 allowed_paths，给一个基础分
      score += 0.2;
    }

    // 2. 文件名是否包含任务标题中的关键词
    const titleWords = this.extractKeywords(node.title);
    const goalWords = this.extractKeywords(node.goal);
    const allKeywords = [...titleWords, ...goalWords];

    const fileName = normalizedPath.split('/').pop() ?? '';
    const keywordHits = allKeywords.filter((kw) =>
      fileName.includes(kw.toLowerCase()),
    ).length;

    if (keywordHits > 0) {
      // 命中关键词越多，分数越高，上限 0.3
      score += Math.min(0.3, keywordHits * 0.1);
    }

    // 3. 路径中包含关键词（目录级别匹配）
    const pathKeywordHits = allKeywords.filter((kw) =>
      normalizedPath.includes(kw.toLowerCase()),
    ).length;

    if (pathKeywordHits > keywordHits) {
      score += Math.min(0.2, (pathKeywordHits - keywordHits) * 0.05);
    }

    // 4. 配置文件 / 入口文件加分
    const isConfigFile =
      /\.(json|ya?ml|toml|config\.[jt]s)$/.test(normalizedPath) ||
      /index\.[jt]sx?$/.test(normalizedPath);
    if (isConfigFile) {
      score += 0.1;
    }

    // 确保分数在 0-1 范围内
    return Math.min(1.0, Math.max(0, score));
  }

  /**
   * 根据 allowed_paths 和 forbidden_paths 过滤文件列表
   *
   * - 如果 allowed_paths 为空，则不做允许路径过滤（全部允许）
   * - forbidden_paths 始终生效
   */
  filterByPaths(
    files: string[],
    allowed: string[],
    forbidden: string[],
  ): string[] {
    let result = files;

    // 允许路径过滤（如果有指定）
    if (allowed.length > 0) {
      result = result.filter((f) =>
        allowed.some((a) => f.startsWith(a) || f.includes(a)),
      );
    }

    // 禁止路径过滤（始终生效）
    if (forbidden.length > 0) {
      result = result.filter(
        (f) => !forbidden.some((fb) => f.startsWith(fb) || f.includes(fb)),
      );
    }

    return result;
  }

  /**
   * 将上下文包截断到指定的最大 token 数
   *
   * 从最低相关度的文件开始移除，直到总 token 数 ≤ maxTokens。
   */
  truncateToLimit(pack: ContextPack, maxTokens: number): ContextPack {
    // 计算引用部分占用的 token
    const referenceTokens = pack.references.reduce(
      (sum, ref) => sum + this.estimateTokens(ref),
      0,
    );

    // 可用于文件内容的 token 预算
    const fileTokenBudget = maxTokens - referenceTokens;

    if (fileTokenBudget <= 0) {
      // 引用本身已超限，清空文件列表
      return { ...pack, files: [] };
    }

    // 文件已按相关度降序排列，从前往后累加
    const keptFiles: ContextFile[] = [];
    let usedTokens = 0;

    for (const file of pack.files) {
      const fileTokens = file.content
        ? this.estimateTokens(file.content)
        : 500; // 未加载内容的文件预估 500 token（路径 + 元信息）

      if (usedTokens + fileTokens > fileTokenBudget) {
        // 超出预算，停止添加
        break;
      }

      keptFiles.push(file);
      usedTokens += fileTokens;
    }

    return { ...pack, files: keptFiles };
  }

  /**
   * 简单估算字符串的 token 数量
   *
   * 粗略按 4 个字符 ≈ 1 token 估算。
   * 这是一个保守的近似值，实际 tokenizer 可能更精确。
   */
  estimateTokens(content: string): number {
    return Math.ceil(content.length / 4);
  }

  // ── 内部辅助 ────────────────────────────────────────────

  /**
   * 从文本中提取关键词
   *
   * 去除常见停用词，保留长度 >= 2 的词汇。
   */
  private extractKeywords(text: string): string[] {
    // 常见英文停用词
    const stopWords = new Set([
      'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been',
      'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will',
      'would', 'could', 'should', 'may', 'might', 'can', 'shall',
      'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from',
      'as', 'into', 'through', 'during', 'before', 'after',
      'and', 'but', 'or', 'nor', 'not', 'so', 'yet',
      'this', 'that', 'these', 'those', 'it', 'its',
      // 常见中文虚词
      '的', '了', '在', '是', '和', '与', '对', '把', '被', '将',
      '要', '会', '能', '可以', '需要',
    ]);

    // 分词：按空格、标点、驼峰分割
    const words = text
      .replace(/([a-z])([A-Z])/g, '$1 $2') // 驼峰分割
      .replace(/[_\-./\\]/g, ' ') // 分隔符替换为空格
      .split(/\s+/)
      .map((w) => w.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]/g, ''))
      .filter((w) => w.length >= 2 && !stopWords.has(w));

    // 去重
    return [...new Set(words)];
  }

  // ── 只读访问器 ──────────────────────────────────────────

  /** 获取当前打包选项（只读副本） */
  getOptions(): Readonly<PackagingOptions> {
    return { ...this.options };
  }
}
