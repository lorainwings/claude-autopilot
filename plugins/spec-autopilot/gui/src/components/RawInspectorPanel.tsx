import { memo, useEffect, useRef, useState } from "react";

type RawKind = "hooks" | "statusline";

interface RawTailResponse {
  lines: string[];
  cursor: number;
  fileSize: number;
}

/** Derive HTTP API base from current page origin (consistent with WSBridge's localhost default) */
function getApiBase(): string {
  const { protocol, hostname } = window.location;
  return `${protocol}//${hostname}:9527`;
}

export const RawInspectorPanel = memo(function RawInspectorPanel() {
  const [kind, setKind] = useState<RawKind>("hooks");
  const [lines, setLines] = useState<string[]>([]);
  const cursorRef = useRef(0);

  // kind 切换时重置游标和行
  useEffect(() => {
    cursorRef.current = 0;
    setLines([]);
  }, [kind]);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        const res = await fetch(
          `${getApiBase()}/api/raw-tail?kind=${kind}&cursor=${cursorRef.current}`
        );
        if (!res.ok) return;
        const data = (await res.json()) as RawTailResponse;
        if (!cancelled && data.lines.length > 0) {
          setLines((prev) => [...prev, ...data.lines].slice(-500));
          cursorRef.current = data.cursor;
        }
      } catch {
        // 网络错误静默忽略，下次轮询重试
      }
    };

    load();
    const timer = setInterval(load, 2000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [kind]);

  return (
    <div className="h-full flex flex-col bg-void">
      <div className="px-4 py-3 border-b border-border flex items-center justify-between">
        <div className="flex gap-2">
          {(["hooks", "statusline"] as RawKind[]).map((item) => (
            <button
              key={item}
              onClick={() => setKind(item)}
              className={`px-2 py-1 text-[10px] font-mono border rounded ${
                kind === item ? "border-cyan/50 bg-cyan/10 text-cyan" : "border-border text-text-muted"
              }`}
            >
              {item}
            </button>
          ))}
        </div>
        <div className="text-[10px] font-mono text-text-muted truncate ml-4">
          {lines.length > 0 ? `${lines.length} 行 (游标增量)` : "暂无数据"}
        </div>
      </div>
      <div className="flex-1 overflow-y-auto p-4">
        {lines.length === 0 ? (
          <div className="h-full flex items-center justify-center text-text-muted text-sm font-mono">
            暂无原始 {kind} 数据
          </div>
        ) : (
          <pre className="whitespace-pre-wrap break-all text-[11px] leading-5 font-mono text-text-bright">
            {lines.join("\n")}
          </pre>
        )}
      </div>
    </div>
  );
});
