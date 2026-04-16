import type React from "react";

export function Tooltip({ text, children }: { text: string; children: React.ReactNode }) {
  return (
    <span className="relative group cursor-help">
      {children}
      <span
        className="absolute bottom-full left-1/2 -translate-x-1/2 mb-1 hidden group-hover:block z-50 pointer-events-none px-2 py-1 bg-deep border border-border rounded shadow-lg text-[9px] font-mono text-text-muted max-w-[260px]"
        style={{ whiteSpace: "normal" }}
      >
        {text}
      </span>
    </span>
  );
}
