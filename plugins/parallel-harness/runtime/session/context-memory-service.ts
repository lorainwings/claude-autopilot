/**
 * parallel-harness: Context Memory Service
 *
 * 替代截断式压缩的分层记忆系统。
 * 三层记忆: working (当前任务), episodic (阶段摘要), semantic (依赖索引)。
 * 支持失败原因记忆、role-aware retrieval、occupancy 保护阈值。
 */

// ============================================================
// 记忆层类型
// ============================================================

export type MemoryLayer = "working" | "episodic" | "semantic";
export type RoleType = "planner" | "author" | "verifier" | "synthesizer";

export interface MemoryEntry {
  id: string;
  layer: MemoryLayer;
  key: string;
  content: string;
  tokens_estimate: number;
  created_at: string;
  updated_at: string;
  relevance_score: number;
  source_task_id?: string;
  source_phase?: string;
  tags: string[];
}

export interface FailureMemory {
  task_id: string;
  failure_reason: string;
  failure_class: string;
  attempted_fix?: string;
  resolved: boolean;
  recorded_at: string;
}

export interface PhaseSummary {
  phase: string;
  summary: string;
  key_decisions: string[];
  artifacts_produced: string[];
  issues_encountered: string[];
  tokens_estimate: number;
  created_at: string;
}

export interface DependencyIndex {
  task_id: string;
  output_summary: string;
  modified_paths: string[];
  key_exports: string[];
  tokens_estimate: number;
}

// ============================================================
// Context Memory Service 配置
// ============================================================

export interface ContextMemoryConfig {
  /** 总 token 预算上限 */
  max_total_tokens: number;
  /** working 层占比上限 (0-1) */
  working_ratio: number;
  /** episodic 层占比上限 (0-1) */
  episodic_ratio: number;
  /** semantic 层占比上限 (0-1) */
  semantic_ratio: number;
  /** occupancy 保护阈值 (0-1)，超过此比例触发压缩 */
  occupancy_threshold: number;
  /** 每层最大条目数 */
  max_entries_per_layer: number;
}

const DEFAULT_CONFIG: ContextMemoryConfig = {
  max_total_tokens: 30000,
  working_ratio: 0.5,
  episodic_ratio: 0.3,
  semantic_ratio: 0.2,
  occupancy_threshold: 0.85,
  max_entries_per_layer: 50,
};

// ============================================================
// Context Memory Service
// ============================================================

export class ContextMemoryService {
  private config: ContextMemoryConfig;
  private working: Map<string, MemoryEntry> = new Map();
  private episodic: Map<string, MemoryEntry> = new Map();
  private semantic: Map<string, MemoryEntry> = new Map();
  private failures: FailureMemory[] = [];
  private phaseSummaries: Map<string, PhaseSummary> = new Map();
  private dependencyIndex: Map<string, DependencyIndex> = new Map();

