/**
 * VirtualTerminal — xterm.js 终端渲染器
 * 显示事件流的文本日志（未来可接入 CLI 输出流）
 */

import { useEffect, useRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";
import { useStore } from "../store";

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
      const line = `[${timestamp}] ${event.type.toUpperCase()} | Phase ${event.phase} (${event.phase_label})\r\n`;
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
