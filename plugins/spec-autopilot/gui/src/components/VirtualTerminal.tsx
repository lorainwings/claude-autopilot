/**
 * VirtualTerminal — V2 极客外壳 + xterm.js 内核
 * 保留 xterm.js 实例的 ANSI 渲染能力，包裹进 V2 的终端 UI 壳
 * 数据源: Zustand Store (events)
 */

import { useEffect, useRef, useState, useCallback, memo } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";
import { useStore, selectAgentIds } from "../store";
import type { AutopilotEvent } from "../lib/ws-bridge";

// ANSI color codes for event type labels
const EVENT_TYPE_COLORS: Record<string, string> = {
  phase_start: "\x1b[34m",          // blue
  phase_end: "\x1b[32m",            // green
  gate_pass: "\x1b[32m",            // green
  gate_block: "\x1b[1;31m",         // bright red
  error: "\x1b[1;31m",              // bright red
  task_progress: "\x1b[36m",        // cyan
  gate_decision_pending: "\x1b[33m", // yellow
  gate_decision_received: "\x1b[35m", // magenta
  agent_dispatch: "\x1b[35m",       // magenta
  agent_complete: "\x1b[32m",       // green
  tool_use: "\x1b[2;36m",           // dim cyan
};

// Filter categories
type FilterType = "all" | "lifecycle" | "gate" | "agent" | "tool" | "task" | "error" | "agent_by_id";

const FILTER_OPTIONS: { value: FilterType; label: string }[] = [
  { value: "all", label: "全部" },
  { value: "lifecycle", label: "阶段生命周期" },
  { value: "gate", label: "门禁" },
  { value: "agent", label: "Agent" },
  { value: "agent_by_id", label: "指定 Agent" },
  { value: "tool", label: "工具调用" },
  { value: "task", label: "任务进度" },
  { value: "error", label: "错误" },
];

const FILTER_MATCH: Record<FilterType, Set<string> | null> = {
  all: null,
  lifecycle: new Set(["phase_start", "phase_end"]),
  gate: new Set(["gate_pass", "gate_block", "gate_decision_pending", "gate_decision_received"]),
  agent: new Set(["agent_dispatch", "agent_complete"]),
  agent_by_id: new Set(["tool_use", "agent_dispatch", "agent_complete"]),
  tool: new Set(["tool_use"]),
  task: new Set(["task_progress"]),
  error: new Set(["error"]),
};

function matchesFilter(eventType: string, filter: FilterType, selectedAgentId?: string, event?: AutopilotEvent): boolean {
  if (filter === "agent_by_id" && selectedAgentId) {
    const allowed = FILTER_MATCH[filter];
    if (allowed && !allowed.has(eventType)) return false;
    const agentId = event?.payload ? (event.payload as Record<string, unknown>).agent_id : undefined;
    return agentId === selectedAgentId;
  }
  const allowed = FILTER_MATCH[filter];
  return allowed === null || allowed.has(eventType);
}

function formatEventLine(event: AutopilotEvent, allEvents: AutopilotEvent[]): string {
  const timestamp = new Date(event.timestamp).toLocaleTimeString();
  const typeUpper = event.type.toUpperCase();
  const color = EVENT_TYPE_COLORS[event.type] || "\x1b[37m";
  const reset = "\x1b[0m";
  const dimGray = "\x1b[90m";

  let detail = "";
  const p = event.payload;
  switch (event.type) {
    case "gate_block":
      detail = ` ${dimGray}score=${reset}${String(p.gate_score ?? "--")}/8`;
      if (typeof p.error_message === "string") detail += ` ${dimGray}err=${reset}${p.error_message.slice(0, 80)}`;
      break;
    case "gate_pass":
      detail = ` ${dimGray}score=${reset}${String(p.gate_score ?? "--")}/8`;
      break;
    case "phase_end": {
      let dur = p.duration_ms;
      if (dur == null || dur === 0) {
        const phaseStart = allEvents.findLast(
          (ev) => ev.type === "phase_start" && ev.phase === event.phase
        );
        if (phaseStart) {
          dur = new Date(event.timestamp).getTime() - new Date(phaseStart.timestamp).getTime();
        }
      }
      detail = ` ${dimGray}status=${reset}${String(p.status ?? "--")} ${dimGray}duration=${reset}${String(dur ?? "--")}ms`;
      break;
    }
    case "task_progress":
      detail = ` ${dimGray}task=${reset}${String(p.task_name ?? "--")} ${dimGray}status=${reset}${String(p.status ?? "--")}`;
      if (p.tdd_step) detail += ` ${dimGray}tdd=${reset}${String(p.tdd_step)}`;
      break;
    case "error":
      if (typeof p.error_message === "string") detail = ` ${p.error_message.slice(0, 120)}`;
      break;
    case "tool_use": {
      detail = ` ${dimGray}tool=${reset}${String(p.tool_name ?? "--")}`;
      if (typeof p.key_param === "string") {
        const labelMap: Record<string, string> = { Bash: "cmd", Glob: "pattern", Grep: "pattern", Agent: "desc" };
        const lbl = labelMap[p.tool_name as string] ?? "file";
        detail += ` ${dimGray}${lbl}="${p.key_param}"${reset}`;
      }
      if (p.exit_code != null) detail += ` ${dimGray}exit=${reset}${String(p.exit_code)}`;
      break;
    }
    case "agent_dispatch":
      detail = ` ${dimGray}id=${reset}${String(p.agent_id ?? "--")} ${dimGray}label=${reset}${String(p.agent_label ?? "--")}`;
      if (p.background) detail += ` ${dimGray}[background]${reset}`;
      break;
    case "agent_complete":
      detail = ` ${dimGray}id=${reset}${String(p.agent_id ?? "--")} ${dimGray}status=${reset}${String(p.status ?? "--")}`;
      if (p.duration_ms != null) detail += ` ${dimGray}duration=${reset}${String(p.duration_ms)}ms`;
      if (typeof p.summary === "string") detail += ` ${dimGray}${p.summary.slice(0, 80)}${reset}`;
      break;
  }

  return `${dimGray}[${timestamp}]${reset} ${color}${typeUpper}${reset} ${dimGray}\u2502${reset} Phase ${event.phase} ${dimGray}(${event.phase_label})${reset}${detail}\r\n`;
}

