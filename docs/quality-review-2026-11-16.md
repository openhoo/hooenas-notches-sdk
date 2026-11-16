# SDK quality review — November 16, 2026

## Scope and environment

This review covers SDK **0.1.1**, native host protocol **1**, the TypeScript
client and the Tauri v2 example. The supported minimum remains macOS 14.
Recorded desktop checks ran on **Apple Silicon, macOS 26.6.2 (25G83)**, with
**Xcode 26.5 beta (17F5032f)**. The hosted quality gate also passed on the
production Xcode build recorded below; desktop interaction results remain
specific to the local machine.

## Automated checks

| Check                                                           | Recorded result                            |
| --------------------------------------------------------------- | ------------------------------------------ |
| Swift protocol and native suites                                | 40 total: 39 passed, 1 skipped, 0 failures |
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

The interaction observations and executable hashes are recorded in
`output/review-desktop-smoke.json`. `output/review-pages-check.json` records HTTP
200 responses and byte-for-byte matches for the published landing, privacy and
support pages and all three GIFs.

## Packaged release helper smoke

The prepared `hooenas-notches-host-v0.1.1-universal-macos.tar.gz` was extracted
and tested directly, without rebuilding the helper. Its SHA-256 is
`59dd385e16b768fde30980a72ae9117c47c2316a22ac0f19a5fe83a6e050201c`.
The checksum manifest passed; the extracted helper contains both `arm64` and
`x86_64` and reports version `0.1.1`, protocol `1`.

The existing open-stdin smoke passed ready, show, update, atomic rejection of an
invalid patch, hide and quit against that extracted executable, with exit code
0 and empty stderr. The bundled license, third-party notices, preserved upstream
license and protocol documentation matched repository sources byte-for-byte.
Archive and manifest hashes remained unchanged after the smoke. Evidence is
retained locally at `output/release-asset-smoke-pusebbu4/verification.json`.

This is a development helper without distribution signing or notarization, as
stated in its bundled README. The smoke does not establish distribution
qualification.

## Dependency and secret review

Full `npm audit` checks for the development root, TypeScript client and Tauri
example reported zero vulnerabilities, including development dependencies.
Gitleaks found no secrets in the staged review changes or the locally available
Git history, including all branches at the time of the scan. The history result
is recorded in `output/review-history-secrets.json`. These checks do not
establish that every dependency or repository revision is free of vulnerabilities.

The Rust lockfile retains an open moderate advisory for `glib 0.18.5`,
`GHSA-wrw7-89jp-8q8g` / `RUSTSEC-2024-0429`. The crate is absent from both locked
macOS target dependency trees, `aarch64-apple-darwin` and
`x86_64-apple-darwin`. It is present in the Linux GTK/WebKit dependency graph.
This example supports macOS only; no Linux build or security qualification is
claimed. A compatible upstream fix is not available in the checked stable Tauri
dependency chain. The advisory remains open and was not dismissed. See the
[Tauri dependency assessment](../examples/tauri/README.md#dependency-advisory)
for primary sources and the exact limitation.

## CI configuration review

The workflow runs the same quality entry point on `macos-26` and selects
`/Applications/Xcode_26.5.app/Contents/Developer`. The actual hosted diagnostic
used **macOS 26.7.2 (25G332)**, Arm64 image **20261112.0504.1**, and
**Xcode 26.5 (17F42)**. That hosted Xcode build differs from the local beta.
The matching runner inventory is
`https://github.com/actions/runner-images/blob/macos-26-arm64/20261112.0504/images/macos/macos-26-arm64-Readme.md`.

Initial hosted runs exposed two keyboard-fixture failures. A key panel and
AppKit first responder alone did not establish SwiftUI focus. In the isolated
hosted diagnostic run **43832969432**, an unfocused plain SwiftUI host also
ignored Escape; the focused host baseline and both focused notch cases passed.
Calling `finishLaunching` did not change the unfocused result. This confirms
the documented focus precondition of `onExitCommand`.

The final fixture makes the panel key, waits for a real SwiftUI text field to
own the field editor, and sends Escape through `NSApplication.sendEvent`. It
retains a plain-host comparison and detects a deliberately restored collapsed
interception regression. Production sources are unchanged. Diagnostic matrix
code and logging are excluded from the final fixture. Evidence is retained
locally in `output/review-keyboard-ci-diagnostics.log` and
`output/review-keyboard-focused-full.log`.

Hosted [Quality run 43833573682](https://github.com/openhoo/hooenas-notches-sdk/actions/runs/43833573682)
passed for source revision `2678d96f4b2958585b3a820311c447e1941a90e9` on
November 16, 2026. It completed all 40 Swift tests with the documented single AX
skip, all three keyboard cases, 25 client/adapter tests, four actual-host
integrations, the open-stdin smoke, release builds, Tauri bundling, Clippy and
documentation/media checks. The hosted build used the production Xcode version
recorded above. Its log is retained locally in
`output/review-quality-focused-hosted.log`.

[CodeQL run 43829642947](https://github.com/openhoo/hooenas-notches-sdk/actions/runs/43829642947)
passed at production-source revision `71ea51a49e06b30627ae15352ed17f86b1fe4d7e`,
including Swift and JavaScript/TypeScript analysis. Production sources are
unchanged between that revision and the hosted quality revision above. The
subsequent commits changed the keyboard test fixture and review documentation.

## Remaining verification

- Verify runtime accessibility outside the XCTest baseline limitation.
- Exercise the GUI on actual macOS 14 and Intel hardware. Universal compilation
  has passed; those GUI environments were not exercised.
- Qualify signing and notarization in each distributing application. The tested
  universal Tauri build was explicitly produced with `--no-sign`.

The hosted quality, local automated, desktop and media gates are complete.
Versioned publication and final-head verification are recorded in the GitHub
release, separately from the source-revision evidence above.

The TypeScript package remains a repository source package; no npm publication
is claimed by this review.
