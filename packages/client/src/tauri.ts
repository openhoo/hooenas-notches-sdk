import { Command, type Child } from "@tauri-apps/plugin-shell";
import { NotchClient, type NotchTransport, type TransportExit, type Unsubscribe } from "./index.js";

export interface TauriNotchOptions {
  /** Must equal the bundle.externalBin entry and scoped shell capability name. */
  sidecar?: string;
  timeoutMs?: number;
  onStderr?: (line: string) => void;
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
      if (!child || exited) throw new Error("Native notch sidecar is not running");
      await child.write(chunk);
    },
    onData(listener) { data.add(listener); return () => data.delete(listener); },
    onError(listener) { errors.add(listener); return () => errors.delete(listener); },
    onClose(listener) { exits.add(listener); return () => exits.delete(listener); },
    async close() { closing = true; if (child && !exited) await child.kill(); },
  };
  const stdout = (line: string): void => { for (const listener of data) listener(line + "\n"); };
  const stderr = (line: string): void => { options.onStderr?.(line); };
  const failure = (message: string): void => { for (const listener of errors) listener(new Error(message)); };
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
  command.stdout.on("data", stdout);
  command.stderr.on("data", stderr);
  command.on("error", failure);
  command.on("close", close);
  const client = new NotchClient(transport, options.timeoutMs === undefined ? {} : { timeoutMs: options.timeoutMs });
  try {
    await Promise.all([
      command.spawn().then(async value => {
        child = value;
        if (closing && !exited) await child.kill();
      }),
      client.ready,
    ]);
    return client;
  } catch (error) {
    detach();
    await client.dispose().catch(() => {});
    throw error;
  }
}
