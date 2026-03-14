/**
 * VirtualTerminal — xterm.js 终端渲染器
 * 显示事件流的文本日志（未来可接入 CLI 输出流）
 */

import { useEffect, useRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";
import { useStore } from "../store";

// v5.2: ANSI color codes for event type labels in terminal
const EVENT_TYPE_COLORS: Record<string, string> = {
  phase_start: "\x1b[34m",     // blue
  phase_end: "\x1b[32m",       // green
  gate_pass: "\x1b[32m",       // green
  gate_block: "\x1b[31m",      // red (bold)
  error: "\x1b[1;31m",         // bright red
  task_progress: "\x1b[36m",   // cyan
  gate_decision_pending: "\x1b[33m",  // yellow
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
      fontFamily: "Menlo, Monaco, 'Courier New', monospace",
      theme: {
        background: "#1e1e1e",
        foreground: "#d4d4d4",
        cursor: "#d4d4d4",
        black: "#000000",
        red: "#cd3131",
        green: "#0dbc79",
        yellow: "#e5e510",
        blue: "#2472c8",
        magenta: "#bc3fbc",
        cyan: "#11a8cd",
        white: "#e5e5e5",
        brightBlack: "#666666",
        brightRed: "#f14c4c",
        brightGreen: "#23d18b",
        brightYellow: "#f5f543",
        brightBlue: "#3b8eea",
        brightMagenta: "#d670d6",
        brightCyan: "#29b8db",
        brightWhite: "#e5e5e5",
      },
      allowTransparency: false,
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

    // Render all events with sequence > lastRenderedSequence (incremental)
    const newEvents = events.filter((e) => e.sequence > lastRenderedSequence.current);
    if (newEvents.length === 0) return;

    for (const event of newEvents) {
      const timestamp = new Date(event.timestamp).toLocaleTimeString();
      const typeUpper = event.type.toUpperCase();

      // v5.2: ANSI color codes per event type
      const color = EVENT_TYPE_COLORS[event.type] || "\x1b[37m"; // default white
      const reset = "\x1b[0m";
      const dimGray = "\x1b[90m";

      const line = `${dimGray}[${timestamp}]${reset} ${color}${typeUpper}${reset} ${dimGray}|${reset} Phase ${event.phase} ${dimGray}(${event.phase_label})${reset}\r\n`;
      term.write(line);
    }

    lastRenderedSequence.current = newEvents[newEvents.length - 1].sequence;
  }, [events]);

  return (
    <div className="virtual-terminal flex flex-col h-full bg-gray-950 rounded-lg border border-gray-700 overflow-hidden">
      <div className="terminal-header px-4 py-2 bg-gray-900 border-b border-gray-700 text-sm font-medium text-gray-300">
        Event Log
      </div>
      <div ref={terminalRef} className="terminal-body flex-1" />
    </div>
  );
}
