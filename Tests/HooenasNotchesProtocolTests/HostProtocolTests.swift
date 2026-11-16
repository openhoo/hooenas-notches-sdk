import Foundation
import XCTest
@testable import HooenasNotchesProtocol

final class HostProtocolTests: XCTestCase {
    private func decode(_ json: String) throws -> HostRequest {
        try JSONDecoder().decode(HostRequest.self, from: Data(json.utf8))
    }

    func testPatchPreservesFieldsAndNullClearsProgress() throws {
        var session = HostSession()
        try session.apply(decode(#"{"id":"1","command":"show","state":{"title":"Upload","progress":0.4,"activity":"working"}}"#))
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
        XCTAssertThrowsError(try session.apply(decode(#"{"id":"2","command":"update","state":{"title":"Changed","progress":1.1}}"#))) { error in
            XCTAssertEqual((error as? HostProtocolError)?.code, "invalid_state")
        }
        XCTAssertEqual(session.state, before)
        XCTAssertTrue(session.visible)
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
        XCTAssertThrowsError(try session.apply(.init(id: "1", command: .show, state: .init(actions: [
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

    func testFullStateEncodesNullProgressAndEmptyActions() throws {
        let event = HostEvent.result(id: "1", state: .init(), visible: false)
        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = try XCTUnwrap(object["state"] as? [String: Any])
        XCTAssertTrue(state["progress"] is NSNull)
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
}
