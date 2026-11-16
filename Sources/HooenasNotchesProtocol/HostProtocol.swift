// Copyright 2026 Hooenas Notches contributors. Licensed under FSL-1.1-MIT.
import Foundation

public enum HostCommand: String, Codable, Sendable {
    case show, update, hide, quit
}

public enum HostNotchStyle: String, Codable, Sendable {
    case contour, capsule, glass
}

public enum HostNotchMotion: String, Codable, Sendable {
    case spring, gentle, snappy
}

public enum HostNotchActivity: String, Codable, Sendable {
    case idle, working, listening, success
}

public struct HostNotchAction: Codable, Equatable, Sendable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// The complete state returned by the host. Progress is always encoded, including null.
public struct HostNotchState: Codable, Equatable, Sendable {
    public var style: HostNotchStyle
    public var motion: HostNotchMotion
    public var expanded: Bool
    public var title: String
    public var subtitle: String
    public var activity: HostNotchActivity
    public var progress: Double?
    public var actions: [HostNotchAction]

    public init(
        style: HostNotchStyle = .contour,
        motion: HostNotchMotion = .spring,
        expanded: Bool = false,
        title: String = "Hooenas Notches",
        subtitle: String = "Bereit, wenn du es bist.",
        activity: HostNotchActivity = .idle,
        progress: Double? = nil,
        actions: [HostNotchAction] = []
    ) {
        self.style = style
        self.motion = motion
        self.expanded = expanded
        self.title = title
        self.subtitle = subtitle
        self.activity = activity
        self.progress = progress
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case style, motion, expanded, title, subtitle, activity, progress, actions
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(motion, forKey: .motion)
        try container.encode(expanded, forKey: .expanded)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(activity, forKey: .activity)
        try container.encode(progress, forKey: .progress)
        try container.encode(actions, forKey: .actions)
    }

    public func applying(_ patch: HostNotchStatePatch?) throws -> Self {
        guard let patch else { return self }
        var next = self
        if let value = patch.style { next.style = value }
        if let value = patch.motion { next.motion = value }
        if let value = patch.expanded { next.expanded = value }
        if let value = patch.title { next.title = value }
        if let value = patch.subtitle { next.subtitle = value }
        if let value = patch.activity { next.activity = value }
        if patch.hasProgress { next.progress = patch.progress }
        if let value = patch.actions { next.actions = value }
        try next.validate()
        return next
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 512 else {
            throw HostProtocolError("invalid_state", "title must contain between 1 and 512 characters.")
        }
        guard subtitle.count <= 2_048 else {
            throw HostProtocolError("invalid_state", "subtitle must contain at most 2048 characters.")
        }
        if let progress, !progress.isFinite || !(0...1).contains(progress) {
            throw HostProtocolError("invalid_state", "progress must be null or a finite number between 0 and 1.")
        }
        guard actions.count <= 4 else {
            throw HostProtocolError("invalid_state", "A notch supports at most four actions.")
        }
        var ids: Set<String> = []
        for action in actions {
            guard Self.validIdentifier(action.id, maximum: 64) else {
                throw HostProtocolError("invalid_state", "Action ids must contain 1 to 64 non-control characters.")
            }
            guard !action.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action.label.count <= 64 else {
                throw HostProtocolError("invalid_state", "Action labels must contain between 1 and 64 characters.")
            }
            guard ids.insert(action.id).inserted else {
                throw HostProtocolError("invalid_state", "Action ids must be unique.")
            }
        }
        // A character can contain an arbitrarily large number of combining
        // scalars. Bound the complete persisted state across separate patches,
        // leaving room for the response envelope and a validated request id.
        guard try JSONEncoder().encode(self).count <= HostLineFramer.maximumLineBytes - 2_048 else {
            throw HostProtocolError("invalid_state", "The complete state is too large for a host response.")
        }
    }

