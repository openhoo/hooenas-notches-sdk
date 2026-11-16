# SDK quality review — November 16, 2026

## Scope and environment

This review covers SDK **0.1.1**, native host protocol **1**, the TypeScript
client and the Tauri v2 example. The supported minimum remains macOS 14.
Recorded desktop checks ran on **Apple Silicon, macOS 26.6.2 (25G83)**, with
**Xcode 26.5 beta (17F5032f)**. Results below are local verification; a hosted CI
run has its own status.

## Automated checks

| Check                                                           | Recorded result                            |
| --------------------------------------------------------------- | ------------------------------------------ |
| Swift protocol and native suites                                | 39 total: 38 passed, 1 skipped, 0 failures |
| TypeScript client and Tauri adapter                             | 25 passed, 0 failures                      |
| Integration against the actual Swift host                       | 4 passed, 0 failures                       |
| Swift debug/tests and release builds with warnings as errors    | Passed                                     |
| Swift formatting, Ruff, Prettier and rustfmt                    | Passed                                     |
| Strict TypeScript and production frontend build                 | Passed                                     |
| Complete Tauri application bundle                               | Passed                                     |
| `cargo clippy --locked --all-targets -- -D warnings`            | Passed                                     |
| Documentation links, legal-resource presence and media metadata | Passed                                     |

The native tests cover panel and hosting-view attachment, preserved SwiftUI
state/editor focus, hover and Escape behavior, normalized geometry and rendered
top pixels. Protocol tests cover framing and atomic rejection of invalid or
oversized accumulated state. The actual-host integrations additionally exercise
32 concurrent updates, fragmented UTF-8, oversized-line recovery, EOF handling
and clean shutdown when the parent closes stdout. The separate open-stdin smoke
also completed ready, show, update, invalid-state rejection, hide and quit.

The single skipped test is
`NotchAccessibilityTests.testCompactButtonPreservesAccessibleContentDescription`.
A plain SwiftUI Button used as the baseline exposes no AX children in this
XCTest process, so the test cannot perform its runtime comparison. This skip
does not establish accessibility or VoiceOver acceptance.

The shared entry point is `./scripts/check.sh`. Focused commands and local
prerequisites are documented in `CONTRIBUTING.md`. The Tauri universal build used
`npm run tauri:build -- --target universal-apple-darwin --no-sign`. The main
executable and bundled native host both contain `x86_64` and `arm64`; the helper
reports `hooenas-notches-host 0.1.1 (protocol 1)`.

## Actual Tauri desktop smoke

The universal Tauri application was launched and exercised on the desktop:

- Contour, Capsule and Glass were selected and rendered.
- Expansion worked; progress reached `activity: "success"` and `progress: 1`.
- The `gentle` motion selection was applied.
- Hide produced a visible state snapshot with `visible: false`.
- Quit completed; a `pgrep` process check found no orphan native host.

These observations cover the listed interactions on the local Apple Silicon
machine. They do not constitute an Intel or macOS 14 GUI run, nor distribution
signing/notarization qualification.

## Actual SwiftUI showcase smoke

The final release showcase executable was wrapped in a temporary local `.app`
for desktop inspection. Contour, Capsule and Glass were selected. Expansion and
Show displayed the actual panel; Finish reached `activity: "success"` and
`progress: 1`. Closing the main window left the real overlay visible. Escape
collapsed it with compact AX description `Complete,100%`; clicking expanded it
again. Quit completed the smoke.

The compact description was observed directly through the actual application.
No VoiceOver evaluation is claimed, and the automated AX baseline test remains
skipped as described above.

## Media and local evidence

All three README GIFs were regenerated and passed metadata validation:
**840 × 532 pixels, 100 frames, 5,000 ms duration and an infinite loop**.
Local links and required license resources resolve.
Representative expanded **frame 55 of each GIF** was visually inspected and was
clean for content, branding, attachment and clipping. The three regenerated
2880 × 1800 utility Store PNGs were also inspected in the private app review.
The matching showcase GIFs were copied into this public repository.

The open-stdin result is stored locally at
`output/host-open-stream-smoke.json`. The built universal app is at
`examples/tauri/src-tauri/target/universal-apple-darwin/release/bundle/macos/Hooenas Notches Tauri.app`.
These paths describe ignored local artifacts; they are not downloadable
repository evidence. The desktop smoke was observed during this review rather
than inferred from unit tests.

## CI configuration review

The workflow runs the same quality entry point on `macos-26` and selects
`/Applications/Xcode_26.5.app/Contents/Developer`. The official
`actions/runner-images` macOS 26 Arm64 inventory, image **20261102.0473.1**,
was checked on November 16, 2026 and lists **Xcode 26.5 (17F42)** at that path.
That hosted Xcode build is different from the local beta identified above.
Official inventory:
`https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-arm64-Readme.md`.

## Remaining verification

- Verify runtime accessibility outside the XCTest baseline limitation.
- Exercise the GUI on actual macOS 14 and Intel hardware. Universal compilation
  has passed; those GUI environments were not exercised.
- Qualify signing and notarization in each distributing application. The tested
  universal Tauri build was explicitly produced with `--no-sign`.
- Complete remote CI verification and publication of the 0.1.1 changes. The
  recorded local automated, desktop and media gates are complete.

The TypeScript package remains a repository source package; no npm publication
is claimed by this review.