  constructor(config: Partial<ContextMemoryConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  // ============================================================
  // 写入接口
  // ============================================================

  /** 添加 working 记忆（当前任务相关） */
  addWorkingMemory(key: string, content: string, taskId?: string, tags: string[] = []): void {
    this.addEntry("working", key, content, taskId, tags);
  }

  /** 添加 episodic 记忆（阶段摘要） */
  addEpisodicMemory(key: string, content: string, phase?: string, tags: string[] = []): void {
    const entry = this.addEntry("episodic", key, content, undefined, tags);
    entry.source_phase = phase;
  }

  /** 添加 semantic 记忆（依赖索引） */
  addSemanticMemory(key: string, content: string, tags: string[] = []): void {
    this.addEntry("semantic", key, content, undefined, tags);
  }

  /** 记录失败原因 */
  recordFailure(failure: FailureMemory): void {
    this.failures.push(failure);
    // 同时写入 episodic 层
    this.addEpisodicMemory(
      `failure:${failure.task_id}`,
      `任务 ${failure.task_id} 失败: ${failure.failure_reason} (${failure.failure_class})`,
      undefined,
      ["failure", failure.failure_class]
    );
  }

  /** 记录阶段摘要 */
  recordPhaseSummary(summary: PhaseSummary): void {
    this.phaseSummaries.set(summary.phase, summary);
    this.addEpisodicMemory(
      `phase:${summary.phase}`,
      summary.summary,
      summary.phase,
      ["phase_summary"]
    );
  }

  /** 记录依赖输出索引 */
  recordDependencyOutput(index: DependencyIndex): void {
    this.dependencyIndex.set(index.task_id, index);
    this.addSemanticMemory(
      `dep:${index.task_id}`,
      `任务 ${index.task_id} 输出: ${index.output_summary}. 修改: ${index.modified_paths.join(", ")}`,
      ["dependency"]
    );
  }

  // ============================================================
  // 检索接口
  // ============================================================

  /**
   * Role-aware 检索：根据角色返回不同优先级的记忆
   */
  retrieveForRole(role: RoleType, maxTokens?: number): MemoryEntry[] {
    const budget = maxTokens || this.config.max_total_tokens;
    let entries: MemoryEntry[] = [];

    switch (role) {
      case "planner":
        // planner 需要全局视图: episodic > semantic > working
        entries = [
          ...this.getLayerEntries("episodic"),
          ...this.getLayerEntries("semantic"),
          ...this.getLayerEntries("working"),
        ];
        break;
      case "author":
        // author 需要具体上下文: working > semantic > episodic
        entries = [
          ...this.getLayerEntries("working"),
          ...this.getLayerEntries("semantic"),
          ...this.getLayerEntries("episodic"),
        ];
        break;
      case "verifier":
        // verifier 需要规格和证据: semantic > episodic > working
        entries = [
          ...this.getLayerEntries("semantic"),
          ...this.getLayerEntries("episodic"),
          ...this.getLayerEntries("working"),
        ];
        break;
      case "synthesizer":
        // synthesizer 需要全面信息: episodic > working > semantic
        entries = [
          ...this.getLayerEntries("episodic"),
          ...this.getLayerEntries("working"),
          ...this.getLayerEntries("semantic"),
        ];
        break;
    }

    // 按 relevance_score 排序后截取到预算
    entries.sort((a, b) => b.relevance_score - a.relevance_score);
    return this.fitToBudget(entries, budget);
  }

  /** 按关键词检索 */
  search(query: string, maxResults: number = 10): MemoryEntry[] {
    const queryLower = query.toLowerCase();
    const allEntries = [
      ...this.getLayerEntries("working"),
      ...this.getLayerEntries("episodic"),
      ...this.getLayerEntries("semantic"),
    ];

    return allEntries
      .filter(e =>
        e.content.toLowerCase().includes(queryLower) ||
        e.key.toLowerCase().includes(queryLower) ||
        e.tags.some(t => t.toLowerCase().includes(queryLower))
      )
      .sort((a, b) => b.relevance_score - a.relevance_score)
      .slice(0, maxResults);
  }

  /** 获取失败记忆 */
  getFailures(resolved?: boolean): FailureMemory[] {
    if (resolved === undefined) return [...this.failures];
    return this.failures.filter(f => f.resolved === resolved);
  }

  /** 获取阶段摘要 */
  getPhaseSummary(phase: string): PhaseSummary | undefined {
    return this.phaseSummaries.get(phase);
  }

  /** 获取依赖索引 */
  getDependencyOutput(taskId: string): DependencyIndex | undefined {
    return this.dependencyIndex.get(taskId);
  }

  // ============================================================
  // 容量管理
  // ============================================================

  /** 获取当前 occupancy 比率 */
  getOccupancy(): number {
    const totalTokens = this.getTotalTokens();
    return totalTokens / this.config.max_total_tokens;
  }

  /** 获取各层 token 使用情况 */
  getLayerStats(): Record<MemoryLayer, { entries: number; tokens: number; ratio: number }> {
    const total = this.config.max_total_tokens;
    return {
      working: {
        entries: this.working.size,
        tokens: this.getLayerTokens("working"),
        ratio: this.getLayerTokens("working") / total,
      },
      episodic: {
        entries: this.episodic.size,
        tokens: this.getLayerTokens("episodic"),
        ratio: this.getLayerTokens("episodic") / total,
      },
      semantic: {
        entries: this.semantic.size,
        tokens: this.getLayerTokens("semantic"),
        ratio: this.getLayerTokens("semantic") / total,
      },
    };
  }

  /** 检查是否需要压缩 */
  needsCompaction(): boolean {
    return this.getOccupancy() >= this.config.occupancy_threshold;
  }

  /** 执行压缩：移除 relevance 最低的条目直到低于阈值 */
  compact(): number {
    let removed = 0;
    const targetTokens = this.config.max_total_tokens * (this.config.occupancy_threshold * 0.8);

    while (this.getTotalTokens() > targetTokens) {
      // 找所有层中 relevance 最低的条目
      let lowestEntry: MemoryEntry | undefined;
      let lowestLayer: MemoryLayer | undefined;

      for (const [layer, store] of [
        ["working", this.working],
        ["episodic", this.episodic],
        ["semantic", this.semantic],
      ] as const) {
        for (const entry of store.values()) {
          if (!lowestEntry || entry.relevance_score < lowestEntry.relevance_score) {
            lowestEntry = entry;
            lowestLayer = layer;
          }
        }
      }

      if (!lowestEntry || !lowestLayer) break;
      this.getLayerStore(lowestLayer).delete(lowestEntry.key);
      removed++;
    }

    return removed;
  }

  /** 清空 working 层（任务切换时） */
  clearWorking(): void {
    this.working.clear();
  }

  // ============================================================
  // 内部工具
  // ============================================================

  private addEntry(layer: MemoryLayer, key: string, content: string, taskId?: string, tags: string[] = []): MemoryEntry {
    const store = this.getLayerStore(layer);
    const tokensEstimate = Math.ceil(content.length / 4); // 粗略估算

    const entry: MemoryEntry = {
      id: `mem_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      layer,
      key,
      content,
      tokens_estimate: tokensEstimate,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      relevance_score: 1.0,
      source_task_id: taskId,
      tags,
    };

    // 如果超出层条目限制，移除最旧的
    if (store.size >= this.config.max_entries_per_layer) {
      const oldest = [...store.entries()].sort(
        (a, b) => new Date(a[1].created_at).getTime() - new Date(b[1].created_at).getTime()
      )[0];
      if (oldest) store.delete(oldest[0]);
    }

    store.set(key, entry);

    // 检查是否需要压缩
    if (this.needsCompaction()) {
      this.compact();
    }

    return entry;
  }

  private getLayerStore(layer: MemoryLayer): Map<string, MemoryEntry> {
    switch (layer) {
      case "working": return this.working;
      case "episodic": return this.episodic;
      case "semantic": return this.semantic;
    }
  }

  private getLayerEntries(layer: MemoryLayer): MemoryEntry[] {
    return [...this.getLayerStore(layer).values()];
  }

  private getLayerTokens(layer: MemoryLayer): number {
    let total = 0;
    for (const entry of this.getLayerStore(layer).values()) {
      total += entry.tokens_estimate;
    }
    return total;
  }

  private getTotalTokens(): number {
    return this.getLayerTokens("working") + this.getLayerTokens("episodic") + this.getLayerTokens("semantic");
  }

  private fitToBudget(entries: MemoryEntry[], maxTokens: number): MemoryEntry[] {
    const result: MemoryEntry[] = [];
    let usedTokens = 0;

    for (const entry of entries) {
      if (usedTokens + entry.tokens_estimate > maxTokens) break;
      result.push(entry);
      usedTokens += entry.tokens_estimate;
    }

    return result;
  }
}
