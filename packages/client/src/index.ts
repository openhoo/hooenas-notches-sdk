/** Native macOS view, independent of the framework hosting the client. */
export type NotchStyle = "contour" | "capsule" | "glass";
export type NotchMotion = "spring" | "gentle" | "snappy";
export type NotchActivity = "idle" | "working" | "listening" | "success";
export interface NotchAction {
  id: string;
  label: string;
}
/** Requested expanded width and height in macOS points. */
export interface NotchSize {
  width: number;
  height: number;
}
export const notchSizeBounds = Object.freeze({
  minWidth: 280,
  maxWidth: 1_600,
  minHeight: 140,
  maxHeight: 1_000,
});
export interface NotchState {
  style: NotchStyle;
  motion: NotchMotion;
  expanded: boolean;
  title: string;
  subtitle: string;
  activity: NotchActivity;
  progress: number | null;
  actions: NotchAction[];
  /** Null uses the default size. Absent on older protocol v1 hosts. */
  expandedSize?: NotchSize | null;
}
/** Omitted values stay unchanged. Explicit null resets `progress` or `expandedSize`. */
export type NotchPatch = Partial<NotchState>;
export interface NotchSnapshot {
  state: NotchState;
  visible: boolean;
}
export type NotchCommand = "show" | "update" | "hide" | "quit";
export interface NotchResult extends NotchSnapshot {
  event: "result";
  id: string;
  ok: true;
}
export type NotchEvent =
  | { event: "ready"; protocolVersion: 1; capabilities?: string[] }
  | NotchResult
  | { event: "error"; id?: string; code: string; message: string }
  | { event: "action"; actionId: string }
  | ({ event: "state" } & NotchSnapshot);
export type Unsubscribe = () => void;
export interface TransportExit {
  code: number | null;
  signal?: number | string | null;
}
export interface NotchClientOptions {
  /** Deadline for readiness and each request, including time waiting to write. */
  timeoutMs?: number;
  /** Receives synchronous and asynchronous consumer callback failures. */
  onListenerError?: (error: Error) => unknown;
}

/**
 * Use raw, incrementally decoded stdout chunks, including line separators.
 * Install listeners before starting the child so its initial ready event is kept.
 * Writes are serialized; resolve write() only when the complete chunk is written.
 * close() must release the child and its process listeners, and may run on failure.
 */
export interface NotchTransport {
  write(chunk: string): Promise<void>;
  onData(listener: (chunk: string) => void): Unsubscribe;
  onError(listener: (error: Error) => void): Unsubscribe;
  onClose(listener: (exit: TransportExit) => void): Unsubscribe;
  close(): Promise<void>;
}

export class NotchError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "NotchError";
  }
}

const maximumLineBytes = 65_536;
const maximumTimeoutMs = 2_147_483_647;
const encoder = new TextEncoder();
interface Pending {
  command: NotchCommand;
  resolve: (result: NotchResult) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

/** Correlated requests, readiness, bounded framing, and native UI events. */
export class NotchClient {
  readonly ready: Promise<void>;
  /** Resolves with the reason when the session ends, even when no request is pending. */
  readonly closed: Promise<Error>;
  private closedResolve!: (reason: Error) => void;
  private readyResolve!: () => void;
  private readyReject!: (error: Error) => void;
  private readyTimer: ReturnType<typeof setTimeout>;
  private readyReceived = false;
  private hostCapabilities = new Set<string>();
  private quitTimer: ReturnType<typeof setTimeout> | undefined;
  private buffer = "";
  private sequence = 0;
  private ended: Error | undefined;
  private quitting = false;
  private pending = new Map<string, Pending>();
  private listeners = new Set<(event: NotchEvent) => unknown>();
  private unsubscribes: Unsubscribe[] = [];
  private writeQueue = Promise.resolve();
  private closePromise: Promise<void> | undefined;
  private readonly timeoutMs: number;

