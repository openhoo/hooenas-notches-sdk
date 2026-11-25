# Changelog

## 0.2.0 — 2026-11-25

- Fit the overlay to its actual display while preserving camera clearance and
  preserving editor focus through size changes. `NotchConfiguration.fitting(in:)`
  also works for inline previews.
- Release hidden content when AppKit temporarily retains the detached hosting
  view.
- Add a single binding presentation helper, explicit keyboard focus, localizable
  accessibility labels, and camera aware compact content slots.
- Keep the collapse button inside the outline at small sizes and custom radii.
- Add `expandedSize` to desktop host patches and the TypeScript client, including
  live resizing, default reset, and capability negotiation with older hosts.
- Make the desktop host controls scroll or wrap at small sizes and add size
  controls to the Swift and Tauri showcases.
- Keep an explicitly opened notch open when an earlier hover delay expires.
  Stop idle pointer polling outside the notch when movement monitoring is available.
- Let Escape collapse a keyboard-focused screen panel even when it contains
  only read-only content. Text editors and popovers keep their own Escape handling.
- Reject invalid null fields without applying the rest of a patch. Bound sidecar
  startup and keep action delivery stable when listeners subscribe again.
- Stop the Tauri progress demo on Hide, show the settings acknowledged by the host,
  and offer to reconnect when the host exits.

## 0.1.1 — 2026-11-16

### Fixed

- Preserve the hosting view, SwiftUI state, unfinished editor text and keyboard
  focus when updating a visible panel or refreshing its screen geometry.
- Release expansion captures and event tracking when hiding the panel.
- Keep large contour radii inside shallow bounds; preserve valid custom geometry
  on displays without a camera and ignore invalid screen metrics.
- Keep a hover-opened notch available while its text field has keyboard focus;
  preserve compact content labels and scope Escape handling to expanded content.
- Clean up failed client connections and pending requests, handle synchronous
  transport failures, reject invalid enum values and isolate listener errors.
- Bound native input processing and state output; build Tauri sidecars for the
  requested target architecture and handle window shutdown consistently.

### Quality

- Focused native, protocol, client and Tauri regressions for the failures above.
- Reproducible formatting, warnings-as-errors builds, real-host integration,
  Tauri bundling, Clippy, documentation/media checks and macOS GitHub Actions.
- Correct native keyboard test dispatch by verifying the key panel and first
  responder and real SwiftUI focus before routing Escape through AppKit.
- Check both macOS dependency graphs and document the open `glib 0.18.5`
  advisory in the unsupported Linux dependency graph.
- Updated component documentation, regenerated showcase media and validated
  dimensions and timing. Visually inspected the representative expanded GIF
  frames and exercised the actual SwiftUI showcase through every surface,
  completion, panel interaction and shutdown.
- Verified 39 Swift tests with one explicit AX baseline skip, 25 client/adapter
  tests and four integrations against the real Swift host. Built a universal
  Tauri app and checked its surfaces, expansion, progress, motion, hide and
  process cleanup on the actual desktop. See the
  [quality review](docs/quality-review-2026-11-16.md) for evidence and remaining
  platform, accessibility and delivery limits.

## 0.1.0 — 2026-11-16

Initial public SDK: Contour, Capsule and Glass; SwiftUI/AppKit overlay; native
JSON Lines host; typed client; Tauri example and animated README showcase.
