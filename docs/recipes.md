# Build a notch for your app

The Swift example uses `NotchCompactWings` and size fitting from SDK 0.2.0.
See [installation](../README.md#install-with-swift-package-manager) or use a
[local checkout](../README.md#use-a-local-checkout).

Choose one item for the compact notch: a timer, progress, or a short status.
Put actions and details in the expanded view. `NotchCompactWings` fits the
status around the camera; the same view also works inline on other displays.

| Use case                   | Compact                     | Expanded                                 |
| -------------------------- | --------------------------- | ---------------------------------------- |
| Focus or meeting countdown | Remaining time              | Start, pause, reset, and duration        |
| Upload or build status     | Percentage or activity      | Progress, status, and cancel             |
| Media in your app          | Play state                  | Title, play/pause, and skip controls     |
| File shelf                 | Item count                  | Drop target, file list, and open buttons |
| Notes and checklist        | A symbol or remaining count | Editor or checklist with keyboard focus  |

The Swift library owns presentation and layout. Your app supplies the data,
permissions, persistence, and actions. The TypeScript client offers a fixed
native view for text, progress and up to four actions; use SwiftUI for your own
card layout, drop targets or text editors.

## A responsive pair of cards

Both cards are ordinary views. The same content becomes one column when the
notch narrows, and the scroll view keeps both controls available at short
heights. Bind `width` and `height` to your app's controls or saved settings.

```swift
import SwiftUI
import HooenasNotches

struct WorkbenchNotch: View {
    @State private var expanded = false
    @State private var needsReview = true
    var width: CGFloat = 480
    var height: CGFloat = 240

    var body: some View {
        HooenasNotch(
            isExpanded: $expanded,
            configuration: NotchConfiguration(expandedSize: CGSize(width: width, height: height)),
            hoverOpens: false
        ) {
            NotchCompactWings {
                Image(systemName: "tray").accessibilityHidden(true)
            } trailing: {
                Text(needsReview ? "1 task" : "Ready").font(.caption).lineLimit(1)
            }
        } expanded: {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading) {
                    VStack(alignment: .leading) {
                        Text("Daily checklist").font(.headline)
                        Toggle("Review notes", isOn: $needsReview)
                    }
                    VStack(alignment: .leading) {
                        Text("Daily progress").font(.headline)
                        ProgressView(value: needsReview ? 0 : 1)
                            .accessibilityLabel("Daily progress")
                    }
                }
            }
        }
    }
}
```

For a resizable preview, fit your configuration to the available frame with
`fitting(in:)`. For a real overlay, pass the configuration to the
[native screen overlay](../README.md#native-screen-overlay); the controller
applies the display bounds and camera clearance. Keep actions visible, verify
keyboard access at the smallest offered size, and label compact icon-only
status and actions for assistive technology.