  constructor(
    private readonly transport: NotchTransport,
    private readonly options: NotchClientOptions = {},
  ) {
    this.timeoutMs = options.timeoutMs ?? 5_000;
    if (
      !Number.isFinite(this.timeoutMs) ||
      this.timeoutMs < 1 ||
      this.timeoutMs > maximumTimeoutMs
    ) {
      throw new RangeError(`timeoutMs must be between 1 and ${maximumTimeoutMs}`);
    }
    this.closed = new Promise((resolve) => {
      this.closedResolve = resolve;
    });
    this.ready = new Promise((resolve, reject) => {
      this.readyResolve = resolve;
      this.readyReject = reject;
    });
    // A client can fail before its owner awaits ready or dispose.
    void this.ready.catch(() => {});
    this.readyTimer = setTimeout(
      () => this.fail(new NotchError("ready_timeout", "Native notch host did not become ready")),
      this.timeoutMs,
    );
    const subscriptions = [
      () => transport.onData((chunk) => this.receive(chunk)),
      () => transport.onError((error) => this.fail(asError(error))),
      () =>
        transport.onClose((exit) =>
          this.fail(
            new NotchError(
              "host_closed",
              `Native notch host exited (${exit.code ?? exit.signal ?? "unknown"})`,
            ),
          ),
        ),
    ];
    try {
      for (const subscribe of subscriptions) {
        if (this.ended) break;
        const unsubscribe = subscribe();
        // Transports may synchronously deliver buffered output during registration.
        if (this.ended) this.unsubscribe(unsubscribe);
        else this.unsubscribes.push(unsubscribe);
      }
    } catch (error) {
      this.fail(asError(error));
    }
  }

