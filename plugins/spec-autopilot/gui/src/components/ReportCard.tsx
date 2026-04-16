/**
 * ReportCard — v7.0 测试报告卡片 (工作包 D)
 * 主窗口一等展示: 报告格式、pass rate、suite results、anomaly alerts、Allure 链接
 * minimal 模式显示合理降级态
 */

import { memo } from "react";
import { useStore } from "../store";
import type { ReportState, TddAuditSummary } from "../store";

import { Tooltip } from "./Tooltip";

// --- 通过率进度条 ---
function PassRateBar({ total, passed, failed }: { total: number; passed: number; failed: number }) {
  const passRate = total > 0 ? Math.round((passed / total) * 100) : 0;
  const failRate = total > 0 ? Math.round((failed / total) * 100) : 0;

  const barColor = passRate >= 90
    ? "bg-emerald"
    : passRate >= 70
      ? "bg-amber"
      : "bg-rose";

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between text-[10px] font-mono">
        <span className="text-text-muted">通过率</span>
        <span className={`font-bold ${passRate >= 90 ? "text-emerald" : passRate >= 70 ? "text-amber" : "text-rose"}`}>
          {passRate}%
        </span>
      </div>
      <div className="h-2 bg-border rounded-full overflow-hidden flex">
        <div className={`${barColor} transition-all duration-300`} style={{ width: `${passRate}%` }}></div>
        {failRate > 0 && (
          <div className="bg-rose/60 transition-all duration-300" style={{ width: `${failRate}%` }}></div>
        )}
      </div>
    </div>
  );
}

// --- Suite 结果明细 ---
function SuiteDetails({ results }: { results: NonNullable<ReportState["suite_results"]> }) {
  const items = [
    { label: "总计", value: results.total, color: "text-text-bright" },
    { label: "通过", value: results.passed, color: "text-emerald" },
    { label: "失败", value: results.failed, color: results.failed > 0 ? "text-rose" : "text-text-muted" },
    { label: "跳过", value: results.skipped, color: results.skipped > 0 ? "text-amber" : "text-text-muted" },
    { label: "错误", value: results.error, color: results.error > 0 ? "text-rose" : "text-text-muted" },
  ];

  return (
    <div className="grid grid-cols-5 gap-1">
      {items.map(({ label, value, color }) => (
        <div key={label} className="text-center">
          <div className={`text-[14px] font-bold font-mono ${color}`}>{value}</div>
          <div className="text-[8px] font-mono text-text-muted uppercase">{label}</div>
        </div>
      ))}
    </div>
  );
}

// --- TDD 审计摘要 ---
function TddAuditSection({ audit }: { audit: TddAuditSummary }) {
  return (
    <div className="mt-2 pt-2 border-t border-border/50 space-y-1">
      <div className="text-[9px] font-bold font-mono text-text-bright uppercase tracking-wider">
        TDD 审计
      </div>
      <div className="grid grid-cols-4 gap-1 text-center">
        <div>
          <div className="text-[12px] font-bold font-mono text-cyan">{audit.cycle_count}</div>
          <Tooltip text="TDD 红-绿-重构循环总数">
            <div className="text-[8px] font-mono text-text-muted">CYCLE</div>
          </Tooltip>
        </div>
        <div>
          <div className={`text-[12px] font-bold font-mono ${audit.red_violations > 0 ? "text-rose" : "text-emerald"}`}>
            {audit.red_violations}
          </div>
          <Tooltip text="正常值: violations=0, RED 阶段测试必须失败">
            <div className="text-[8px] font-mono text-text-muted">RED违规</div>
          </Tooltip>
        </div>
        <div>
          <div className={`text-[12px] font-bold font-mono ${audit.green_violations > 0 ? "text-rose" : "text-emerald"}`}>
            {audit.green_violations}
          </div>
          <Tooltip text="正常值: violations=0, GREEN 阶段测试必须通过">
            <div className="text-[8px] font-mono text-text-muted">GREEN违规</div>
          </Tooltip>
        </div>
        <div>
          <div className={`text-[12px] font-bold font-mono ${audit.refactor_rollbacks > 0 ? "text-amber" : "text-emerald"}`}>
            {audit.refactor_rollbacks}
          </div>
          <Tooltip text="正常值: rollbacks 应 < cycles/3">
            <div className="text-[8px] font-mono text-text-muted">回滚</div>
          </Tooltip>
        </div>
      </div>
    </div>
  );
}

