/**
 * RequirementPacketPanel -- Phase 1 需求包详情展示
 */

import { memo } from "react";
import { useStore } from "../store";
import type { RequirementPacket } from "../store";

const TYPE_COLORS: Record<string, string> = {
  feature: "text-cyan",
  bugfix: "text-rose",
  refactor: "text-amber",
  chore: "text-text-muted",
};

function SectionHeader({ title, dotColor }: { title: string; dotColor?: string }) {
  return (
    <div className="flex items-center gap-2 mb-1">
      <span className={`w-1.5 h-1.5 rounded-full ${dotColor || "bg-cyan"}`}></span>
      <span className="font-display text-[10px] font-bold text-text-bright uppercase tracking-wider">
        {title}
      </span>
    </div>
  );
}

function InfoRow({ label, value, valueColor }: { label: string; value: string; valueColor?: string }) {
  return (
    <div className="flex justify-between items-center gap-2 text-[11px] font-mono">
      <span className="text-text-muted shrink-0">{label}</span>
      <span className={`truncate ${valueColor || "text-text-bright"}`}>{value}</span>
    </div>
  );
}

function ListItems({ items, color }: { items: string[]; color: string }) {
  if (items.length === 0) return <div className="text-[10px] font-mono text-text-muted">--</div>;
  return (
    <ul className="space-y-0.5">
      {items.map((item, i) => (
        <li key={i} className={`text-[10px] font-mono ${color} leading-snug`}>
          {item}
        </li>
      ))}
    </ul>
  );
}

function PacketContent({ packet }: { packet: RequirementPacket }) {
  const typeColor = TYPE_COLORS[packet.requirement_type] ?? "text-text-bright";
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <span className={`px-1.5 py-0.5 text-[9px] font-mono font-bold border rounded ${typeColor}`} style={{ borderColor: "currentColor" }}>
          {packet.requirement_type.toUpperCase()}
        </span>
      </div>
      <div className="space-y-0.5">
        <div className="text-[9px] font-mono text-text-muted uppercase">Goal</div>
        <div className="text-[11px] font-mono text-cyan leading-snug">{packet.goal}</div>
      </div>
      <div className="space-y-0.5">
        <div className="text-[9px] font-mono text-text-muted uppercase">Scope</div>
        <ListItems items={packet.scope} color="text-emerald" />
      </div>
      {packet.non_goals.length > 0 && (
        <div className="space-y-0.5">
          <div className="text-[9px] font-mono text-text-muted uppercase">Non-Goals</div>
          <ListItems items={packet.non_goals} color="text-rose" />
        </div>
      )}
      {packet.constraints.length > 0 && (
        <div className="space-y-0.5">
          <div className="text-[9px] font-mono text-text-muted uppercase">Constraints</div>
          <ListItems items={packet.constraints} color="text-amber" />
        </div>
      )}
    </div>
  );
}

export const RequirementPacketPanel = memo(function RequirementPacketPanel() {
  const requirementPacket = useStore((s) => s.orchestration.requirementPacket);
  const requirementPacketHash = useStore((s) => s.orchestration.requirementPacketHash);

  if (!requirementPacket && !requirementPacketHash) {
    return (
      <div className="px-3 py-2">
        <SectionHeader title="需求包" dotColor="bg-cyan" />
        <div className="text-[10px] font-mono text-text-muted">
          等待 Phase 1...
        </div>
      </div>
    );
  }

  if (!requirementPacket) {
    return (
      <div className="px-3 py-2">
        <SectionHeader title="需求包" dotColor="bg-cyan" />
        <InfoRow label="Hash" value={requirementPacketHash || "--"} valueColor="text-text-muted" />
        <div className="text-[10px] font-mono text-text-muted mt-1">
          等待 Phase 1 完成...
        </div>
      </div>
    );
  }

  return (
    <div className="px-3 py-2">
      <SectionHeader title="需求包" dotColor="bg-cyan" />
      <PacketContent packet={requirementPacket} />
    </div>
  );
});