  onEvent(listener: (event: NotchEvent) => unknown): Unsubscribe {
    if (this.ended) return () => {};
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /** Feature names announced by the host; empty until `ready` resolves. */
  get capabilities(): readonly string[] {
    return [...this.hostCapabilities];
  }

  onAction(listener: (actionId: string) => unknown): Unsubscribe {
    return this.onEvent((event) =>
      event.event === "action" ? listener(event.actionId) : undefined,
    );
  }

  onState(listener: (snapshot: NotchSnapshot) => unknown): Unsubscribe {
    return this.onEvent((event) =>
      event.event === "state" || event.event === "result" ? listener(event) : undefined,
    );
  }

  show(state: NotchPatch = {}): Promise<NotchResult> {
    return this.request("show", state);
  }
  update(state: NotchPatch): Promise<NotchResult> {
    return this.request("update", state);
  }
  hide(): Promise<NotchResult> {
    return this.request("hide");
  }
  quit(): Promise<NotchResult> {
    return this.request("quit");
  }

  /** Force close the transport once and reject every outstanding request. */
  async dispose(): Promise<void> {
    this.fail(new NotchError("disposed", "Notch client was disposed"));
    await this.closeTransport();
  }

  private async request(command: NotchCommand, state?: NotchPatch): Promise<NotchResult> {
    if (this.ended) throw this.ended;
    if (this.quitting)
      throw new NotchError("session_closed", "Native notch host session is closing");
    if (command === "quit") this.quitting = true;
    await this.ready;
    if (this.ended) throw this.ended;
    if (
      state?.progress !== undefined &&
      state.progress !== null &&
      (!Number.isFinite(state.progress) || state.progress < 0 || state.progress > 1)
    ) {
      throw new NotchError(
        "invalid_state",
        "progress must be null or a finite number between 0 and 1",
      );
    }
    if (state?.expandedSize !== undefined) {
      if (!this.hostCapabilities.has("expanded-size")) {
        throw new NotchError(
          "unsupported_feature",
          "Native notch host does not support expandedSize",
        );
      }
      if (state.expandedSize !== null && !validSize(state.expandedSize)) {
        throw new NotchError(
          "invalid_state",
          "expandedSize must contain a width of 280–1600 and a height of 140–1000",
        );
      }
    }
    const id = `hn-${++this.sequence}`;
    const line = JSON.stringify(state === undefined ? { id, command } : { id, command, state });
    if (encoder.encode(line).byteLength > maximumLineBytes) {
      throw new NotchError("line_too_large", "Request exceeds the native host's 64 KiB line limit");
    }
    return new Promise<NotchResult>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.fail(new NotchError("request_timeout", `Native notch host timed out for ${command}`));
      }, this.timeoutMs);
      this.pending.set(id, { command, resolve, reject, timer });
      this.writeQueue = this.writeQueue.then(async () => {
        if (this.ended || !this.pending.has(id)) return;
        try {
          await this.transport.write(line + "\n");
        } catch (error) {
          this.fail(asError(error));
        }
      });
    });
  }

  private receive(chunk: string): void {
    let start = 0;
    while (!this.ended && start < chunk.length) {
      const end = chunk.indexOf("\n", start);
      const part = chunk.slice(start, end === -1 ? undefined : end);
      // Check before concatenation so one oversized chunk cannot grow the buffer.
      if (this.buffer.length + part.length > maximumLineBytes) {
        this.fail(new NotchError("line_too_large", "Native host emitted an oversized JSON line"));
        return;
      }
      const framed = this.buffer + part;
      if (encoder.encode(framed).byteLength > maximumLineBytes) {
        this.fail(new NotchError("line_too_large", "Native host emitted an oversized JSON line"));
        return;
      }
      this.buffer = framed;
      if (end === -1) return;
      this.buffer = "";
      start = end + 1;
      const line = framed.replace(/\r$/, "");
      if (!line) continue;
      try {
        this.handle(parseEvent(JSON.parse(line)));
      } catch (error) {
        this.fail(new NotchError("invalid_message", asError(error).message));
        return;
      }
    }
  }

  private handle(event: NotchEvent): void {
    if (event.event === "ready") {
      if (this.readyReceived) throw new Error("Native notch host sent ready more than once");
      this.readyReceived = true;
      this.hostCapabilities = new Set(event.capabilities);
      clearTimeout(this.readyTimer);
      this.readyResolve();
    } else if (!this.readyReceived) {
      throw new Error("Native notch host sent an event before ready");
    }
    let quitAcknowledged = false;
    if (event.event === "result" || event.event === "error") {
      const request = event.id ? this.pending.get(event.id) : undefined;
      if (request && event.id) {
        clearTimeout(request.timer);
        this.pending.delete(event.id);
        quitAcknowledged = request.command === "quit";
        if (event.event === "result") request.resolve(event);
        else request.reject(new NotchError(event.code, event.message));
      }
    }
    // New subscriptions start with the next event, even if a callback subscribes again.
    for (const listener of [...this.listeners]) {
      if (!this.listeners.has(listener)) continue;
      try {
        void Promise.resolve(listener(event)).catch((error) => this.reportListenerError(error));
      } catch (error) {
        this.reportListenerError(error);
      }
    }
    if (quitAcknowledged && !this.ended) {
      // Let an acknowledged quit exit normally; killing here races the host's
      // successful exit and turns it into an unexpected signal termination.
      this.quitTimer = setTimeout(
        () =>
          this.fail(
            new NotchError(
              "host_exit_timeout",
              "Native notch host acknowledged quit but did not exit",
            ),
          ),
        this.timeoutMs,
      );
    }
  }

  private fail(error: Error): void {
    if (this.ended) return;
    this.ended = error;
    this.closedResolve(error);
    this.buffer = "";
    clearTimeout(this.readyTimer);
    clearTimeout(this.quitTimer);
    this.readyReject(error);
    for (const request of this.pending.values()) {
      clearTimeout(request.timer);
      request.reject(error);
    }
    this.pending.clear();
    for (const unsubscribe of this.unsubscribes) this.unsubscribe(unsubscribe);
    this.unsubscribes = [];
    this.listeners.clear();
    void this.closeTransport().catch(() => {});
  }

  private closeTransport(): Promise<void> {
    if (this.closePromise) return this.closePromise;
    let resolve!: () => void;
    let reject!: (error: unknown) => void;
    this.closePromise = new Promise<void>((done, failed) => {
      resolve = done;
      reject = failed;
    });
    try {
      void Promise.resolve(this.transport.close()).then(resolve, reject);
    } catch (error) {
      reject(error);
    }
    // Automatic cleanup must not mask the original failure with an unhandled rejection.
    void this.closePromise.catch(() => {});
    return this.closePromise;
  }

  private unsubscribe(unsubscribe: Unsubscribe): void {
    try {
      unsubscribe();
    } catch (error) {
      this.reportListenerError(error);
    }
  }

  private reportListenerError(error: unknown): void {
    try {
      if (this.options.onListenerError) {
        void Promise.resolve(this.options.onListenerError(asError(error))).catch(
          (callbackError) => {
            console.error("Notch error listener failed:", callbackError);
          },
        );
      } else console.error("Notch event listener failed:", error);
    } catch (callbackError) {
      console.error("Notch error listener failed:", callbackError);
    }
  }
}

