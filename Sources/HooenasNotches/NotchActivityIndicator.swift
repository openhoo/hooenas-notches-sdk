// Hooenas Notches. See LICENSE and THIRD_PARTY_NOTICES.md.
import SwiftUI

/// A small, dependency-free status animation suitable for either content slot.
public struct NotchActivityIndicator: View {
    public var activity: NotchActivity
    public var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(activity: NotchActivity = .working, tint: Color = .mint) {
        self.activity = activity
        self.tint = tint
    }

    public var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 24, paused: reduceMotion || activity == .idle || activity == .success)
        ) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            Group {
                switch activity {
                case .idle:
                    Circle().fill(tint.opacity(0.7)).frame(width: 6, height: 6)
                case .success:
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                case .working:
                    ZStack {
                        ForEach(0..<8) { index in
                            Capsule()
                                .fill(
                                    tint.opacity(
                                        reduceMotion
                                            ? 0.8 : 0.22 + 0.78 * max(0, sin(phase * 6 - Double(index) * .pi / 4)))
                                )
                                .frame(width: 2, height: 4)
                                .offset(y: -5)
                                .rotationEffect(.degrees(Double(index) * 45))
                        }
                    }
                case .listening:
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Capsule().fill(tint)
                                .frame(
                                    width: 2,
                                    height: reduceMotion
                                        ? 9 : CGFloat(4 + 10 * abs(sin(phase * 4 + Double(index) * 0.8))))
                        }
                    }
                }
            }
            .frame(width: 18, height: 18)
        }
        .accessibilityLabel(activity.title)
    }
}
