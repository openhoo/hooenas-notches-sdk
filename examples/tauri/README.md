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
target triple comes from Tauri's `TAURI_ENV_TARGET_TRIPLE` build-hook variable,
then `CARGO_BUILD_TARGET`, or `rustc -vV` for the current host. The Swift
architecture is selected to match that triple. Explicit Tauri `--target`
builds therefore prepare the correct helper. `universal-apple-darwin` builds
both Swift architectures and combines them with `lipo` into one sidecar. The
two individual helpers are retained for Tauri's intermediate architecture builds.

The example supports Contour, Capsule, and Glass styles, three motion presets,
expanded and collapsed presentation, progress, and native action callbacks.
The size picker follows the host’s acknowledged size and is disabled for older
hosts. Hide stops an active progress demo. If the sidecar exits, the controls
are disabled and Reconnect starts a new session.
Opening the Vite page in a normal browser displays an explanation; launching
through Tauri enables the native sidecar.

## Build an application bundle

```sh
npm run tauri:build
```

For a universal application, install both macOS Rust targets and run
`npm run tauri:build -- --target universal-apple-darwin`. The helper build
supports both Apple Silicon and Intel.

The bundle contains a native helper with the same architecture as the application
(both architectures for a universal bundle). Distribution beyond
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

## Dependency advisory

This example and its native renderer support **macOS 14 or newer only**. As
checked on November 16, 2026, the cross-platform `Cargo.lock` contains
`glib 0.18.5`, affected by
[GHSA-wrw7-89jp-8q8g](https://github.com/advisories/GHSA-wrw7-89jp-8q8g) /
[RUSTSEC-2024-0429](https://rustsec.org/advisories/RUSTSEC-2024-0429.html)
(an unsound `VariantStrIter` iterator implementation).

From `examples/tauri/src-tauri`, both commands below complete successfully with
an empty dependency tree (`warning: nothing to print`): `glib 0.18.5` is absent
from both macOS target build graphs.

```sh
cargo tree --locked --target aarch64-apple-darwin --invert glib@0.18.5
cargo tree --locked --target x86_64-apple-darwin --invert glib@0.18.5
```

The equivalent check for `x86_64-unknown-linux-gnu` includes `glib 0.18.5`
transitively through GTK/WebKitGTK in the Tauri/wry stack. This establishes
Linux dependency reachability; application exploitability has not been
established. Linux builds are unsupported by this example.

The checked stable versions (`tauri 2.12.5`, `tauri-runtime-wry 2.12.3`, and
`wry 0.57.2`) still require GTK/glib 0.18 on Linux. There is no compatible
published upstream patch in that dependency family: RustSec lists the fix in
`glib >=0.20.0`, which does not satisfy the existing 0.18 constraints. See the
[Tauri dependencies](https://crates.io/api/v1/crates/tauri/2.12.5/dependencies),
[runtime dependencies](https://crates.io/api/v1/crates/tauri-runtime-wry/2.12.3/dependencies),
[wry dependencies](https://crates.io/api/v1/crates/wry/0.57.2/dependencies),
[GTK dependencies](https://crates.io/api/v1/crates/gtk/0.18.2/dependencies), and
[upstream fix](https://github.com/gtk-rs/gtk-rs-core/pull/1343).
The advisory remains open pending an official compatible backport or a
coordinated upstream upgrade. These checks are limited to the named target
graphs; a globally clean Rust audit is not claimed.

## Documentation checked

The integration and target selection were checked against Tauri v2 documentation
through the configured HooLLM Context7 connection on November 16, 2026:

- https://v2.tauri.app/develop/sidecar/
- https://v2.tauri.app/plugin/shell/
- https://github.com/tauri-apps/plugins-workspace/tree/v2/plugins/shell

## License

The repository's FSL-1.1-MIT license and third-party notices apply. Cua source is
not currently relicensed as MIT.
