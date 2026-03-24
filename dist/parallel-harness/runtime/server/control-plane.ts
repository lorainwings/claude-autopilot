/**
 * parallel-harness: Control Plane Server
 *
 * 最小可操作的 HTTP API + Web GUI 服务。
 * 使用 Bun.serve 提供 REST API 和静态页面。
 *
 * 面板：run list、run detail、task graph、gate panel、cost panel、config diagnostics
 */

import { EventBus } from "../observability/event-bus";
import type {
  RunExecution,
  RunResult,
  RunPlan,
  AuditEvent,
  SessionState,
  GateResult,
  CostLedger,
} from "../schemas/ga-schemas";

// ============================================================
// Data Provider — 数据源抽象
// ============================================================

export interface ControlPlaneDataProvider {
  listRuns(): Promise<RunSummary[]>;
  getRun(runId: string): Promise<RunDetail | undefined>;
  getAuditLog(runId: string): Promise<AuditEvent[]>;
  getGateResults(runId: string): Promise<GateResult[]>;
  // 写操作
  cancelRun?(runId: string): Promise<{ ok: boolean; message: string }>;
  retryTask?(runId: string, taskId: string): Promise<{ ok: boolean; message: string }>;
  approveAction?(runId: string, approvalId: string): Promise<{ ok: boolean; message: string }>;
  rejectAction?(runId: string, approvalId: string): Promise<{ ok: boolean; message: string }>;
}

export interface RunSummary {
  run_id: string;
  status: string;
  intent: string;
  task_count: number;
  started_at: string;
  duration_ms: number;
  total_cost: number;
}

export interface RunDetail {
  run_id: string;
  status: string;
  intent: string;
  tasks: TaskSummary[];
  batches: BatchSummary[];
  cost: CostSummaryView;
  gate_results: GateResultView[];
  timeline: TimelineEvent[];
  started_at: string;
  completed_at?: string;
  duration_ms: number;
}

export interface TaskSummary {
  id: string;
  title: string;
  status: string;
  model_tier: string;
  attempts: number;
  tokens_used: number;
  duration_ms: number;
  risk_level: string;
}

export interface BatchSummary {
  batch_index: number;
  task_count: number;
  has_critical_path: boolean;
}

export interface CostSummaryView {
  total_tokens: number;
  total_cost: number;
  budget_limit: number;
  budget_utilization: number;
  tier_breakdown: { tier: string; tokens: number; cost: number }[];
}

export interface GateResultView {
  gate_type: string;
  level: string;
  passed: boolean;
  blocking: boolean;
  findings_count: number;
  summary: string;
}

export interface TimelineEvent {
  timestamp: string;
  type: string;
  task_id?: string;
  message: string;
}

// ============================================================
// In-Memory Data Provider
// ============================================================

export class InMemoryDataProvider implements ControlPlaneDataProvider {
  private runs: Map<string, RunDetail> = new Map();
  private auditLogs: Map<string, AuditEvent[]> = new Map();
  private gateResults: Map<string, GateResult[]> = new Map();

  addRun(detail: RunDetail): void {
    this.runs.set(detail.run_id, detail);
  }

  addAuditLog(runId: string, events: AuditEvent[]): void {
    this.auditLogs.set(runId, events);
  }

  addGateResults(runId: string, results: GateResult[]): void {
    this.gateResults.set(runId, results);
  }

  async listRuns(): Promise<RunSummary[]> {
    return [...this.runs.values()].map((r) => ({
      run_id: r.run_id,
      status: r.status,
      intent: r.intent,
      task_count: r.tasks.length,
      started_at: r.started_at,
      duration_ms: r.duration_ms,
      total_cost: r.cost.total_cost,
    }));
  }

  async getRun(runId: string): Promise<RunDetail | undefined> {
    return this.runs.get(runId);
  }

  async getAuditLog(runId: string): Promise<AuditEvent[]> {
    return this.auditLogs.get(runId) || [];
  }

  async getGateResults(runId: string): Promise<GateResult[]> {
    return this.gateResults.get(runId) || [];
  }

  async cancelRun(runId: string): Promise<{ ok: boolean; message: string }> {
    const run = this.runs.get(runId);
    if (!run) return { ok: false, message: `Run ${runId} 不存在` };
    if (run.status === "succeeded" || run.status === "cancelled") {
      return { ok: false, message: `Run ${runId} 已处于终态 ${run.status}` };
    }
    run.status = "cancelled";
    return { ok: true, message: `Run ${runId} 已取消` };
  }

