/** Native macOS view, independent of the framework hosting the client. */
export type NotchStyle = "contour" | "capsule" | "glass";
export type NotchMotion = "spring" | "gentle" | "snappy";
export type NotchActivity = "idle" | "working" | "listening" | "success";
export interface NotchAction { id: string; label: string }
export interface NotchState {
  style: NotchStyle;
  motion: NotchMotion;
  expanded: boolean;
  title: string;
  subtitle: string;
  activity: NotchActivity;
  progress: number | null;
  actions: NotchAction[];
}
/** Omitted values keep their current value. Explicit `progress: null` clears it. */
export type NotchPatch = Partial<NotchState>;
export interface NotchSnapshot { state: NotchState; visible: boolean }
export type NotchCommand = "show" | "update" | "hide" | "quit";
export interface NotchResult extends NotchSnapshot { event: "result"; id: string; ok: true }
export type NotchEvent =
  | { event: "ready"; protocolVersion: 1 }
  | NotchResult
  | { event: "error"; id?: string; code: string; message: string }
  | { event: "action"; actionId: string }
  | ({ event: "state" } & NotchSnapshot);
export type Unsubscribe = () => void;
export interface TransportExit { code: number | null; signal?: number | string | null }

/**
 * Use raw stdout chunks, including line separators. A Node child_process, Rust
 * bridge, Electron utility process, or Tauri sidecar can implement this contract.
 * Install listeners before starting the child so its initial ready event is kept.
 */
export interface NotchTransport {
  write(chunk: string): Promise<void>;
  onData(listener: (chunk: string) => void): Unsubscribe;
  onError(listener: (error: Error) => void): Unsubscribe;
  onClose(listener: (exit: TransportExit) => void): Unsubscribe;
  close(): Promise<void>;
}

export class NotchError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message);
    this.name = "NotchError";
  }
}

const maximumLineBytes = 65_536;
const encoder = new TextEncoder();
interface Pending {
  resolve: (result: NotchResult) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

/** Correlated requests, readiness, bounded framing, and native UI events. */
export class NotchClient {
  readonly ready: Promise<void>;
  private readyResolve!: () => void;
  private readyReject!: (error: Error) => void;
  private readyTimer: ReturnType<typeof setTimeout>;
  private buffer = "";
  private sequence = 0;
  private ended: Error | undefined;
  private pending = new Map<string, Pending>();
  private listeners = new Set<(event: NotchEvent) => void>();
  private unsubscribes: Unsubscribe[];
  private readonly timeoutMs: number;

  constructor(private readonly transport: NotchTransport, options: { timeoutMs?: number } = {}) {
    this.timeoutMs = options.timeoutMs ?? 5_000;
    if (!Number.isFinite(this.timeoutMs) || this.timeoutMs <= 0) {
      throw new RangeError("timeoutMs must be a positive finite number");
    }
    this.ready = new Promise((resolve, reject) => {
      this.readyResolve = resolve;
      this.readyReject = reject;
    });
    // A client can be disposed before its owner awaits ready.
    void this.ready.catch(() => {});
    this.readyTimer = setTimeout(() => this.fail(new NotchError("ready_timeout", "Native notch host did not become ready")), this.timeoutMs);
    this.unsubscribes = [
      transport.onData(chunk => this.receive(chunk)),
      transport.onError(error => this.fail(error)),
      transport.onClose(exit => this.fail(new NotchError("host_closed", `Native notch host exited (${exit.code ?? exit.signal ?? "unknown"})`))),
    ];
  }