    static func validIdentifier(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.count <= maximum
            && value.utf8.count <= maximum * 4
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

/// Missing fields preserve the previous value. An explicit progress:null clears progress.
public struct HostNotchStatePatch: Codable, Equatable, Sendable {
    public var style: HostNotchStyle?
    public var motion: HostNotchMotion?
    public var expanded: Bool?
    public var title: String?
    public var subtitle: String?
    public var activity: HostNotchActivity?
    public var progress: Double?
    public var hasProgress: Bool
    public var actions: [HostNotchAction]?

    public init(
        style: HostNotchStyle? = nil,
        motion: HostNotchMotion? = nil,
        expanded: Bool? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        activity: HostNotchActivity? = nil,
        progress: Double? = nil,
        clearProgress: Bool = false,
        actions: [HostNotchAction]? = nil
    ) {
        self.style = style
        self.motion = motion
        self.expanded = expanded
        self.title = title
        self.subtitle = subtitle
        self.activity = activity
        self.progress = progress
        self.hasProgress = progress != nil || clearProgress
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case style, motion, expanded, title, subtitle, activity, progress, actions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(HostNotchStyle.self, forKey: .style)
        motion = try container.decodeIfPresent(HostNotchMotion.self, forKey: .motion)
        expanded = try container.decodeIfPresent(Bool.self, forKey: .expanded)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        activity = try container.decodeIfPresent(HostNotchActivity.self, forKey: .activity)
        hasProgress = container.contains(.progress)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        actions = try container.decodeIfPresent([HostNotchAction].self, forKey: .actions)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(motion, forKey: .motion)
        try container.encodeIfPresent(expanded, forKey: .expanded)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(activity, forKey: .activity)
        if hasProgress { try container.encode(progress, forKey: .progress) }
        try container.encodeIfPresent(actions, forKey: .actions)
    }
}

public struct HostRequest: Codable, Equatable, Sendable {
    public var id: String
    public var command: HostCommand
    public var state: HostNotchStatePatch?

    public init(id: String, command: HostCommand, state: HostNotchStatePatch? = nil) {
        self.id = id
        self.command = command
        self.state = state
    }

    public func validate() throws {
        guard HostNotchState.validIdentifier(id, maximum: 128) else {
            throw HostProtocolError("invalid_request", "id must contain 1 to 128 non-control characters.")
        }
        if command == .hide || command == .quit, state != nil {
            throw HostProtocolError("invalid_request", "hide and quit do not accept state.")
        }
    }

    /// Recover only a bounded, valid correlation id when another field is invalid.
    public static func correlationID(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String,
            HostNotchState.validIdentifier(id, maximum: 128)
        else { return nil }
        return id
    }
}

public struct HostProtocolError: Error, LocalizedError, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct HostEvent: Codable, Equatable, Sendable {
    public var event: String
    public var protocolVersion: Int?
    public var id: String?
    public var ok: Bool?
    public var state: HostNotchState?
    public var visible: Bool?
    public var code: String?
    public var message: String?
    public var actionId: String?

    public static var ready: Self { Self(event: "ready", protocolVersion: 1) }

    public static func result(id: String, state: HostNotchState, visible: Bool) -> Self {
        Self(event: "result", id: id, ok: true, state: state, visible: visible)
    }

    public static func error(id: String? = nil, _ error: HostProtocolError) -> Self {
        Self(event: "error", id: id, code: error.code, message: error.message)
    }

    public static func action(_ id: String) -> Self { Self(event: "action", actionId: id) }

    public static func changed(state: HostNotchState, visible: Bool) -> Self {
        Self(event: "state", state: state, visible: visible)
    }
}

/// A platform independent state reducer. Invalid requests never partially alter state.
public struct HostSession: Sendable {
    public private(set) var state = HostNotchState()
    public private(set) var visible = false
    public private(set) var terminated = false

    public init() {}

    @discardableResult
    public mutating func apply(_ request: HostRequest) throws -> HostEvent {
        guard !terminated else { throw HostProtocolError("session_closed", "The host session has ended.") }
        try request.validate()
        let next = try state.applying(request.state)
        state = next
        switch request.command {
        case .show: visible = true
        case .update: break
        case .hide: visible = false
        case .quit:
            visible = false
            terminated = true
        }
        return .result(id: request.id, state: state, visible: visible)
    }

    public mutating func setExpanded(_ expanded: Bool) {
        state.expanded = expanded
    }
}

public enum HostInputFrame: Sendable, Equatable {
    case line(Data)
    case lineTooLong
}

/// Splits arbitrary stdin chunks without assuming UTF-8 or JSON boundaries match reads.
public struct HostLineFramer: Sendable {
    public static let maximumLineBytes = 65_536
    private var buffer = Data()
    private var discarding = false

    public init() {}

    public mutating func append(_ data: Data) -> [HostInputFrame] {
        var frames: [HostInputFrame] = []
        for byte in data {
            if byte == 10 {
                if discarding {
                    frames.append(.lineTooLong)
                } else if !buffer.isEmpty {
                    if buffer.last == 13 { buffer.removeLast() }
                    if !buffer.isEmpty { frames.append(.line(buffer)) }
                }
                buffer.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                if buffer.count == Self.maximumLineBytes {
                    buffer.removeAll(keepingCapacity: true)
                    discarding = true
                } else {
                    buffer.append(byte)
                }
            }
        }
        return frames
    }

    public mutating func finish() -> [HostInputFrame] {
        defer {
            buffer.removeAll()
            discarding = false
        }
        if discarding { return [.lineTooLong] }
        if buffer.isEmpty { return [] }
        if buffer.last == 13 { buffer.removeLast() }
        return buffer.isEmpty ? [] : [.line(buffer)]
    }
}