  async retryTask(runId: string, taskId: string): Promise<{ ok: boolean; message: string }> {
    const run = this.runs.get(runId);
    if (!run) return { ok: false, message: `Run ${runId} 不存在` };
    const task = run.tasks.find((t) => t.id === taskId);
    if (!task) return { ok: false, message: `Task ${taskId} 不存在` };
    task.status = "pending";
    task.attempts += 1;
    return { ok: true, message: `Task ${taskId} 已标记为重试` };
  }

  async approveAction(runId: string, approvalId: string): Promise<{ ok: boolean; message: string }> {
    const run = this.runs.get(runId);
    if (!run) return { ok: false, message: `Run ${runId} 不存在` };
    if (run.status === "blocked") {
      run.status = "running";
    }
    return { ok: true, message: `审批 ${approvalId} 已通过，Run ${runId} 恢复执行` };
  }

  async rejectAction(runId: string, approvalId: string): Promise<{ ok: boolean; message: string }> {
    const run = this.runs.get(runId);
    if (!run) return { ok: false, message: `Run ${runId} 不存在` };
    run.status = "failed";
    return { ok: true, message: `审批 ${approvalId} 已拒绝，Run ${runId} 标记为失败` };
  }
}

// ============================================================
// Runtime Bridge Data Provider — 桥接 OrchestratorRuntime
// ============================================================

export interface RuntimeBridge {
  cancelRun(runId: string, cancelledBy?: string): Promise<void>;
  approveAndResume(runId: string, approvalId: string, decidedBy: string): Promise<unknown>;
  rejectRun(runId: string, approvalId: string, decidedBy: string, reason?: string): Promise<void>;
  // 读操作（现已强制实现，不再是可选）
  listRuns(): Promise<RunSummary[]>;
  getRun?(runId: string): Promise<RunDetail | undefined>;
  getRunDetail?(runId: string): Promise<RunDetail | undefined>;
  getAuditLog?(runId: string): Promise<AuditEvent[]>;
  getGateResults?(runId: string): Promise<GateResult[]>;
}

export class RuntimeBridgeDataProvider implements ControlPlaneDataProvider {
  private inner: InMemoryDataProvider;
  private runtime: RuntimeBridge;

  constructor(runtime: RuntimeBridge, inner?: InMemoryDataProvider) {
    this.runtime = runtime;
    this.inner = inner || new InMemoryDataProvider();
  }

  // 读操作优先从 runtime 读取，fallback 到 inner
  async listRuns() {
    return this.runtime.listRuns();
  }
  async getRun(runId: string) {
    // 优先使用专用的 getRunDetail()，否则回落到 getRun()，最终 fallback 到 inner
    if (this.runtime.getRunDetail) return this.runtime.getRunDetail(runId);
    if (this.runtime.getRun) return this.runtime.getRun(runId);
    return this.inner.getRun(runId);
  }
  async getAuditLog(runId: string) {
    if (this.runtime.getAuditLog) return this.runtime.getAuditLog(runId);
    return this.inner.getAuditLog(runId);
  }
  async getGateResults(runId: string) {
    if (this.runtime.getGateResults) return this.runtime.getGateResults(runId);
    return this.inner.getGateResults(runId);
  }

  // 写操作桥接到 runtime
  async cancelRun(runId: string): Promise<{ ok: boolean; message: string }> {
    try {
      await this.runtime.cancelRun(runId, "control-plane");
      return { ok: true, message: `Run ${runId} 已取消` };
    } catch (e) {
      return { ok: false, message: e instanceof Error ? e.message : String(e) };
    }
  }

  async approveAction(runId: string, approvalId: string): Promise<{ ok: boolean; message: string }> {
    try {
      await this.runtime.approveAndResume(runId, approvalId, "control-plane");
      return { ok: true, message: `审批 ${approvalId} 已通过` };
    } catch (e) {
      return { ok: false, message: e instanceof Error ? e.message : String(e) };
    }
  }

