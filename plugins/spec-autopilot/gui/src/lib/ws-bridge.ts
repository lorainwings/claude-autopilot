/**
 * WSBridge — WebSocket 通信桥接层
 * 连接 autopilot-server.ts 的 WS 端口，管理重连与事件分发
 */

export interface AutopilotEvent {
  type: string;
  phase: number;
  mode: "full" | "lite" | "minimal";
  timestamp: string;
  change_name: string;
  session_id: string;
  phase_label: string;
  total_phases: number;
  sequence: number;
  payload: Record<string, unknown>;
}

type EventHandler = (events: AutopilotEvent[]) => void;
type AckHandler = (data: { action: string; phase: number; timestamp: string }) => void;

export class WSBridge {
  private ws: WebSocket | null = null;
  private url: string;
  private handlers = new Set<EventHandler>();
  private ackHandlers = new Set<AckHandler>();
  private resetHandlers = new Set<() => void>();
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectDelay = 1000;
  private maxReconnectDelay = 10000;
  private connectTimeout: ReturnType<typeof setTimeout> | null = null;

  constructor(url = "ws://localhost:8765") {
    this.url = url;
  }

  connect() {
    if (this.ws?.readyState === WebSocket.OPEN) return;

    try {
      this.ws = new WebSocket(this.url);

      // 5s connection timeout: if still CONNECTING, force close → triggers onclose → reconnect
      this.connectTimeout = setTimeout(() => {
        if (this.ws?.readyState === WebSocket.CONNECTING) {
          this.ws.close();
        }
      }, 5000);

      this.ws.onopen = () => {
        this.clearConnectTimeout();
        this.reconnectDelay = 1000;
      };

      this.ws.onmessage = (e) => {
        try {
          const msg = JSON.parse(e.data);
          if (msg.type === "snapshot") {
            this.emit(msg.data as AutopilotEvent[]);
          } else if (msg.type === "event") {
            this.emit([msg.data as AutopilotEvent]);
          } else if (msg.type === "decision_ack") {
            // v5.2: Decision ACK — notify listeners for UI dismissal
            for (const handler of this.ackHandlers) {
              handler(msg.data);
            }
          } else if (msg.type === "reset") {
            for (const handler of this.resetHandlers) {
              handler();
            }
          }
        } catch {
          // Ignore malformed messages
        }
      };

      this.ws.onclose = () => {
        this.scheduleReconnect();
      };

      this.ws.onerror = () => {
        this.clearConnectTimeout();
        this.ws?.close();
      };
    } catch {
      this.scheduleReconnect();
    }
  }

  disconnect() {
    this.clearConnectTimeout();
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.ws?.close();
    this.ws = null;
  }

  onEvents(handler: EventHandler) {
    this.handlers.add(handler);
    return () => this.handlers.delete(handler);
  }

  onDecisionAck(handler: AckHandler) {
    this.ackHandlers.add(handler);
    return () => this.ackHandlers.delete(handler);
  }

  onReset(handler: () => void) {
    this.resetHandlers.add(handler);
    return () => this.resetHandlers.delete(handler);
  }

  get connected() {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  sendDecision(decision: { action: "retry" | "fix" | "override"; phase: number; reason?: string }) {
    if (!this.connected) {
      throw new Error("WebSocket not connected");
    }
    this.ws?.send(JSON.stringify({ type: "decision", data: decision }));
  }

  private emit(events: AutopilotEvent[]) {
    for (const handler of this.handlers) {
      handler(events);
    }
  }

  private clearConnectTimeout() {
    if (this.connectTimeout) {
      clearTimeout(this.connectTimeout);
      this.connectTimeout = null;
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.reconnectDelay = Math.min(this.reconnectDelay * 1.5, this.maxReconnectDelay);
      this.connect();
    }, this.reconnectDelay);
  }
}