  onEvent(listener: (event: NotchEvent) => void): Unsubscribe {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  onAction(listener: (actionId: string) => void): Unsubscribe {
    return this.onEvent(event => { if (event.event === "action") listener(event.actionId); });
  }

  onState(listener: (snapshot: NotchSnapshot) => void): Unsubscribe {
    return this.onEvent(event => { if (event.event === "state" || event.event === "result") listener(event); });
  }

  show(state: NotchPatch = {}): Promise<NotchResult> { return this.request("show", state); }
  update(state: NotchPatch): Promise<NotchResult> { return this.request("update", state); }
  hide(): Promise<NotchResult> { return this.request("hide"); }
  quit(): Promise<NotchResult> { return this.request("quit"); }

  /** Force close the transport and reject every outstanding request. */
  async dispose(): Promise<void> {
    this.fail(new NotchError("disposed", "Notch client was disposed"));
    await this.transport.close();
  }

  private async request(command: NotchCommand, state?: NotchPatch): Promise<NotchResult> {
    await this.ready;
    if (this.ended) throw this.ended;
    const id = `bn-${++this.sequence}`;
    const line = JSON.stringify(state === undefined ? { id, command } : { id, command, state });
    if (encoder.encode(line).byteLength > maximumLineBytes) {
      throw new NotchError("line_too_large", "Request exceeds the native host's 64 KiB line limit");
    }
    return new Promise<NotchResult>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new NotchError("request_timeout", `Native notch host timed out for ${command}`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.transport.write(line + "\n").catch(error => {
        const request = this.pending.get(id);
        if (!request) return;
        clearTimeout(request.timer);
        this.pending.delete(id);
        reject(error instanceof Error ? error : new Error(String(error)));
      });
    });
  }

  private receive(chunk: string): void {
    if (this.ended) return;
    this.buffer += chunk;
    let end: number;
    while ((end = this.buffer.indexOf("\n")) !== -1) {
      const line = this.buffer.slice(0, end).replace(/\r$/, "");
      this.buffer = this.buffer.slice(end + 1);
      if (!line) continue;
      if (encoder.encode(line).byteLength > maximumLineBytes) {
        this.fail(new NotchError("line_too_large", "Native host emitted an oversized JSON line"));
        return;
      }
      let event: NotchEvent;
      try {
        event = parseEvent(JSON.parse(line));
      } catch (error) {
        this.fail(new NotchError("invalid_message", error instanceof Error ? error.message : String(error)));
        return;
      }
      this.handle(event);
    }
    if (encoder.encode(this.buffer).byteLength > maximumLineBytes) {
      this.fail(new NotchError("line_too_large", "Native host emitted an oversized JSON line"));
    }
  }

  private handle(event: NotchEvent): void {
    if (event.event === "ready") {
      clearTimeout(this.readyTimer);
      this.readyResolve();
    } else if (event.event === "result" || event.event === "error") {
      const request = event.id ? this.pending.get(event.id) : undefined;
      if (request && event.id) {
        clearTimeout(request.timer);
        this.pending.delete(event.id);
        if (event.event === "result") request.resolve(event);
        else request.reject(new NotchError(event.code, event.message));
      }
    }
    for (const listener of this.listeners) listener(event);
  }

  private fail(error: Error): void {
    if (this.ended) return;
    this.ended = error;
    clearTimeout(this.readyTimer);
    this.readyReject(error);
    for (const request of this.pending.values()) {
      clearTimeout(request.timer);
      request.reject(error);
    }
    this.pending.clear();
    for (const unsubscribe of this.unsubscribes ?? []) unsubscribe();
    this.listeners.clear();
  }
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validState(value: unknown): value is NotchState {
  return record(value)
    && ["contour", "capsule", "glass"].includes(String(value.style))
    && ["spring", "gentle", "snappy"].includes(String(value.motion))
    && typeof value.expanded === "boolean"
    && typeof value.title === "string" && typeof value.subtitle === "string"
    && ["idle", "working", "listening", "success"].includes(String(value.activity))
    && (value.progress === null || (typeof value.progress === "number" && Number.isFinite(value.progress) && value.progress >= 0 && value.progress <= 1))
    && Array.isArray(value.actions)
    && value.actions.every(action => record(action) && typeof action.id === "string" && typeof action.label === "string");
}

function parseEvent(value: unknown): NotchEvent {
  if (record(value)) {
    switch (value.event) {
      case "ready":
        if (value.protocolVersion === 1) return value as unknown as NotchEvent;
        throw new Error(`Unsupported notch protocol version ${String(value.protocolVersion)}`);
      case "result":
        if (typeof value.id === "string" && value.ok === true && validState(value.state) && typeof value.visible === "boolean") return value as unknown as NotchResult;
        break;
      case "state":
        if (validState(value.state) && typeof value.visible === "boolean") return value as unknown as NotchEvent;
        break;
      case "action":
        if (typeof value.actionId === "string") return value as unknown as NotchEvent;
        break;
      case "error":
        if ((value.id === undefined || typeof value.id === "string") && typeof value.code === "string" && typeof value.message === "string") return value as unknown as NotchEvent;
        break;
    }
  }
  throw new Error("Malformed native notch event");
}
