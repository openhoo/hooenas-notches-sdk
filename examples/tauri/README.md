# Native notch from Tauri v2

This is a real Tauri application, with a TypeScript frontend, the official shell
plugin, and the `hooenas-notches-host` Swift executable as a bundled sidecar. The
notch is drawn by SwiftUI and AppKit on the macOS desktop.

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools with Swift 6.2 or newer
- Rust with a macOS host target
- Node.js 22.12 or newer

## Run

From the repository root:

```sh
cd packages/client
npm ci
npm run build
cd ../../examples/tauri
npm ci
npm run tauri:dev
```

Tauri's `beforeDevCommand` builds the release Swift host, copies it to
`src-tauri/binaries/hooenas-notches-host-<target-triple>`, and starts Vite. The Rust
target triple comes from `CARGO_BUILD_TARGET`, or `rustc -vV` for the current host.
The Swift architecture is selected to match that triple.

The example supports Contour, Capsule, and Glass styles, three motion presets,
expanded and collapsed presentation, progress, and native action callbacks.
Opening the Vite page in a normal browser displays an explanation; launching
through Tauri enables the native sidecar.

## Build an application bundle

```sh
npm run tauri:build
```

The bundle contains the architecture-specific native helper. Distribution beyond
your development machine also requires your own macOS signing and notarization
setup; none is configured by this example.

## How the bridge works

1. `bundle.externalBin` registers `binaries/hooenas-notches-host`.
2. The macOS capability grants `shell:allow-spawn` for that sidecar and its fixed
   `--stdio` argument, plus stdin-write and kill permissions.
3. `createTauriNotch()` subscribes to process output before spawning the host and
   waits for its protocol-v1 ready event.
4. `show`, `update`, `hide`, and `quit` send correlated JSON-lines commands.
5. The native host sends acknowledgements, state events, and action IDs back to
   the TypeScript client.

See `../../packages/client/README.md` for the complete state and client API.

## Verify the integration

From the repository root, run:

```sh
swift test
swift build -c release --product hooenas-notches-host
npm --prefix packages/client test
npm --prefix packages/client run test:native
npm --prefix examples/tauri run build
```

The client integration test exchanges show, update, progress-clear, hide and quit
commands with the real Swift host while keeping stdin open. Native Swift tests
inspect the AppKit panel, hosting view and rendered top pixel row for every
surface. The example's progress button and native Cancel action provide an
interactive check of updates and callbacks. Signing and notarization belong to
the application that distributes the helper.

## Documentation checked

The integration was checked against Tauri v2 documentation through the configured
HooLLM Context7 connection on November 15, 2026:

- https://v2.tauri.app/develop/sidecar/
- https://v2.tauri.app/plugin/shell/
- https://github.com/tauri-apps/plugins-workspace/tree/v2/plugins/shell

## License

The repository's FSL-1.1-MIT license and third-party notices apply. Cua source is
not currently relicensed as MIT.
