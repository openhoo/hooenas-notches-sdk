// Hooenas Notches. See LICENSE and THIRD_PARTY_NOTICES.md.
import SwiftUI

/// The visual language of the notch. Each preset uses the same content API.
public enum NotchStyle: String, CaseIterable, Identifiable, Sendable {
    case contour
    case capsule
    case glass

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .contour: "Contour"
        case .capsule: "Capsule"
        case .glass: "Liquid Glass"
        }
    }

    /// Every skin attaches to the physical top edge, including displays with a camera housing.
    public var topInset: CGFloat { 0 }
}

/// A consistent set of native spring curves for every notch preset.
public enum NotchMotion: String, CaseIterable, Identifiable, Sendable {
    case spring
    case gentle
    case snappy

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    public func animation(expanding: Bool = true, reduceMotion: Bool = false) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        switch self {
        case .spring:
            return .spring(response: expanding ? 0.46 : 0.36, dampingFraction: expanding ? 0.86 : 0.98)
        case .gentle:
            return .spring(response: 0.64, dampingFraction: 0.95)
        case .snappy:
            return .spring(response: 0.30, dampingFraction: 0.82)
        }
    }
}

/// Default breathing room around expanded content. Compact content keeps its own layout.
public struct NotchContentInsets: Equatable, Sendable {
    public let top: CGFloat
    public let leading: CGFloat
    public let bottom: CGFloat
    public let trailing: CGFloat

    public init(top: CGFloat = 44, leading: CGFloat = 34, bottom: CGFloat = 20, trailing: CGFloat = 34) {
        self.top = Self.normalized(top, fallback: 44)
        self.leading = Self.normalized(leading, fallback: 34)
        self.bottom = Self.normalized(bottom, fallback: 20)
        self.trailing = Self.normalized(trailing, fallback: 34)
    }

    private static func normalized(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : fallback
    }
}

/// Geometry shared by the inline view and the screen overlay.
/// Invalid or nonfinite sizes are normalized at initialization.
public struct NotchConfiguration: Equatable, Sendable {
    public let collapsedSize: CGSize
    public let expandedSize: CGSize
    public let collapsedTopRadius: CGFloat
    public let collapsedBottomRadius: CGFloat
    public let expandedTopRadius: CGFloat
    public let expandedBottomRadius: CGFloat
    public let contentInsets: NotchContentInsets
    /// Raise expanded content below a real camera housing when shown as a screen overlay.
    public let automaticallyPadsCamera: Bool

    public init(
        collapsedSize: CGSize = CGSize(width: 204, height: 32),
        expandedSize: CGSize = CGSize(width: 640, height: 219),
        collapsedTopRadius: CGFloat = 8,
        collapsedBottomRadius: CGFloat = 16,
        expandedTopRadius: CGFloat = 22,
        expandedBottomRadius: CGFloat = 28,
        contentInsets: NotchContentInsets = NotchContentInsets(),
        automaticallyPadsCamera: Bool = true
    ) {
        let closed = CGSize(
            width: Self.valid(collapsedSize.width, fallback: 204, minimum: 80),
            height: Self.valid(collapsedSize.height, fallback: 32, minimum: 24)
        )
        self.collapsedSize = closed
        self.expandedSize = CGSize(
            width: max(closed.width, Self.valid(expandedSize.width, fallback: 640, minimum: 160)),
            height: max(closed.height, Self.valid(expandedSize.height, fallback: 219, minimum: 80))
        )
        self.collapsedTopRadius = Self.valid(collapsedTopRadius, fallback: 8, minimum: 0)
        self.collapsedBottomRadius = Self.valid(collapsedBottomRadius, fallback: 16, minimum: 0)
        self.expandedTopRadius = Self.valid(expandedTopRadius, fallback: 22, minimum: 0)
        self.expandedBottomRadius = Self.valid(expandedBottomRadius, fallback: 28, minimum: 0)
        self.contentInsets = contentInsets
        self.automaticallyPadsCamera = automaticallyPadsCamera
    }

    public func size(expanded: Bool) -> CGSize { expanded ? expandedSize : collapsedSize }

    /// Leave room for compact leading/trailing controls around a physical camera housing.
    /// The extra 56 points on each side keep the default padded content out of the camera area.
    public func accommodating(cameraHousingWidth: CGFloat, safeAreaHeight: CGFloat) -> Self {
        let topInset = automaticallyPadsCamera && safeAreaHeight.isFinite && safeAreaHeight > 0
            ? max(contentInsets.top, safeAreaHeight + 12)
            : contentInsets.top
        return Self(
            collapsedSize: CGSize(
                width: max(collapsedSize.width, cameraHousingWidth + 112),
                height: max(collapsedSize.height, safeAreaHeight)
            ),
            expandedSize: expandedSize,
            collapsedTopRadius: collapsedTopRadius,
            collapsedBottomRadius: collapsedBottomRadius,
            expandedTopRadius: expandedTopRadius,
            expandedBottomRadius: expandedBottomRadius,
            contentInsets: NotchContentInsets(
                top: topInset, leading: contentInsets.leading,
                bottom: contentInsets.bottom, trailing: contentInsets.trailing
            ),
            automaticallyPadsCamera: automaticallyPadsCamera
        )
    }

    private static func valid(_ value: CGFloat, fallback: CGFloat, minimum: CGFloat) -> CGFloat {
        value.isFinite ? max(minimum, value) : fallback
    }
}

/// Status data is independent of whichever notch style hosts it.
public enum NotchActivity: String, CaseIterable, Identifiable, Sendable {
    case idle
    case working
    case listening
    case success

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .idle: "Ready"
        case .working: "Working"
        case .listening: "Listening"
        case .success: "Complete"
        }
    }
}
