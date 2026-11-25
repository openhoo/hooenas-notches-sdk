// Hooenas Notches. See LICENSE and THIRD_PARTY_NOTICES.md for source attribution and terms.
import AppKit
import SwiftUI

/// A top-anchored, animated notch with interchangeable skins and arbitrary SwiftUI content.
/// Compact content is a button. Expanded content can contain its own interactive controls.
@MainActor
public struct HooenasNotch<Compact: View, Expanded: View>: View {
    private let style: NotchStyle
    @Binding private var isExpanded: Bool
    private let configuration: NotchConfiguration
    private let motion: NotchMotion
    private let hoverOpens: Bool
    private let accessibilityLabels: NotchAccessibilityLabels
    private let compact: Compact
    private let expanded: Expanded

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchScreenConfiguration) private var screenConfiguration
    @State private var isHovered = false
    @State private var hoverExpanded = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var focusContext = NotchFocusContext()

    public init(
        style: NotchStyle = .contour,
        isExpanded: Binding<Bool>,
        configuration: NotchConfiguration? = nil,
        motion: NotchMotion = .spring,
        hoverOpens: Bool = true,
        accessibilityLabels: NotchAccessibilityLabels = NotchAccessibilityLabels(),
        @ViewBuilder compact: () -> Compact,
        @ViewBuilder expanded: () -> Expanded
    ) {
        self.style = style
        self._isExpanded = isExpanded
        self.configuration = configuration ?? NotchConfiguration()
        self.motion = motion
        self.hoverOpens = hoverOpens
        self.accessibilityLabels = accessibilityLabels
        self.compact = compact()
        self.expanded = expanded()
    }

    private var geometry: NotchConfiguration { screenConfiguration ?? configuration }
    private var size: CGSize { geometry.size(expanded: isExpanded) }
    private var silhouette: NotchSilhouette {
        NotchSilhouette(
            style: style,
            top: isExpanded ? geometry.expandedTopRadius : geometry.collapsedTopRadius,
            bottom: isExpanded ? geometry.expandedBottomRadius : geometry.collapsedBottomRadius
        )
    }

    public var body: some View {
        ZStack(alignment: .top) {
            surface
            if isExpanded {
                expanded
                    .padding(
                        EdgeInsets(
                            top: geometry.contentInsets.top,
                            leading: geometry.contentInsets.leading,
                            bottom: geometry.contentInsets.bottom,
                            trailing: geometry.contentInsets.trailing
                        )
                    )
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.96, anchor: .top)))
                    .overlay(alignment: .topTrailing) {
                        let insets = silhouette.collapseButtonInsets(in: size)
                        let buttonSize = NotchSilhouette.collapseButtonSize
                        Button(action: collapse) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: buttonSize, height: buttonSize)
                                .background(.white.opacity(0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help(accessibilityLabels.collapse)
                        .accessibilityLabel(accessibilityLabels.collapse)
                        .padding(.top, insets.top)
                        .padding(.trailing, insets.trailing)
                    }
                    .onExitCommand(perform: collapse)
            } else {
                Button {
                    hoverTask?.cancel()
                    hoverExpanded = false
                    isExpanded = true
                } label: {
                    compact
                        .padding(.horizontal, 16)
                        .frame(width: size.width, height: size.height)
                        .contentShape(silhouette)
                }
                .buttonStyle(.plain)
                .help(accessibilityLabels.expandHelp)
                .accessibilityHint(accessibilityLabels.expandHint)
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(NotchFocusReader(context: focusContext).accessibilityHidden(true))
        .clipShape(silhouette)
        .contentShape(silhouette)
        .shadow(color: .black.opacity(style == .glass ? 0.24 : 0.3), radius: isExpanded ? 22 : 8, y: 8)
        .scaleEffect(
            x: !isExpanded && isHovered && !reduceMotion ? 1.03 : 1,
            y: !isExpanded && isHovered && !reduceMotion ? 1.04 : 1,
            anchor: .top
        )
        .foregroundStyle(.white)
        .colorScheme(.dark)
        .animation(motion.animation(expanding: isExpanded, reduceMotion: reduceMotion), value: isExpanded)
        .animation(motion.animation(expanding: isExpanded, reduceMotion: reduceMotion), value: style)
        .animation(motion.animation(expanding: isExpanded, reduceMotion: reduceMotion), value: geometry)
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.8), value: isHovered
        )
        .onHover(perform: hover)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                hoverTask?.cancel()
                hoverExpanded = false
            }
        }
        .onChange(of: hoverOpens) { _, enabled in
            if !enabled {
                hoverTask?.cancel()
                hoverExpanded = false
            }
        }
        .onDisappear { hoverTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isExpanded ? accessibilityLabels.expanded : accessibilityLabels.collapsed)
    }

    @ViewBuilder private var surface: some View {
        if style == .glass {
            silhouette.fill(.ultraThinMaterial)
                .overlay(silhouette.fill(Color(red: 0.09, green: 0.11, blue: 0.16).opacity(0.63)))
                .overlay(silhouette.strokeBorderCompatibility(.white.opacity(0.16), lineWidth: 1))
        } else if style == .contour {
            silhouette.fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.012, green: 0.014, blue: 0.022), Color(red: 0.040, green: 0.045, blue: 0.075),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                silhouette.strokeBorderCompatibility(
                    Color(red: 0.48, green: 0.54, blue: 0.86).opacity(0.16), lineWidth: 1
                ))
        } else {
            silhouette.fill(Color(red: 0.055, green: 0.06, blue: 0.075))
                .overlay(silhouette.strokeBorderCompatibility(.white.opacity(0.12), lineWidth: 1))
        }
    }

    private func collapse() {
        hoverTask?.cancel()
        hoverExpanded = false
        isExpanded = false
    }

    private func hover(_ inside: Bool) {
        isHovered = inside
        hoverTask?.cancel()
        guard hoverOpens else { return }
        if inside && !isExpanded {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, isHovered, !isExpanded else { return }
                hoverExpanded = true
                isExpanded = true
            }
        } else if !inside && hoverExpanded {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, !isHovered else { return }
                hoverExpanded = false
                guard !focusContext.ownsKeyboardFocus else { return }
                isExpanded = false
            }
        }
    }
}