  async rejectAction(runId: string, approvalId: string): Promise<{ ok: boolean; message: string }> {
    try {
      await this.runtime.rejectRun(runId, approvalId, "control-plane");
      return { ok: true, message: `审批 ${approvalId} 已拒绝` };
    } catch (e) {
      return { ok: false, message: e instanceof Error ? e.message : String(e) };
    }
  }

  async retryTask(runId: string, taskId: string): Promise<{ ok: boolean; message: string }> {
    return this.inner.retryTask(runId, taskId);
  }

  /** 暴露 inner 以支持数据注入 */
  getInner(): InMemoryDataProvider { return this.inner; }
}

// ============================================================
// HTTP Server
// ============================================================

export interface ControlPlaneConfig {
  port: number;
  host: string;
  dataProvider: ControlPlaneDataProvider;
  /** 可选的 API token，设置后 POST 请求需要 Authorization header */
  apiToken?: string;
}

const DEFAULT_CONFIG: ControlPlaneConfig = {
  port: 9800,
  host: "127.0.0.1",
  dataProvider: new InMemoryDataProvider(),
};

export function createControlPlaneServer(config: Partial<ControlPlaneConfig> = {}) {
  const cfg = { ...DEFAULT_CONFIG, ...config };
  const provider = cfg.dataProvider;

  return Bun.serve({
    port: cfg.port,
    hostname: cfg.host,

    async fetch(req: Request): Promise<Response> {
      const url = new URL(req.url);
      const path = url.pathname;

      // 写操作 API (POST) — 必须在 GET 之前匹配
      if (req.method === "POST") {
        // API 鉴权
        if (cfg.apiToken) {
          const auth = req.headers.get("Authorization");
          if (auth !== `Bearer ${cfg.apiToken}`) {
            return Response.json({ ok: false, message: "Unauthorized" }, { status: 401 });
          }
        }

        if (path.match(/\/api\/runs\/[^/]+\/cancel$/)) {
          const runId = path.split("/api/runs/")[1].split("/cancel")[0];
          if (provider.cancelRun) {
            const result = await provider.cancelRun(runId);
            return Response.json(result, { status: result.ok ? 200 : 400 });
          }
          return Response.json({ ok: false, message: "cancelRun not implemented" }, { status: 501 });
        }

        if (path.match(/\/api\/runs\/[^/]+\/tasks\/[^/]+\/retry$/)) {
          const parts = path.split("/");
          const runsIdx = parts.indexOf("runs");
          const tasksIdx = parts.indexOf("tasks");
          const runId = parts[runsIdx + 1];
          const taskId = parts[tasksIdx + 1];
          if (provider.retryTask) {
            const result = await provider.retryTask(runId, taskId);
            return Response.json(result, { status: result.ok ? 200 : 400 });
          }
          return Response.json({ ok: false, message: "retryTask not implemented" }, { status: 501 });
        }

        if (path.match(/\/api\/runs\/[^/]+\/approve\/[^/]+$/)) {
          const runId = path.split("/api/runs/")[1].split("/approve/")[0];
          const approvalId = path.split("/approve/")[1];
          if (provider.approveAction) {
            const result = await provider.approveAction(runId, approvalId);
            return Response.json(result, { status: result.ok ? 200 : 400 });
          }
          return Response.json({ ok: false, message: "approveAction not implemented" }, { status: 501 });
        }

        if (path.match(/\/api\/runs\/[^/]+\/reject\/[^/]+$/)) {
          const runId = path.split("/api/runs/")[1].split("/reject/")[0];
          const approvalId = path.split("/reject/")[1];
          if (provider.rejectAction) {
            const result = await provider.rejectAction(runId, approvalId);
            return Response.json(result, { status: result.ok ? 200 : 400 });
          }
          return Response.json({ ok: false, message: "rejectAction not implemented" }, { status: 501 });
        }
      }

      // GET API Routes — 统一鉴权（除 /api/health 外）
      if (req.method === "GET" && path.startsWith("/api/") && path !== "/api/health") {
        if (cfg.apiToken) {
          const auth = req.headers.get("Authorization");
          if (auth !== `Bearer ${cfg.apiToken}`) {
            return Response.json({ ok: false, message: "Unauthorized" }, { status: 401 });
          }
        }
      }

      // GET API Routes
      if (path === "/api/runs") {
        const runs = await provider.listRuns();
        return Response.json(runs);
      }

      if (path.startsWith("/api/runs/") && !path.includes("/audit") && !path.includes("/gates")) {
        const runId = path.split("/api/runs/")[1];
        const run = await provider.getRun(runId);
        if (!run) return Response.json({ error: "Run not found" }, { status: 404 });
        return Response.json(run);
      }

      if (path.match(/\/api\/runs\/[^/]+\/audit/)) {
        const runId = path.split("/api/runs/")[1].split("/audit")[0];
        const log = await provider.getAuditLog(runId);
        return Response.json(log);
      }

      if (path.match(/\/api\/runs\/[^/]+\/gates/)) {
        const runId = path.split("/api/runs/")[1].split("/gates")[0];
        const gates = await provider.getGateResults(runId);
        return Response.json(gates);
      }

      if (path === "/api/health") {
        return Response.json({ status: "ok", version: "1.0.0" });
      }

      // GUI
      if (path === "/" || path === "/index.html") {
        return new Response(DASHBOARD_HTML, {
          headers: { "Content-Type": "text/html; charset=utf-8" },
        });
      }

      return Response.json({ error: "Not found" }, { status: 404 });
    },
  });
}

