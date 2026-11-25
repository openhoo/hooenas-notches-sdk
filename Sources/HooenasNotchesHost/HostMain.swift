// Copyright 2026 Hooenas Notches contributors. Licensed under FSL-1.1-MIT.
import AppKit
import Darwin
import HooenasNotches
import HooenasNotchesProtocol
import SwiftUI

@main
enum HooenasNotchesHostMain {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--version"] {
            print("hooenas-notches-host 0.2.0 (protocol 1)")
            return
        }
        if arguments == ["--help"] {
            print(
                """
                Usage: hooenas-notches-host [--stdio]
                Native macOS notch host. Reads JSON Lines from stdin and writes events to stdout.
                Commands: show, update, hide, quit. See docs/host-protocol.md.
                """)
            return
        }
        guard arguments.isEmpty || arguments == ["--stdio"] else {
            FileHandle.standardError.write(Data("Unknown arguments. Use --help.\n".utf8))
            exit(2)
        }
        // A closed parent stdout pipe should take the normal cleanup path.
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = HostApplication()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

private enum Input: Sendable {
    case frame(HostInputFrame)
    case readError
    case end
}

@MainActor
private final class HostApplication: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var state = HostNotchState()
    private var session = HostSession()
    private var panel = NotchPanelController()
    private var inputTask: Task<Void, Never>?
    private let encoder = JSONEncoder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        emit(.ready)
        inputTask = Task.detached(priority: .userInitiated) { [weak self] in
            var framer = HostLineFramer()
            var bytes = [UInt8](repeating: 0, count: 4_096)
            // POSIX read returns available short pipe writes immediately.
            // Await each delivery so a fast writer is backpressured by the pipe
            // rather than an unbounded queue of pending UI requests.
            while !Task.isCancelled {
                let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                if count == 0 { break }
                if count < 0 {
                    if errno == EINTR { continue }
                    _ = await self?.receive(.readError)
                    return
                }
                for frame in framer.append(Data(bytes.prefix(count))) {
                    guard await self?.receive(.frame(frame)) == true else { return }
                }
            }
            guard !Task.isCancelled else { return }
            for frame in framer.finish() {
                guard await self?.receive(.frame(frame)) == true else { return }
            }
            _ = await self?.receive(.end)
        }
    }

    private func receive(_ input: Input) -> Bool {
        switch input {
        case .frame(.line(let data)): consume(data)
        case .frame(.lineTooLong):
            emit(.error(HostProtocolError("line_too_long", "A request must not exceed 65536 bytes.")))
        case .readError:
            emit(.error(HostProtocolError("input_error", "The host could not read stdin.")))
            panel.hide()
            NSApplication.shared.terminate(nil)
            return false
        case .end:
            panel.hide()
            NSApplication.shared.terminate(nil)
            return false
        }
        return !session.terminated
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputTask?.cancel()
        panel.hide()
    }

    private func consume(_ data: Data) {
        let requestID = HostRequest.correlationID(in: data)
        do {
            let request = try JSONDecoder().decode(HostRequest.self, from: data)
            let previous = state
            let result = try session.apply(request)
            state = session.state
            if session.visible {
                if !panel.isVisible || previous.style != state.style || previous.expandedSize != state.expandedSize {
                    showPanel()
                }
            } else {
                panel.hide()
            }
            emit(result)
            if session.terminated { NSApplication.shared.terminate(nil) }
        } catch let error as HostProtocolError {
            emit(.error(id: requestID, error))
        } catch {
            emit(
                .error(
                    id: requestID,
                    HostProtocolError(
                        "invalid_request", "Expected a JSON object with a valid id, command and optional state.")))
        }
    }

    private func showPanel() {
        panel.show(
            content: HostNotchContent(model: self),
            configuration: configuration,
            style: NotchStyle(rawValue: state.style.rawValue) ?? .contour,
            isExpanded: { [weak self] in self?.state.expanded ?? false }
        )
    }

    var configuration: NotchConfiguration {
        guard let size = state.expandedSize else { return NotchConfiguration() }
        return NotchConfiguration(expandedSize: CGSize(width: size.width, height: size.height))
    }

    func setExpanded(_ value: Bool) {
        guard value != session.state.expanded else { return }
        session.setExpanded(value)
        state = session.state
        emit(.changed(state: state, visible: session.visible))
    }

    func action(_ id: String) { emit(.action(id)) }

    private func emit(_ event: HostEvent) {
        do {
            var data = try encoder.encode(event)
            data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch {
            panel.hide()
            NSApplication.shared.terminate(nil)
        }
    }

}

private struct HostNotchContent: View {
    @ObservedObject var model: HostApplication

    private var tint: Color {
        switch model.state.activity {
        case .idle: .white.opacity(0.7)
        case .working: .indigo
        case .listening: .mint
        case .success: .green
        }
    }

    private var symbol: String {
        switch model.state.activity {
        case .idle: "sparkle"
        case .working: "sparkles"
        case .listening: "waveform"
        case .success: "checkmark"
        }
    }

    var body: some View {
        HooenasNotch(
            style: NotchStyle(rawValue: model.state.style.rawValue) ?? .contour,
            isExpanded: Binding(get: { model.state.expanded }, set: { model.setExpanded($0) }),
            configuration: model.configuration,
            motion: NotchMotion(rawValue: model.state.motion.rawValue) ?? .spring
        ) {
            NotchCompactWings {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            } trailing: {
                if model.state.progress != nil {
                    Text(model.state.progress ?? 0, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                } else {
                    Text(model.state.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.state.title)
            .accessibilityValue(
                model.state.progress?.formatted(.percent.precision(.fractionLength(0))) ?? model.state.subtitle)
        } expanded: {
            ScrollView {
                expandedContent.frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.top)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.state.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(model.state.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            if let progress = model.state.progress {
                HStack(spacing: 12) {
                    ProgressView(value: progress).tint(tint)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if !model.state.actions.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(model.state.actions, id: \.id) { action in
                        Button {
                            model.action(action.id)
                        } label: {
                            Text(action.label)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(.white.opacity(0.1), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}
