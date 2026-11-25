// Hooenas Notches. See LICENSE and THIRD_PARTY_NOTICES.md.
import SwiftUI

/// Gives compact content two equal slots separated by the physical camera housing.
/// Put short, independently readable content in each slot. The notch itself remains one button.
@MainActor
public struct NotchCompactWings<Leading: View, Trailing: View>: View {
    @Environment(\.notchCameraHousingWidth) private var screenCameraHousingWidth
    private let cameraHousingWidth: CGFloat?
    private let leading: Leading
    private let trailing: Trailing

    /// The override is useful for previews that simulate a camera housing.
    public init(
        cameraHousingWidth: CGFloat? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.cameraHousingWidth = cameraHousingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        GeometryReader { proxy in
            let widths = Self.widths(
                in: proxy.size.width, cameraHousingWidth: cameraHousingWidth ?? screenCameraHousingWidth)
            HStack(spacing: widths.gap) {
                leading.frame(width: widths.wing, height: proxy.size.height, alignment: .leading).clipped()
                trailing.frame(width: widths.wing, height: proxy.size.height, alignment: .trailing).clipped()
            }
        }
    }

    static func widths(in available: CGFloat, cameraHousingWidth: CGFloat) -> (wing: CGFloat, gap: CGFloat) {
        let width = available.isFinite ? max(0, available) : 0
        let camera = cameraHousingWidth.isFinite ? max(0, cameraHousingWidth) : 0
        let gap = min(width, max(12, camera + 12))
        return ((width - gap) / 2, gap)
    }
}

private struct NotchCameraHousingWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var notchCameraHousingWidth: CGFloat {
        get { self[NotchCameraHousingWidthKey.self] }
        set { self[NotchCameraHousingWidthKey.self] = newValue }
    }
}
