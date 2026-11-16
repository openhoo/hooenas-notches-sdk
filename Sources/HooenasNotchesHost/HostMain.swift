// Copyright 2026 Hooenas Notches contributors. Licensed under FSL-1.1-MIT.
import AppKit
import HooenasNotches
import HooenasNotchesProtocol
import Darwin
import SwiftUI

@main
enum HooenasNotchesHostMain {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--version"] {
            print("hooenas-notches-host 0.1.0 (protocol 1)")
            return
        }
        if arguments == ["--help"] {
            print("""
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
        let stream = Self.stdinStream()
        inputTask = Task { [weak self] in
            for await input in stream {
                guard let self else { return }
                switch input {
                case .frame(.line(let data)): consume(data)
                case .frame(.lineTooLong):
                    emit(.error(HostProtocolError("line_too_long", "A request must not exceed 65536 bytes.")))
                case .readError:
                    emit(.error(HostProtocolError("input_error", "The host could not read stdin.")))
                case .end:
                    panel.hide()
                    NSApplication.shared.terminate(nil)
                }
                if session.terminated { return }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputTask?.cancel()
        panel.hide()
    }

    private func consume(_ data: Data) {
        var requestID: String?
        do {
            let request = try JSONDecoder().decode(HostRequest.self, from: data)
            requestID = request.id
            let oldStyle = state.style
            let result = try session.apply(request)
            state = session.state
            if session.visible {
                if !panel.isVisible || oldStyle != state.style { showPanel() }
            } else {
                panel.hide()
            }
            emit(result)
            if session.terminated { NSApplication.shared.terminate(nil) }
        } catch let error as HostProtocolError {
            emit(.error(id: requestID, error))
        } catch {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let candidate = object?["id"] as? String
            if let candidate, candidate.count <= 128 { requestID = candidate }
            emit(.error(id: requestID, HostProtocolError("invalid_request", "Expected a JSON object with a valid id, command and optional state.")))
        }
    }

    private func showPanel() {
        panel.show(
            content: AnyView(HostNotchContent(model: self)),
            style: NotchStyle(rawValue: state.style.rawValue) ?? .contour,
            isExpanded: { [weak self] in self?.state.expanded ?? false }
        )
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

    private static func stdinStream() -> AsyncStream<Input> {
        AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var framer = HostLineFramer()
                var bytes = [UInt8](repeating: 0, count: 4_096)
                // Foundation's read(upToCount:) may try to fill its requested buffer on
                // a pipe. POSIX read returns each available short write immediately,
                // which is essential while the parent keeps stdin open between requests.
                while true {
                    let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                    if count == 0 { break }
                    if count < 0 {
                        if errno == EINTR { continue }
                        continuation.yield(.readError)
                        break
                    }
                    for frame in framer.append(Data(bytes.prefix(count))) {
                        continuation.yield(.frame(frame))
                    }
                }
                for frame in framer.finish() { continuation.yield(.frame(frame)) }
                continuation.yield(.end)
                continuation.finish()
            }
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
            motion: NotchMotion(rawValue: model.state.motion.rawValue) ?? .spring
        ) {
            HStack(spacing: 9) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(model.state.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if model.state.progress != nil {
                    Circle().trim(from: 0, to: model.state.progress ?? 0)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 11, height: 11)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
        } expanded: {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.state.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(model.state.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                    }
                    Spacer(minLength: 28)
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
                    HStack(spacing: 8) {
                        ForEach(model.state.actions, id: \.id) { action in
                            Button(action.label) { model.action(action.id) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        }
    }
}
