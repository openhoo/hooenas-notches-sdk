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

    /// The expanded area available to your content, in points, after applying the insets.
    public var expandedContentSize: CGSize {
        CGSize(
            width: max(0, expandedSize.width - contentInsets.leading - contentInsets.trailing),
            height: max(0, expandedSize.height - contentInsets.top - contentInsets.bottom)
        )
    }

    /// Fit the requested geometry to a preview, screen or other bounded region.
    /// With camera metrics, reserve space around the housing before applying the bounds.
    /// Insets shrink when needed to retain content space, keeping camera clearance first.
    public func fitting(
        in maximumSize: CGSize,
        cameraHousingWidth: CGFloat = 0,
        safeAreaHeight: CGFloat = 0
    ) -> Self {
        let adjusted = accommodating(cameraHousingWidth: cameraHousingWidth, safeAreaHeight: safeAreaHeight)
        func fit(_ size: CGSize) -> CGSize {
            CGSize(
                width: maximumSize.width.isFinite ? min(size.width, max(0, maximumSize.width)) : size.width,
                height: maximumSize.height.isFinite ? min(size.height, max(0, maximumSize.height)) : size.height
            )
        }
        let closed = fit(adjusted.collapsedSize)
        let open = fit(adjusted.expandedSize)
        let insets = adjusted.contentInsets

        let horizontalBudget = max(0, open.width - 44)
        var leading = insets.leading
        var trailing = insets.trailing
        if leading > horizontalBudget || trailing > horizontalBudget - leading {
            let scale = max(leading, trailing)
            let fraction = (leading / scale) / (leading / scale + trailing / scale)
            leading = horizontalBudget * fraction
            trailing = horizontalBudget - leading
        }

        let cameraClearance = automaticallyPadsCamera ? min(open.height, Self.cameraClearance(safeAreaHeight)) : 0
        let verticalBudget = open.height - min(24, open.height - cameraClearance)
        let top = min(verticalBudget, insets.top)
        let bottom = min(verticalBudget - top, insets.bottom)
        return Self(
            copying: adjusted, collapsedSize: closed, expandedSize: open,
            contentInsets: NotchContentInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
        )
    }

    /// Leave room for compact leading/trailing controls around a physical camera housing.
    /// The extra 56 points on each side keep the default padded content out of the camera area.
    public func accommodating(cameraHousingWidth: CGFloat, safeAreaHeight: CGFloat) -> Self {
        let cameraWidth = cameraHousingWidth.isFinite ? max(0, cameraHousingWidth) : 0
        let safeHeight = safeAreaHeight.isFinite ? max(0, safeAreaHeight) : 0
        let topInset =
            automaticallyPadsCamera ? max(contentInsets.top, Self.cameraClearance(safeHeight)) : contentInsets.top
        let closed = CGSize(
            width: cameraWidth > 0 ? max(collapsedSize.width, cameraWidth + 112) : collapsedSize.width,
            height: max(collapsedSize.height, safeHeight)
        )
        return Self(
            copying: self, collapsedSize: closed,
            expandedSize: CGSize(
                width: max(expandedSize.width, closed.width),
                height: max(expandedSize.height, closed.height)
            ),
            contentInsets: NotchContentInsets(
                top: topInset, leading: contentInsets.leading,
                bottom: contentInsets.bottom, trailing: contentInsets.trailing
            )
        )
    }

    private init(copying source: Self, collapsedSize: CGSize, expandedSize: CGSize, contentInsets: NotchContentInsets) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        collapsedTopRadius = source.collapsedTopRadius
        collapsedBottomRadius = source.collapsedBottomRadius
        expandedTopRadius = source.expandedTopRadius
        expandedBottomRadius = source.expandedBottomRadius
        self.contentInsets = contentInsets
        automaticallyPadsCamera = source.automaticallyPadsCamera
    }

    private static func cameraClearance(_ height: CGFloat) -> CGFloat {
        height.isFinite && height > 0 ? height + 12 : 0
    }

    private static func valid(_ value: CGFloat, fallback: CGFloat, minimum: CGFloat) -> CGFloat {
        value.isFinite ? max(minimum, value) : fallback
    }
}

/// Localizable descriptions for the built-in disclosure and its accessibility state.
public struct NotchAccessibilityLabels: Equatable, Sendable {
    public var expandHelp: String
    public var expandHint: String
    public var collapse: String
    public var expanded: String
    public var collapsed: String

    public init(
        expandHelp: String = "Expand notch",
        expandHint: String = "Opens the notch controls",
        collapse: String = "Collapse notch",
        expanded: String = "Expanded",
        collapsed: String = "Collapsed"
    ) {
        self.expandHelp = expandHelp
        self.expandHint = expandHint
        self.collapse = collapse
        self.expanded = expanded
        self.collapsed = collapsed
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