function asError(error: unknown): Error {
  return error instanceof Error ? error : new Error(String(error));
}

function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function validSize(value: unknown): value is NotchSize {
  return (
    record(value) &&
    typeof value.width === "number" &&
    value.width >= notchSizeBounds.minWidth &&
    value.width <= notchSizeBounds.maxWidth &&
    typeof value.height === "number" &&
    value.height >= notchSizeBounds.minHeight &&
    value.height <= notchSizeBounds.maxHeight
  );
}

function validState(value: unknown): value is NotchState {
  return (
    record(value) &&
    typeof value.style === "string" &&
    ["contour", "capsule", "glass"].includes(value.style) &&
    typeof value.motion === "string" &&
    ["spring", "gentle", "snappy"].includes(value.motion) &&
    typeof value.expanded === "boolean" &&
    typeof value.title === "string" &&
    value.title.trim().length > 0 &&
    typeof value.subtitle === "string" &&
    typeof value.activity === "string" &&
    ["idle", "working", "listening", "success"].includes(value.activity) &&
    (value.progress === null ||
      (typeof value.progress === "number" &&
        Number.isFinite(value.progress) &&
        value.progress >= 0 &&
        value.progress <= 1)) &&
    (value.expandedSize === undefined ||
      value.expandedSize === null ||
      validSize(value.expandedSize)) &&
    Array.isArray(value.actions) &&
    value.actions.length <= 4 &&
    value.actions.every(
      (action) =>
        record(action) &&
        validIdentifier(action.id, 64) &&
        typeof action.label === "string" &&
        action.label.trim().length > 0,
    ) &&
    new Set(value.actions.map((action) => action.id)).size === value.actions.length
  );
}

function validIdentifier(value: unknown, maximum: number): value is string {
  return (
    typeof value === "string" &&
    value.trim().length > 0 &&
    encoder.encode(value).byteLength <= maximum * 4 &&
    !/[\p{Cc}\p{Cf}]/u.test(value)
  );
}

function parseEvent(value: unknown): NotchEvent {
  if (record(value)) {
    switch (value.event) {
      case "ready":
        if (value.protocolVersion !== 1) {
          throw new Error(`Unsupported notch protocol version ${String(value.protocolVersion)}`);
        }
        if (
          value.capabilities === undefined ||
          (Array.isArray(value.capabilities) &&
            value.capabilities.every((capability) => typeof capability === "string"))
        )
          return value as unknown as NotchEvent;
        break;
      case "result":
        if (
          validIdentifier(value.id, 128) &&
          value.ok === true &&
          validState(value.state) &&
          typeof value.visible === "boolean"
        )
          return value as unknown as NotchResult;
        break;
      case "state":
        if (validState(value.state) && typeof value.visible === "boolean")
          return value as unknown as NotchEvent;
        break;
      case "action":
        if (validIdentifier(value.actionId, 64)) return value as unknown as NotchEvent;
        break;
      case "error":
        if (
          (value.id === undefined || validIdentifier(value.id, 128)) &&
          typeof value.code === "string" &&
          typeof value.message === "string"
        )
          return value as unknown as NotchEvent;
        break;
    }
  }
  throw new Error("Malformed native notch event");
}