@MainActor
private final class NotchFocusContext {
    weak var marker: NSView?

    var ownsKeyboardFocus: Bool {
        guard let marker, let window = marker.window,
            let responder = window.firstResponder as? NSView,
            responder.window === window
        else { return false }
        let focusedView: NSView
        if let editor = responder as? NSTextView, editor.isFieldEditor,
            let owner = editor.delegate as? NSView, owner.window === window
        {
            focusedView = owner
        } else {
            focusedView = responder
        }
        guard focusedView !== marker, !marker.isDescendant(of: focusedView),
            !focusedView.isHiddenOrHasHiddenAncestor
        else { return false }
        let focusedBounds = focusedView.convert(focusedView.bounds, to: marker)
        let overlap = marker.bounds.intersection(focusedBounds)
        return !overlap.isNull && overlap.width > 0 && overlap.height > 0
    }
}

private struct NotchFocusReader: NSViewRepresentable {
    let context: NotchFocusContext

    func makeNSView(context: Context) -> NotchFocusMarker {
        let view = NotchFocusMarker()
        view.setAccessibilityElement(false)
        self.context.marker = view
        return view
    }

    func updateNSView(_ nsView: NotchFocusMarker, context: Context) {
        self.context.marker = nsView
    }
}

private final class NotchFocusMarker: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Shared shape dispatch ensures inline rendering and overlay hit regions agree.
struct NotchSilhouette: Shape {
    var style: NotchStyle
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set {
            top = newValue.first
            bottom = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch style {
        case .contour, .glass:
            ContourNotchShape(top: top, bottom: bottom).path(in: rect)
        case .capsule:
            RoundedRectangle(cornerRadius: min(rect.height / 2, max(bottom, 18)), style: .continuous).path(in: rect)
        }
    }

    static let collapseButtonSize: CGFloat = 28

    func collapseButtonInsets(in size: CGSize) -> (top: CGFloat, trailing: CGFloat) {
        let topInset = min(12, max(0, (size.height - Self.collapseButtonSize) / 2))
        let centered = max(0, (size.width - Self.collapseButtonSize) / 2)
        let preferred = min(14, centered)
        let outline = path(in: CGRect(origin: .zero, size: size))

        // The silhouette is symmetric and gets no narrower between these two
        // heights than at either endpoint. Keep the button inside both edges.
        func fits(_ trailing: CGFloat) -> Bool {
            let x = size.width - trailing + 2
            return outline.contains(CGPoint(x: x, y: topInset))
                && outline.contains(CGPoint(x: x, y: topInset + Self.collapseButtonSize))
        }
        if fits(preferred) { return (topInset, preferred) }
        guard fits(centered) else { return (topInset, centered) }

        var lower = preferred
        var upper = centered
        for _ in 0..<12 {
            guard upper - lower > 0.25 else { break }
            let middle = (lower + upper) / 2
            if fits(middle) { upper = middle } else { lower = middle }
        }
        return (topInset, upper)
    }

    func strokeBorderCompatibility(_ color: Color, lineWidth: CGFloat) -> some View {
        stroke(color, lineWidth: lineWidth)
    }
}

private struct NotchScreenConfigurationKey: EnvironmentKey {
    static let defaultValue: NotchConfiguration? = nil
}

extension EnvironmentValues {
    var notchScreenConfiguration: NotchConfiguration? {
        get { self[NotchScreenConfigurationKey.self] }
        set { self[NotchScreenConfigurationKey.self] = newValue }
    }
}