// --- Anomaly Alerts ---
function AnomalyAlerts({ alerts }: { alerts: string[] }) {
  if (alerts.length === 0) return null;

  return (
    <div className="mt-2 pt-2 border-t border-border/50 space-y-1">
      <div className="flex items-center gap-1">
        <span className="w-1.5 h-1.5 rounded-full bg-rose animate-pulse"></span>
        <span className="text-[9px] font-bold font-mono text-rose uppercase">
          异常告警 ({alerts.length})
        </span>
      </div>
      <div className="space-y-0.5 max-h-[60px] overflow-y-auto">
        {alerts.map((alert, i) => (
          <div key={i} className="text-[9px] font-mono text-rose/80 leading-snug truncate">
            {alert}
          </div>
        ))}
      </div>
    </div>
  );
}

// --- minimal 模式降级态 ---
function MinimalModePlaceholder() {
  return (
    <div className="px-4 py-3 bg-deep border border-border rounded">
      <div className="flex items-center gap-2 mb-2">
        <span className="w-1.5 h-1.5 rounded-full bg-text-muted"></span>
        <span className="font-display text-[10px] font-bold text-text-muted uppercase tracking-wider">
          测试报告
        </span>
      </div>
      <div className="text-[11px] font-mono text-text-muted text-center py-2">
        最小模式 — 无测试报告
      </div>
      <div className="text-[9px] font-mono text-text-muted/60 text-center">
        minimal 模式跳过 Phase 6 测试报告阶段
      </div>
    </div>
  );
}

// --- 主卡片 ---
export const ReportCard = memo(function ReportCard() {
  const mode = useStore((s) => s.mode);
  const reportState = useStore((s) => s.orchestration.reportState);
  const tddAudit = useStore((s) => s.orchestration.tddAudit);

  // minimal 模式: 显示降级态
  if (mode === "minimal") {
    return <MinimalModePlaceholder />;
  }

  // 无报告数据
  if (!reportState) {
    return (
      <div className="px-4 py-3 bg-deep border border-border rounded">
        <div className="flex items-center gap-2">
          <span className="w-1.5 h-1.5 rounded-full bg-text-muted"></span>
          <span className="font-display text-[10px] font-bold text-text-muted uppercase tracking-wider">
            测试报告
          </span>
        </div>
        <div className="text-[10px] font-mono text-text-muted mt-1">
          等待 Phase 6 报告生成...
        </div>
      </div>
    );
  }

  const formatLabel = reportState.report_format === "allure"
    ? "Allure"
    : reportState.report_format === "junit"
      ? "JUnit"
      : reportState.report_format === "custom"
        ? "自定义"
        : reportState.report_format === "none"
          ? "无格式"
          : "未知";

  return (
    <div className="px-4 py-3 bg-deep border border-cyan/30 rounded space-y-2">
      {/* 标题行 */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="w-1.5 h-1.5 rounded-full bg-cyan"></span>
          <span className="font-display text-[10px] font-bold text-text-bright uppercase tracking-wider">
            测试报告
          </span>
        </div>
        <span className="px-1.5 py-0.5 text-[9px] font-mono border border-cyan/30 text-cyan rounded">
          {formatLabel}
        </span>
      </div>

      {/* Suite Results */}
      {reportState.suite_results && (
        <>
          <PassRateBar
            total={reportState.suite_results.total}
            passed={reportState.suite_results.passed}
            failed={reportState.suite_results.failed}
          />
          <SuiteDetails results={reportState.suite_results} />
        </>
      )}

      {/* 报告链接 */}
      <div className="space-y-0.5">
        {reportState.report_url && (
          <div className="flex items-center gap-2 text-[9px] font-mono">
            <span className="text-text-muted">报告:</span>
            <a href={reportState.report_url} target="_blank" rel="noopener noreferrer"
               className="text-cyan hover:underline truncate">
              {reportState.report_url}
            </a>
          </div>
        )}
        {reportState.report_path && !reportState.report_url && (
          <div className="flex items-center gap-2 text-[9px] font-mono">
            <span className="text-text-muted">路径:</span>
            <span className="text-text-bright truncate">{reportState.report_path}</span>
          </div>
        )}
        {reportState.allure_preview_url && (
          <div className="flex items-center gap-2 text-[9px] font-mono">
            <span className="text-text-muted">Allure:</span>
            <a href={reportState.allure_preview_url} target="_blank" rel="noopener noreferrer"
               className="text-cyan hover:underline truncate">
              {reportState.allure_preview_url}
            </a>
          </div>
        )}
        {reportState.allure_results_dir && !reportState.allure_preview_url && (
          <div className="flex items-center gap-2 text-[9px] font-mono">
            <span className="text-text-muted">Allure 数据:</span>
            <span className="text-text-bright truncate">{reportState.allure_results_dir}</span>
          </div>
        )}
      </div>

      {/* TDD 审计 */}
      {tddAudit && <TddAuditSection audit={tddAudit} />}

      {/* Anomaly Alerts */}
      <AnomalyAlerts alerts={reportState.anomaly_alerts} />
    </div>
  );
});
