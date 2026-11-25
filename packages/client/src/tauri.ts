import { Command, type Child } from "@tauri-apps/plugin-shell";
import {
  NotchClient,
  NotchError,
  type NotchClientOptions,
  type NotchTransport,
  type TransportExit,
  type Unsubscribe,
} from "./index.js";

export interface TauriNotchOptions extends NotchClientOptions {
  /** Must equal the bundle.externalBin entry and scoped shell capability name. */
  sidecar?: string;
  onStderr?: (line: string) => unknown;
}

/** Spawn the real Swift/AppKit overlay through Tauri v2's shell plugin. macOS only. */
export async function createTauriNotch(options: TauriNotchOptions = {}): Promise<NotchClient> {
  const command = Command.sidecar(options.sidecar ?? "binaries/hooenas-notches-host", ["--stdio"]);
  const data = new Set<(chunk: string) => void>();
  const errors = new Set<(error: Error) => void>();
  const exits = new Set<(exit: TransportExit) => void>();
  let child: Child | undefined;
  let exited = false;
  let closing = false;
  const transport: NotchTransport = {
    async write(chunk) {
      if (!child || exited || closing) throw new Error("Native notch sidecar is not running");
      await child.write(chunk);
    },
    onData(listener) {
      data.add(listener);
      return () => data.delete(listener);
    },
    onError(listener) {
      errors.add(listener);
      return () => errors.delete(listener);
    },
    onClose(listener) {
      exits.add(listener);
      return () => exits.delete(listener);
    },
    async close() {
      closing = true;
      detach();
      if (child && !exited) await child.kill();
    },
  };
  const stdout = (line: string): void => {
    for (const listener of data) listener(line + "\n");
  };
  const stderr = (line: string): void => {
    const report = (error: unknown): void => {
      if (options.onListenerError) {
        try {
          void Promise.resolve(
            options.onListenerError(error instanceof Error ? error : new Error(String(error))),
          ).catch((callbackError) => {
            console.error("Notch error listener failed:", callbackError);
          });
        } catch (callbackError) {
          console.error("Notch error listener failed:", callbackError);
        }
      } else console.error("Notch stderr listener failed:", error);
    };
    try {
      void Promise.resolve(options.onStderr?.(line)).catch(report);
    } catch (error) {
      report(error);
    }
  };
  const failure = (message: string): void => {
    for (const listener of errors) listener(new Error(message));
  };
  const close = (exit: TransportExit): void => {
    exited = true;
    for (const listener of exits) listener(exit);
    detach();
  };
  const detach: Unsubscribe = () => {
    command.stdout.off("data", stdout);
    command.stderr.off("data", stderr);
    command.off("error", failure);
    command.off("close", close);
  };
  const timeoutMs = options.timeoutMs ?? 5_000;
  const client = new NotchClient(transport, { ...options, timeoutMs });
  command.stdout.on("data", stdout);
  command.stderr.on("data", stderr);
  command.on("error", failure);
  command.on("close", close);
  // The ready line and the IPC reply containing the child handle arrive independently.
  // Keep the startup deadline active until both are available.
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new NotchError("ready_timeout", "Native notch sidecar did not finish starting")),
      timeoutMs,
    );
  });
  try {
    const spawn = async (): Promise<void> => {
      child = await command.spawn();
      if (closing && !exited) await child.kill();
    };
    await Promise.race([
      Promise.all([client.ready, spawn()]),
      client.closed.then((reason) => {
        throw reason;
      }),
      deadline,
    ]);
    if (closing || exited)
      throw new NotchError("host_closed", "Native notch host closed during startup");
    return client;
  } catch (error) {
    detach();
    // Start cleanup immediately; an unresponsive shell IPC must not hold up the error.
    void client.dispose().catch(() => {});
    throw error;
  } finally {
    clearTimeout(timer);
  }
}