export const VirtualTerminal = memo(function VirtualTerminal() {
  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const lastRenderedSequence = useRef<number>(-1);
  const writeBufferRef = useRef<string[]>([]);
  const rafIdRef = useRef<number | null>(null);
  const filterRef = useRef<FilterType>("all");
  const dropdownRef = useRef<HTMLDivElement>(null);
  const [filterType, setFilterType] = useState<FilterType>("all");
  const [dropdownOpen, setDropdownOpen] = useState(false);
  const [agentSubMenuOpen, setAgentSubMenuOpen] = useState(false);
  const [selectedAgentId, setSelectedAgentId] = useState<string | null>(null);
  const selectedAgentRef = useRef<string | null>(null);
  const events = useStore((s) => s.events);
  const agentMap = useStore((s) => s.agentMap);

  // Close dropdown on click outside
  useEffect(() => {
    if (!dropdownOpen) return;
    const handleClickOutside = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [dropdownOpen]);

  useEffect(() => {
    if (!terminalRef.current) return;

    const term = new Terminal({
      cursorBlink: false,
      fontSize: 13,
      fontFamily: "'JetBrains Mono', Menlo, Monaco, 'Courier New', monospace",
      theme: {
        background: "#06080c",    // --color-void
        foreground: "#c9d1d9",    // --color-text-bright
        cursor: "#00d9ff",        // --color-cyan
        black: "#0a0e14",
        red: "#f43f5e",
        green: "#10b981",
        yellow: "#fbbf24",
        blue: "#3b82f6",
        magenta: "#8b5cf6",
        cyan: "#00d9ff",
        white: "#c9d1d9",
        brightBlack: "#8b949e",
        brightRed: "#f43f5e",
        brightGreen: "#10b981",
        brightYellow: "#fbbf24",
        brightBlue: "#3b82f6",
        brightMagenta: "#8b5cf6",
        brightCyan: "#00d9ff",
        brightWhite: "#e6edf3",
        selectionBackground: "rgba(0, 217, 255, 0.3)",
      },
      allowTransparency: true,
      convertEol: true,
    });

    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    term.open(terminalRef.current);
    fitAddon.fit();

    xtermRef.current = term;
    fitAddonRef.current = fitAddon;

    const handleResize = () => {
      requestAnimationFrame(() => {
        fitAddon.fit();
      });
    };

    window.addEventListener("resize", handleResize);

    return () => {
      window.removeEventListener("resize", handleResize);
      term.dispose();
    };
  }, []);

  // Flush buffered lines in a single rAF batch
  const flushBuffer = useRef(() => {
    const term = xtermRef.current;
    if (!term || writeBufferRef.current.length === 0) {
      rafIdRef.current = null;
      return;
    }
    const batch = writeBufferRef.current.join("");
    writeBufferRef.current = [];
    term.write(batch);
    rafIdRef.current = null;
  }).current;

  // Replay all events matching filter into terminal
  const replayFiltered = useCallback((filter: FilterType, agentId?: string | null) => {
    const term = xtermRef.current;
    if (!term) return;
    term.clear();
    writeBufferRef.current = [];
    const filtered = events.filter((e) => matchesFilter(e.type, filter, agentId || undefined, e));
    for (const event of filtered) {
      writeBufferRef.current.push(formatEventLine(event, events));
    }
    lastRenderedSequence.current = events.length > 0 ? events[events.length - 1]!.sequence : -1;
    if (rafIdRef.current === null) {
      rafIdRef.current = requestAnimationFrame(flushBuffer);
    }
  }, [events, flushBuffer]);

  // Handle filter change: clear terminal and replay matching events
  const handleFilterChange = useCallback((newFilter: FilterType) => {
    filterRef.current = newFilter;
    setFilterType(newFilter);
    setDropdownOpen(false);
    setAgentSubMenuOpen(false);
    if (newFilter !== "agent_by_id") {
      setSelectedAgentId(null);
      selectedAgentRef.current = null;
    }
    replayFiltered(newFilter, selectedAgentRef.current);
  }, [replayFiltered]);

  // Handle agent sub-filter selection
  const handleAgentSelect = useCallback((agentId: string) => {
    setSelectedAgentId(agentId);
    selectedAgentRef.current = agentId;
    filterRef.current = "agent_by_id";
    setFilterType("agent_by_id");
    setDropdownOpen(false);
    replayFiltered("agent_by_id", agentId);
  }, [replayFiltered]);

  useEffect(() => {
    const term = xtermRef.current;
    if (!term || events.length === 0) return;

    const newEvents = events.filter((e) => e.sequence > lastRenderedSequence.current);
    if (newEvents.length === 0) return;

    const currentFilter = filterRef.current;
    for (const event of newEvents) {
      if (!matchesFilter(event.type, currentFilter, selectedAgentRef.current || undefined, event)) continue;
      writeBufferRef.current.push(formatEventLine(event, events));
    }

    lastRenderedSequence.current = newEvents[newEvents.length - 1]!.sequence;

    // Schedule a single rAF flush if not already pending
    if (rafIdRef.current === null) {
      rafIdRef.current = requestAnimationFrame(flushBuffer);
    }
  }, [events, flushBuffer]);

  // Cleanup pending rAF on unmount
  useEffect(() => {
    return () => {
      if (rafIdRef.current !== null) {
        cancelAnimationFrame(rafIdRef.current);
      }
    };
  }, []);

  const currentLabel = filterType === "agent_by_id" && selectedAgentId
    ? `Agent: ${agentMap.get(selectedAgentId)?.agent_label || selectedAgentId}`
    : FILTER_OPTIONS.find((o) => o.value === filterType)?.label ?? "全部";

  const agentOptions = selectAgentIds(agentMap);

  return (
    <section className="h-full flex flex-col bg-void overflow-hidden">
      {/* V2 Terminal Header Bar */}
      <div className="h-8 bg-surface border-b border-border flex items-center justify-between px-4 shrink-0">
        <div className="flex items-center space-x-2">
          <span className="w-2 h-2 rounded-full bg-rose animate-pulse"></span>
          <span className="font-mono text-[10px] text-text-bright tracking-wider">事件流.log</span>
        </div>
        <div className="flex items-center space-x-4 text-[10px] font-mono text-text-muted">
          <div>事件数: {events.length}</div>
          <div className="relative" ref={dropdownRef}>
            <button
              onClick={() => setDropdownOpen((o) => !o)}
              className="bg-void px-2 py-0.5 border border-border hover:border-cyan/50 transition-colors cursor-pointer"
            >
              过滤器: [{currentLabel}]
            </button>
            {dropdownOpen && (
              <div className="absolute right-0 top-full mt-1 bg-surface border border-border z-50 min-w-[140px] shadow-lg">
                {FILTER_OPTIONS.map((opt) => (
                  <div key={opt.value} className="relative">
                    <button
                      onClick={() => {
                        if (opt.value === "agent_by_id" && agentOptions.length > 0) {
                          setAgentSubMenuOpen((prev) => !prev);
                        } else {
                          handleFilterChange(opt.value);
                        }
                      }}
                      className={`block w-full text-left px-3 py-1.5 text-[10px] font-mono hover:bg-elevated transition-colors ${
                        filterType === opt.value ? "text-cyan" : "text-text-muted"
                      }`}
                    >
                      {filterType === opt.value ? "> " : "  "}{opt.label}
                      {opt.value === "agent_by_id" && agentOptions.length > 0 && " >"}
                    </button>
                    {/* Agent sub-filter dropdown (click-driven) */}
                    {opt.value === "agent_by_id" && agentSubMenuOpen && agentOptions.length > 0 && (
                      <div className="absolute right-full top-0 bg-surface border border-border z-50 min-w-[160px] shadow-lg">
                        {agentOptions.map((a) => (
                          <button
                            key={a.id}
                            onClick={() => handleAgentSelect(a.id)}
                            className={`block w-full text-left px-3 py-1.5 text-[10px] font-mono hover:bg-elevated transition-colors ${
                              selectedAgentId === a.id ? "text-cyan" : "text-text-muted"
                            }`}
                          >
                            {selectedAgentId === a.id ? "> " : "  "}{a.label}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* xterm.js Terminal Body */}
      <div ref={terminalRef} className="terminal-body flex-1 p-1" />
    </section>
  );
});
