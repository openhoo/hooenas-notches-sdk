// Hooenas Notches SDK. See LICENSE and THIRD_PARTY_NOTICES.md.
import AppKit
import SwiftUI
import HooenasNotches

@main
struct HooenasNotchesShowcase: App {
    @StateObject private var model = ShowcaseModel()

    var body: some Scene {
        WindowGroup("Hooenas Notches SDK") {
            ShowcaseWindow(model: model)
                .frame(width: 800, height: 610)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.hide()
                }
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
private final class ShowcaseModel: ObservableObject {
    @Published var style: NotchStyle = .contour {
        didSet { if overlayVisible { present() } }
    }
    @Published var motion: NotchMotion = .spring
    @Published var activity: NotchActivity = .working
    @Published var expanded = false
    @Published var progress = 0.64
    @Published private(set) var overlayVisible = false
    private let panel = NotchPanelController()

    func present() {
        panel.show(content: ShowcaseNotch(model: self), style: style, isExpanded: { [weak self] in
            self?.expanded ?? false
        })
        overlayVisible = panel.isVisible
    }

    func hide() {
        panel.hide()
        overlayVisible = false
    }
}

private struct ShowcaseWindow: View {
    @ObservedObject var model: ShowcaseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Hooenas Notches SDK").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Three surfaces. Your content. Native motion.")
                    .foregroundStyle(.secondary)
            }
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.25), Color.teal.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                ShowcaseNotch(model: model)
            }
            .frame(height: 280)
            .overlay(alignment: .bottomLeading) {
                Label("Inline SwiftUI preview", systemImage: "rectangle.inset.filled")
                    .font(.caption).foregroundStyle(.secondary).padding(18)
            }
            HStack(spacing: 18) {
                Picker("Surface", selection: $model.style) {
                    ForEach(NotchStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Motion", selection: $model.motion) {
                    ForEach(NotchMotion.allCases) { Text($0.title).tag($0) }
                }
            }
            HStack(spacing: 18) {
                Picker("Activity", selection: $model.activity) {
                    ForEach(NotchActivity.allCases) { Text($0.title).tag($0) }
                }
                Slider(value: $model.progress, in: 0...1) {
                    Text("Progress")
                }
            }
            HStack {
                Button(model.expanded ? "Collapse" : "Expand") { model.expanded.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                Spacer()
                if model.overlayVisible {
                    Button("Hide screen overlay", action: model.hide)
                } else {
                    Button("Show screen overlay", action: model.present)
                        .buttonStyle(.borderedProminent)
                }
            }
            Text("Hover or click to expand. The screen overlay follows the physical top edge and leaves room for the camera.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(32)
        .background(Color(red: 0.035, green: 0.04, blue: 0.06))
    }
}

private struct ShowcaseNotch: View {
    @ObservedObject var model: ShowcaseModel

    var body: some View {
        HooenasNotch(style: model.style, isExpanded: $model.expanded, motion: model.motion) {
            HStack {
                NotchActivityIndicator(activity: model.activity, tint: .mint)
                Spacer()
                Text("\(Int(model.progress * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.mint)
            }
        } expanded: {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.doc.fill")
                        .font(.system(size: 21)).foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Making room for your ideas").font(.system(size: 17, weight: .semibold))
                        Text("Custom SwiftUI content, in every surface")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    NotchActivityIndicator(activity: model.activity, tint: .mint)
                }
                ProgressView(value: model.progress).tint(.mint)
                HStack {
                    Text(model.style.title + " · " + model.motion.title)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Button("Finish") { model.progress = 1; model.activity = .success }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}
