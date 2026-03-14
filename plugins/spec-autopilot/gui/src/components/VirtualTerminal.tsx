/**
 * VirtualTerminal — V2 极客外壳 + xterm.js 内核
 * 保留 xterm.js 实例的 ANSI 渲染能力，包裹进 V2 的终端 UI 壳
 * 数据源: Zustand Store (events)
 */

import { useEffect, useRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";
import { useStore } from "../store";

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
};

export function VirtualTerminal() {
  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const lastRenderedSequence = useRef<number>(-1);
  const { events } = useStore();

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

  useEffect(() => {
    const term = xtermRef.current;
    if (!term || events.length === 0) return;

    const newEvents = events.filter((e) => e.sequence > lastRenderedSequence.current);
    if (newEvents.length === 0) return;

    for (const event of newEvents) {
      const timestamp = new Date(event.timestamp).toLocaleTimeString();
      const typeUpper = event.type.toUpperCase();

      const color = EVENT_TYPE_COLORS[event.type] || "\x1b[37m";
      const reset = "\x1b[0m";
      const dimGray = "\x1b[90m";

      const line = `${dimGray}[${timestamp}]${reset} ${color}${typeUpper}${reset} ${dimGray}\u2502${reset} Phase ${event.phase} ${dimGray}(${event.phase_label})${reset}\r\n`;
      term.write(line);
    }

    lastRenderedSequence.current = newEvents[newEvents.length - 1]!.sequence;
  }, [events]);

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
          <div className="bg-void px-2 border border-border">过滤器: [全部]</div>
        </div>
      </div>

      {/* xterm.js Terminal Body */}
      <div ref={terminalRef} className="terminal-body flex-1 p-1" />
    </section>
  );
}
