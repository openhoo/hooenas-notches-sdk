# Hooenas Notches client

A typed JSON-lines bridge to the **native macOS notch**. The transport-independent
entry point has no runtime dependencies. The optional `/tauri` entry point uses
Tauri v2's official shell plugin to launch the bundled Swift host.

The current host requires macOS 14 or newer. A Tauri webview sends state and receives
actions; SwiftUI and AppKit draw and animate the actual overlay above the menu bar.

## Build locally

```sh
cd packages/client
npm ci
npm run build
npm test
npm run test:native
```

The package is not published to npm. Add it to an app with a local file dependency
or package the compiled `dist/` directory with `npm pack`.

`test:native` launches the real release Swift host on macOS when it has been
built. Override its location with `HOOENAS_NOTCHES_HOST`; other platforms skip
this integration test.

## Tauri v2

```ts
import { createTauriNotch } from "@hooenas-notches/client/tauri";

const notch = await createTauriNotch();

notch.onAction(async actionId => {
  if (actionId === "cancel") {
    await notch.update({ activity: "idle", progress: null, subtitle: "Cancelled" });
  }
});

await notch.show({
  style: "contour",
  motion: "spring",
  expanded: true,
  title: "Uploading your files",
  subtitle: "3 of 8 files",
  activity: "working",
  progress: 0.375,
  actions: [{ id: "cancel", label: "Cancel" }],
});

await notch.update({ progress: 1, activity: "success", subtitle: "All files uploaded" });
await notch.hide();
await notch.quit();
```

Install `@tauri-apps/plugin-shell` in the frontend and `tauri-plugin-shell` in Rust.
Register the plugin in the Tauri builder. Set
`bundle.externalBin: ["binaries/hooenas-notches-host"]` and grant the main window
`shell:allow-spawn` for that exact sidecar with `args: ["--stdio"]`, plus
`shell:allow-stdin-write` and `shell:allow-kill`.

See `../../examples/tauri` for a complete example, capabilities, architecture-aware
binary preparation, and a frontend that controls the native overlay.

## Other desktop hosts

Implement `NotchTransport` for the process API of Electron, Node, a Rust bridge,
or another desktop runtime. Start `hooenas-notches-host --stdio` and subscribe to
stdout before awaiting `client.ready`. Pass **raw text chunks with newline
separators** to `onData`; the client handles fragmented and combined JSON lines.
Tauri's line events omit the separator, so its provided adapter restores it.

```ts
import { NotchClient, type NotchTransport } from "@hooenas-notches/client";

declare const transport: NotchTransport;
const notch = new NotchClient(transport, { timeoutMs: 5_000 });
await notch.ready;
await notch.show({ title: "Hello from your app", style: "capsule" });
```

The generic transport interface is implemented and tested. Runtimes other than
the supplied Tauri adapter need their own process transport.

## State and events

| Field | Values |
| --- | --- |
| `style` | `contour`, `capsule`, `glass` |
| `motion` | `spring`, `gentle`, `snappy` |
| `expanded` | `true` / `false` |
| `title`, `subtitle` | Text |
| `activity` | `idle`, `working`, `listening`, `success` |
| `progress` | `0…1`; `null` clears the value |
| `actions` | Array of `{ id, label }` native buttons |

`show` and `update` accept partial patches. Omitted fields keep their current
value. `show`, `update`, `hide`, and `quit` resolve with the acknowledged native
state and visibility. `onAction` receives native button IDs; `onState` observes
acknowledgements and changes from hover, clicks, and Escape. `onEvent` exposes
all protocol events. Subscriptions return an unsubscribe function.

Requests have bounded response timeouts. Invalid host messages, unsupported
protocol versions, and process exit reject waiting requests. JSON lines are
limited to 65,536 UTF-8 bytes. Call `quit()` for graceful shutdown or `dispose()`
to force close the transport.

## License

FSL-1.1-MIT. The native library contains adapted Cua source and retains its
license and attribution; see this package's `LICENSE` and the repository's
`THIRD_PARTY_NOTICES.md`.
