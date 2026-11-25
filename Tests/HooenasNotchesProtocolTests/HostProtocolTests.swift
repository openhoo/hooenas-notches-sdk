import Foundation
import XCTest

@testable import HooenasNotchesProtocol

final class HostProtocolTests: XCTestCase {
    private func decode(_ json: String) throws -> HostRequest {
        try JSONDecoder().decode(HostRequest.self, from: Data(json.utf8))
    }

    func testPatchPreservesFieldsAndNullClearsProgress() throws {
        var session = HostSession()
        try session.apply(
            decode(#"{"id":"1","command":"show","state":{"title":"Upload","progress":0.4,"activity":"working"}}"#))
        try session.apply(decode(#"{"id":"2","command":"update","state":{"subtitle":"Noch einen Moment"}}"#))
        XCTAssertEqual(session.state.title, "Upload")
        XCTAssertEqual(session.state.progress, 0.4)
        XCTAssertEqual(session.state.activity, .working)
        try session.apply(decode(#"{"id":"3","command":"update","state":{"progress":null}}"#))
        XCTAssertNil(session.state.progress)
        XCTAssertEqual(session.state.subtitle, "Noch einen Moment")
    }

    func testInvalidPatchIsAtomic() throws {
        var session = HostSession()
        try session.apply(decode(#"{"id":"1","command":"show","state":{"title":"Original","progress":0.25}}"#))
        let before = session.state
        XCTAssertThrowsError(
            try session.apply(decode(#"{"id":"2","command":"update","state":{"title":"Changed","progress":1.1}}"#))
        ) { error in
            XCTAssertEqual((error as? HostProtocolError)?.code, "invalid_state")
        }
        XCTAssertEqual(session.state, before)
        XCTAssertTrue(session.visible)
    }

    func testExpandedSizeCanBeUpdatedPreservedAndReset() throws {
        var session = HostSession()
        let initial = HostNotchSize(width: 480, height: 275)
        let result = try session.apply(
            decode(#"{"id":"show","command":"show","state":{"expandedSize":{"width":480,"height":275}}}"#))
        XCTAssertEqual(result.state?.expandedSize, initial)
        XCTAssertEqual(HostEvent.ready.capabilities, ["expanded-size"])
        try session.apply(decode(#"{"id":"ordinary","command":"update","state":{"title":"A new title"}}"#))
        XCTAssertEqual(session.state.expandedSize, initial)
        try session.apply(decode(#"{"id":"reset","command":"update","state":{"expandedSize":null}}"#))
        XCTAssertNil(session.state.expandedSize)
        XCTAssertEqual(session.state.title, "A new title")
    }

    func testInvalidExpandedSizeLeavesPreviousStateIntact() throws {
        var session = HostSession()
        try session.apply(
            .init(id: "show", command: .show, state: .init(expandedSize: HostNotchSize(width: 500, height: 220))))
        let before = session.state
        for size in [HostNotchSize(width: .infinity, height: 220), HostNotchSize(width: 500, height: 139)] {
            let patch = HostNotchStatePatch(title: "Should not persist", expandedSize: size)
            XCTAssertThrowsError(try session.apply(.init(id: "resize", command: .update, state: patch))) { error in
                XCTAssertEqual((error as? HostProtocolError)?.code, "invalid_state")
            }
            XCTAssertEqual(session.state, before)
        }
    }

    func testUpdateDoesNotDisplayHiddenPanel() throws {
        var session = HostSession()
        try session.apply(.init(id: "configure", command: .update, state: .init(style: .glass, title: "Configured")))
        XCTAssertFalse(session.visible)
        XCTAssertEqual(session.state.style, .glass)
        try session.apply(.init(id: "show", command: .show))
        XCTAssertTrue(session.visible)
        XCTAssertEqual(session.state.title, "Configured")
        try session.apply(.init(id: "hide", command: .hide))
        XCTAssertFalse(session.visible)
        XCTAssertEqual(session.state.title, "Configured")
    }

    func testQuitClosesSessionAndCannotBeReopened() throws {
        var session = HostSession()
        try session.apply(.init(id: "1", command: .show))
        let result = try session.apply(.init(id: "2", command: .quit))
        XCTAssertTrue(session.terminated)
        XCTAssertFalse(session.visible)
        XCTAssertEqual(result.visible, false)
        XCTAssertThrowsError(try session.apply(.init(id: "3", command: .show)))
    }

    func testHideCannotMutateState() throws {
        var session = HostSession()
        let before = session.state
        XCTAssertThrowsError(try session.apply(.init(id: "hide", command: .hide, state: .init(title: "Unexpected"))))
        XCTAssertEqual(session.state, before)
    }

    func testIdentifiersAndActionsAreValidated() throws {
        var session = HostSession()
        XCTAssertThrowsError(try session.apply(.init(id: "\n", command: .show)))
        XCTAssertThrowsError(
            try session.apply(
                .init(
                    id: "1", command: .show,
                    state: .init(actions: [
                        .init(id: "cancel", label: "Cancel"), .init(id: "cancel", label: "Again"),
                    ]))))
        XCTAssertThrowsError(try session.apply(.init(id: "2", command: .show, state: .init(title: "   "))))
    }

    func testInteractiveStateIsReturnedBySubsequentCommands() throws {
        var session = HostSession()
        session.setExpanded(true)
        let result = try session.apply(.init(id: "current", command: .update))
        XCTAssertEqual(result.state?.expanded, true)
    }

    func testUnknownCommandsAndInvalidFieldTypesAreRejected() {
        XCTAssertThrowsError(try decode(#"{"id":"1","command":"launch"}"#))
        XCTAssertThrowsError(try decode(#"{"id":"2","command":"show","state":{"expanded":"true"}}"#))
        XCTAssertThrowsError(try decode(#"{"id":"3","command":"show","state":{"style":"typo"}}"#))
    }

    func testEditingASwiftPatchEncodesBothAssignmentsAndExplicitResets() throws {
        var patch = HostNotchStatePatch()
        patch.progress = 0.5
        patch.expandedSize = .init(width: 400, height: 200)
        let assigned = try JSONDecoder().decode(HostNotchStatePatch.self, from: JSONEncoder().encode(patch))
        var state = try HostNotchState().applying(assigned)
        XCTAssertEqual(state.progress, 0.5)
        XCTAssertEqual(state.expandedSize, .init(width: 400, height: 200))
        patch.progress = nil
        patch.expandedSize = nil
        let reset = try JSONDecoder().decode(HostNotchStatePatch.self, from: JSONEncoder().encode(patch))
        state = try state.applying(reset)
        XCTAssertNil(state.progress)
        XCTAssertNil(state.expandedSize)
    }

    func testExplicitNullCannotSilentlyApplyHalfOfAPatch() throws {
        var session = HostSession()
        for key in ["style", "motion", "expanded", "title", "subtitle", "activity", "actions"] {
            let json = #"{"id":"bad","command":"show","state":{"progress":0.8,"\#(key)":null}}"#
            XCTAssertThrowsError(try session.apply(decode(json)), key)
            XCTAssertFalse(session.visible)
            XCTAssertNil(session.state.progress)
        }
        XCTAssertThrowsError(try decode(#"{"id":"bad","command":"hide","state":null}"#))
    }

    func testFullStateEncodesNullProgressAndEmptyActions() throws {
        let event = HostEvent.result(id: "1", state: .init(), visible: false)
        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = try XCTUnwrap(object["state"] as? [String: Any])
        XCTAssertTrue(state["progress"] is NSNull)
        XCTAssertTrue(state["expandedSize"] is NSNull)
        XCTAssertEqual((state["actions"] as? [Any])?.count, 0)
        XCTAssertEqual(state["motion"] as? String, "spring")
    }

    func testFramingPreservesMultibyteUnicodeAcrossReads() throws {
        var framer = HostLineFramer()
        let message = #"{"id":"1","command":"show","state":{"title":"Gute Nacht 🌙"}}"#
        let bytes = Data(message.utf8)
        var frames: [HostInputFrame] = []
        for byte in bytes { frames += framer.append(Data([byte])) }
        XCTAssertTrue(frames.isEmpty)
        frames += framer.append(Data([13, 10]))
        XCTAssertEqual(frames, [.line(bytes)])
        XCTAssertEqual(try JSONDecoder().decode(HostRequest.self, from: bytes).state?.title, "Gute Nacht 🌙")
    }

    func testOversizedLineIsDiscardedAndNextRequestRecovers() {
        var framer = HostLineFramer()
        XCTAssertEqual(framer.append(Data(repeating: 120, count: HostLineFramer.maximumLineBytes + 5)), [])
        let good = Data(#"{"id":"recovered","command":"hide"}"#.utf8)
        var rest = Data([10])
        rest.append(good)
        rest.append(10)
        XCTAssertEqual(framer.append(rest), [.lineTooLong, .line(good)])
    }

    func testFramerAllowsLimitAndFlushesUnterminatedFinalLine() {
        var framer = HostLineFramer()
        let limit = Data(repeating: 120, count: HostLineFramer.maximumLineBytes)
        XCTAssertEqual(framer.append(limit), [])
        XCTAssertEqual(framer.append(Data([10])), [.line(limit)])
        XCTAssertEqual(framer.append(Data("last".utf8)), [])
        XCTAssertEqual(framer.finish(), [.line(Data("last".utf8))])
        XCTAssertEqual(framer.finish(), [])
    }

    func testCombinedUnicodePatchesCannotOverflowHostResponseFrame() throws {
        var session = HostSession()
        let clustered = "A" + String(repeating: "\u{0301}", count: 17_000)
        try session.apply(.init(id: "title", command: .show, state: .init(title: clustered)))
        let before = session.state
        XCTAssertThrowsError(
            try session.apply(.init(id: "subtitle", command: .update, state: .init(subtitle: clustered)))
        ) { error in
            XCTAssertEqual((error as? HostProtocolError)?.code, "invalid_state")
        }
        XCTAssertEqual(session.state, before)
        let encoded = try JSONEncoder().encode(HostEvent.result(id: "snapshot", state: session.state, visible: true))
        XCTAssertLessThanOrEqual(encoded.count, HostLineFramer.maximumLineBytes)
    }

    func testIdentifiersHaveABoundedUTF8Representation() throws {
        let oversized = "a" + String(repeating: "\u{0301}", count: 1_000)
        var session = HostSession()
        XCTAssertThrowsError(try session.apply(.init(id: oversized, command: .show)))
        XCTAssertThrowsError(
            try session.apply(
                .init(id: "action", command: .show, state: .init(actions: [.init(id: oversized, label: "Action")]))))
        XCTAssertFalse(session.visible)
    }

    func testInvalidRequestsOnlyRecoverSafeCorrelationIDs() throws {
        XCTAssertEqual(HostRequest.correlationID(in: Data(#"{"id":"safe","command":"bad"}"#.utf8)), "safe")
        XCTAssertNil(HostRequest.correlationID(in: Data(#"{"id":"unsafe\n","command":"bad"}"#.utf8)))
        let identifier = "a" + String(repeating: "\u{0301}", count: 1_000)
        let data = try JSONEncoder().encode(["id": identifier, "command": "bad"])
        XCTAssertNil(HostRequest.correlationID(in: data))
    }
}