// ============================================================
// Dashboard HTML — 单文件 GUI
// ============================================================

const DASHBOARD_HTML = `<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>parallel-harness Control Plane</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; background: #0d1117; color: #c9d1d9; }
  .header { background: #161b22; border-bottom: 1px solid #30363d; padding: 12px 24px; display: flex; align-items: center; gap: 12px; }
  .header h1 { font-size: 16px; font-weight: 600; color: #f0f6fc; }
  .header .badge { background: #238636; color: #fff; padding: 2px 8px; border-radius: 12px; font-size: 11px; }
  .container { max-width: 1200px; margin: 0 auto; padding: 24px; }
  .panel { background: #161b22; border: 1px solid #30363d; border-radius: 6px; margin-bottom: 16px; }
  .panel-header { padding: 12px 16px; border-bottom: 1px solid #30363d; font-weight: 600; font-size: 14px; display: flex; justify-content: space-between; align-items: center; }
  .panel-body { padding: 16px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { text-align: left; padding: 8px 12px; border-bottom: 1px solid #30363d; color: #8b949e; font-weight: 500; }
  td { padding: 8px 12px; border-bottom: 1px solid #21262d; }
  tr:hover td { background: #1c2128; }
  .status { padding: 2px 8px; border-radius: 12px; font-size: 11px; font-weight: 600; }
  .status-succeeded { background: #238636; color: #fff; }
  .status-failed { background: #da3633; color: #fff; }
  .status-running { background: #1f6feb; color: #fff; }
  .status-pending { background: #6e7681; color: #fff; }
  .status-blocked { background: #d29922; color: #000; }
  .gate-pass { color: #3fb950; }
  .gate-fail { color: #f85149; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .metric { text-align: center; padding: 16px; }
  .metric-value { font-size: 28px; font-weight: 700; color: #f0f6fc; }
  .metric-label { font-size: 12px; color: #8b949e; margin-top: 4px; }
  .timeline { padding: 0; list-style: none; }
  .timeline li { padding: 8px 16px; border-left: 2px solid #30363d; margin-left: 8px; font-size: 12px; }
  .timeline li .time { color: #8b949e; margin-right: 8px; }
  .btn { background: #21262d; border: 1px solid #30363d; color: #c9d1d9; padding: 4px 12px; border-radius: 6px; cursor: pointer; font-size: 12px; }
  .btn:hover { background: #30363d; }
  .empty { text-align: center; padding: 40px; color: #8b949e; }
  #detail { display: none; }
  .back-btn { cursor: pointer; color: #58a6ff; font-size: 13px; }
  .back-btn:hover { text-decoration: underline; }
  .task-graph { display: flex; flex-wrap: wrap; gap: 8px; padding: 8px; }
  .task-node { background: #21262d; border: 1px solid #30363d; border-radius: 6px; padding: 8px 12px; font-size: 12px; min-width: 120px; }
  .task-node .task-title { font-weight: 600; color: #f0f6fc; margin-bottom: 4px; }
  .task-node .task-meta { color: #8b949e; font-size: 11px; }
</style>
</head>
<body>
<div class="header">
  <h1>parallel-harness</h1>
  <span class="badge">Control Plane v1.0.0</span>
  <span style="flex:1"></span>
  <button class="btn" onclick="refresh()">刷新</button>
</div>

<div class="container">
  <!-- Run List View -->
  <div id="list">
    <div class="panel">
      <div class="panel-header">Run 列表 <span id="run-count" style="color:#8b949e;font-weight:400;font-size:12px"></span></div>
      <div class="panel-body">
        <table>
          <thead><tr><th>Run ID</th><th>状态</th><th>意图</th><th>任务数</th><th>耗时</th><th>成本</th><th>操作</th></tr></thead>
          <tbody id="run-list"></tbody>
        </table>
        <div id="empty-state" class="empty">暂无 Run 数据。启动一次 parallel-harness 执行后将自动显示。</div>
      </div>
    </div>
  </div>

  <!-- Run Detail View -->
  <div id="detail">
    <p class="back-btn" onclick="showList()">&larr; 返回列表</p>
    <div class="grid" style="margin-top:12px">
      <div class="panel">
        <div class="panel-header">概览</div>
        <div class="panel-body grid" style="grid-template-columns:1fr 1fr 1fr 1fr">
          <div class="metric"><div class="metric-value" id="d-tasks">0</div><div class="metric-label">任务数</div></div>
          <div class="metric"><div class="metric-value" id="d-cost">0</div><div class="metric-label">总成本</div></div>
          <div class="metric"><div class="metric-value" id="d-tokens">0</div><div class="metric-label">Token</div></div>
          <div class="metric"><div class="metric-value" id="d-duration">0</div><div class="metric-label">耗时</div></div>
        </div>
      </div>
      <div class="panel">
        <div class="panel-header">Gate 结果</div>
        <div class="panel-body"><table><thead><tr><th>Gate</th><th>状态</th><th>阻断</th><th>发现数</th></tr></thead><tbody id="d-gates"></tbody></table></div>
      </div>
    </div>

    <div class="panel">
      <div class="panel-header">Task Graph</div>
      <div class="panel-body task-graph" id="d-graph"></div>
    </div>

    <div class="grid">
      <div class="panel">
        <div class="panel-header">任务列表</div>
        <div class="panel-body"><table><thead><tr><th>ID</th><th>标题</th><th>状态</th><th>模型</th><th>Token</th><th>耗时</th></tr></thead><tbody id="d-tasks-table"></tbody></table></div>
      </div>
      <div class="panel">
        <div class="panel-header">时间线</div>
        <div class="panel-body"><ul class="timeline" id="d-timeline"></ul></div>
      </div>
    </div>
  </div>
</div>

<script>
let currentRuns = [];

async function refresh() {
  try {
    const res = await fetch('/api/runs');
    currentRuns = await res.json();
    renderList();
  } catch(e) { console.error(e); }
}

function renderList() {
  const el = document.getElementById('run-list');
  const empty = document.getElementById('empty-state');
  const count = document.getElementById('run-count');
  if (!currentRuns.length) { el.innerHTML = ''; empty.style.display = ''; count.textContent = ''; return; }
  empty.style.display = 'none';
  count.textContent = '(' + currentRuns.length + ')';
  el.innerHTML = currentRuns.map(r =>
    '<tr><td style="font-family:monospace;font-size:12px">' + r.run_id.slice(0,16) + '</td>' +
    '<td><span class="status status-' + r.status + '">' + r.status + '</span></td>' +
    '<td>' + (r.intent||'').slice(0,40) + '</td>' +
    '<td>' + r.task_count + '</td>' +
    '<td>' + fmtDur(r.duration_ms) + '</td>' +
    '<td>' + r.total_cost.toFixed(1) + '</td>' +
    '<td><button class="btn" onclick="showDetail(\\'' + r.run_id + '\\')">详情</button> ' +
    '<button class="btn" style="color:#f85149" onclick="cancelRun(\\'' + r.run_id + '\\')">取消</button></td></tr>'
  ).join('');
}

async function showDetail(runId) {
  try {
    const [run, gates, audit] = await Promise.all([
      fetch('/api/runs/' + runId).then(r=>r.json()),
      fetch('/api/runs/' + runId + '/gates').then(r=>r.json()),
      fetch('/api/runs/' + runId + '/audit').then(r=>r.json()),
    ]);
    document.getElementById('list').style.display = 'none';
    document.getElementById('detail').style.display = '';
    document.getElementById('d-tasks').textContent = run.tasks?.length || 0;
    document.getElementById('d-cost').textContent = (run.cost?.total_cost || 0).toFixed(1);
    document.getElementById('d-tokens').textContent = fmtNum(run.cost?.total_tokens || 0);
    document.getElementById('d-duration').textContent = fmtDur(run.duration_ms);

    // Gates
    const gEl = document.getElementById('d-gates');
    gEl.innerHTML = (run.gate_results||[]).map(g =>
      '<tr><td>' + g.gate_type + '</td>' +
      '<td class="' + (g.passed?'gate-pass':'gate-fail') + '">' + (g.passed?'PASS':'FAIL') + '</td>' +
      '<td>' + (g.blocking?'Yes':'No') + '</td>' +
      '<td>' + g.findings_count + '</td></tr>'
    ).join('') || '<tr><td colspan=4 style="color:#8b949e">无 gate 数据</td></tr>';

    // Task Graph
    const graphEl = document.getElementById('d-graph');
    graphEl.innerHTML = (run.tasks||[]).map(t =>
      '<div class="task-node"><div class="task-title">' + t.title + '</div>' +
      '<div class="task-meta"><span class="status status-' + mapStatus(t.status) + '">' + t.status + '</span> ' + t.model_tier + '</div></div>'
    ).join('') || '<div style="color:#8b949e">无任务数据</div>';

    // Task Table
    const tEl = document.getElementById('d-tasks-table');
    tEl.innerHTML = (run.tasks||[]).map(t =>
      '<tr><td style="font-family:monospace;font-size:11px">' + t.id.slice(0,12) + '</td>' +
      '<td>' + t.title + '</td>' +
      '<td><span class="status status-' + mapStatus(t.status) + '">' + t.status + '</span></td>' +
      '<td>' + t.model_tier + '</td>' +
      '<td>' + fmtNum(t.tokens_used) + '</td>' +
      '<td>' + fmtDur(t.duration_ms) + '</td></tr>'
    ).join('');

    // Timeline
    const tlEl = document.getElementById('d-timeline');
    const events = (run.timeline||audit||[]).slice(0,50);
    tlEl.innerHTML = events.map(e =>
      '<li><span class="time">' + fmtTime(e.timestamp) + '</span>' + (e.type||e.message||'') + (e.task_id?' ['+e.task_id.slice(0,8)+']':'') + '</li>'
    ).join('') || '<li style="color:#8b949e">无时间线数据</li>';

  } catch(e) { console.error(e); }
}

function showList() {
  document.getElementById('list').style.display = '';
  document.getElementById('detail').style.display = 'none';
}

function mapStatus(s) {
  if (s === 'verified' || s === 'completed') return 'succeeded';
  if (s === 'failed') return 'failed';
  if (s === 'running' || s === 'dispatched') return 'running';
  if (s === 'blocked') return 'blocked';
  return 'pending';
}

function fmtDur(ms) { return ms < 1000 ? ms + 'ms' : ms < 60000 ? (ms/1000).toFixed(1) + 's' : (ms/60000).toFixed(1) + 'm'; }
function fmtNum(n) { return n >= 1000 ? (n/1000).toFixed(1) + 'k' : String(n); }
function fmtTime(t) { if (!t) return ''; try { return new Date(t).toLocaleTimeString(); } catch { return t; } }

refresh();
setInterval(refresh, 10000);

async function cancelRun(runId) {
  if (!confirm('确认取消 Run ' + runId.slice(0,12) + '?')) return;
  try {
    const res = await fetch('/api/runs/' + runId + '/cancel', { method: 'POST' });
    const data = await res.json();
    alert(data.message);
    refresh();
  } catch(e) { alert('取消失败: ' + e); }
}

async function retryTask(runId, taskId) {
  try {
    const res = await fetch('/api/runs/' + runId + '/tasks/' + taskId + '/retry', { method: 'POST' });
    const data = await res.json();
    alert(data.message);
  } catch(e) { alert('重试失败: ' + e); }
}

async function approveAction(runId, approvalId) {
  try {
    const res = await fetch('/api/runs/' + runId + '/approve/' + approvalId, { method: 'POST' });
    const data = await res.json();
    alert(data.message);
  } catch(e) { alert('审批失败: ' + e); }
}
</script>
</body>
</html>`;
