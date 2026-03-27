import XCTest
@testable import ClaudeStudio

final class PeerChannelMessageTests: XCTestCase {

    // MARK: - MessageType.isPeerChannel

    func testPeerMessageTypeIsPeerChannel() {
        XCTAssertTrue(MessageType.peerMessage.isPeerChannel)
    }

    func testDelegationTypeIsPeerChannel() {
        XCTAssertTrue(MessageType.delegation.isPeerChannel)
    }

    func testBlackboardUpdateTypeIsPeerChannel() {
        XCTAssertTrue(MessageType.blackboardUpdate.isPeerChannel)
    }

    func testChatTypeIsNotPeerChannel() {
        XCTAssertFalse(MessageType.chat.isPeerChannel)
    }

    func testToolCallTypeIsNotPeerChannel() {
        XCTAssertFalse(MessageType.toolCall.isPeerChannel)
    }

    func testToolResultTypeIsNotPeerChannel() {
        XCTAssertFalse(MessageType.toolResult.isPeerChannel)
    }

    func testSystemTypeIsNotPeerChannel() {
        XCTAssertFalse(MessageType.system.isPeerChannel)
    }

    func testQuestionTypeIsNotPeerChannel() {
        XCTAssertFalse(MessageType.question.isPeerChannel)
    }

    func testRichContentTypeIsNotPeerChannel() {
        XCTAssertFalse(MessageType.richContent.isPeerChannel)
    }

    // MARK: - Filter logic

    func testFilterShowsAllWhenEnabled() {
        let messages = makeMixedMessages()
        let filtered = messages.filter { _ in true } // showPeerChannelMessages = true
        XCTAssertEqual(filtered.count, messages.count)
    }

    func testFilterHidesPeerChannelWhenDisabled() {
        let messages = makeMixedMessages()
        let filtered = messages.filter { !$0.type.isPeerChannel }
        let peerCount = messages.filter { $0.type.isPeerChannel }.count
        XCTAssertEqual(peerCount, 3, "Should have 3 peer channel messages")
        XCTAssertEqual(filtered.count, messages.count - peerCount)
        XCTAssertTrue(filtered.allSatisfy { !$0.type.isPeerChannel })
    }

    func testFilterKeepsNonPeerTypes() {
        let messages = makeMixedMessages()
        let filtered = messages.filter { !$0.type.isPeerChannel }
        let types = Set(filtered.map { $0.type })
        XCTAssertTrue(types.contains(.chat))
        XCTAssertTrue(types.contains(.toolCall))
        XCTAssertTrue(types.contains(.system))
        XCTAssertFalse(types.contains(.peerMessage))
        XCTAssertFalse(types.contains(.delegation))
        XCTAssertFalse(types.contains(.blackboardUpdate))
    }

    // MARK: - ConversationMessage creation

    func testPeerMessageCreation() {
        let msg = ConversationMessage(text: "Coder: Review this file", type: .peerMessage)
        XCTAssertEqual(msg.type, .peerMessage)
        XCTAssertEqual(msg.text, "Coder: Review this file")
        XCTAssertTrue(msg.type.isPeerChannel)
    }

    func testDelegationMessageCreation() {
        let msg = ConversationMessage(text: "Orchestrator → Coder: Implement login", type: .delegation)
        XCTAssertEqual(msg.type, .delegation)
        XCTAssertTrue(msg.type.isPeerChannel)
    }

    func testBlackboardUpdateMessageCreation() {
        let msg = ConversationMessage(text: "Coder wrote research.findings: Found 3 endpoints", type: .blackboardUpdate)
        XCTAssertEqual(msg.type, .blackboardUpdate)
        XCTAssertTrue(msg.type.isPeerChannel)
    }

    // MARK: - Wire event parsing

    func testPeerChatEventParsesSessionId() {
        let json: [String: Any] = [
            "type": "peer.chat",
            "sessionId": "abc-123",
            "channelId": "dm-abc-def",
            "from": "Coder",
            "message": "Hello"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let wire = try! JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .peerChat(let sessionId, let channelId, let from, let message) = event {
            XCTAssertEqual(sessionId, "abc-123")
            XCTAssertEqual(channelId, "dm-abc-def")
            XCTAssertEqual(from, "Coder")
            XCTAssertEqual(message, "Hello")
        } else {
            XCTFail("Expected peerChat event, got \(String(describing: event))")
        }
    }

    func testPeerDelegateEventParsesSessionId() {
        let json: [String: Any] = [
            "type": "peer.delegate",
            "sessionId": "abc-123",
            "from": "Orchestrator",
            "to": "Coder",
            "text": "Build the UI"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let wire = try! JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .peerDelegate(let sessionId, let from, let to, let task) = event {
            XCTAssertEqual(sessionId, "abc-123")
            XCTAssertEqual(from, "Orchestrator")
            XCTAssertEqual(to, "Coder")
            XCTAssertEqual(task, "Build the UI")
        } else {
            XCTFail("Expected peerDelegate event, got \(String(describing: event))")
        }
    }

    func testBlackboardUpdateEventParsesSessionId() {
        let json: [String: Any] = [
            "type": "blackboard.update",
            "sessionId": "abc-123",
            "key": "research.findings",
            "value": "Found 3 endpoints",
            "writtenBy": "Researcher"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let wire = try! JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .blackboardUpdate(let sessionId, let key, let value, let writtenBy) = event {
            XCTAssertEqual(sessionId, "abc-123")
            XCTAssertEqual(key, "research.findings")
            XCTAssertEqual(value, "Found 3 endpoints")
            XCTAssertEqual(writtenBy, "Researcher")
        } else {
            XCTFail("Expected blackboardUpdate event, got \(String(describing: event))")
        }
    }

    // MARK: - Helpers

    private func makeMixedMessages() -> [ConversationMessage] {
        [
            ConversationMessage(text: "Hello", type: .chat),
            ConversationMessage(text: "Coder: check this", type: .peerMessage),
            ConversationMessage(text: "Read file.swift", type: .toolCall),
            ConversationMessage(text: "Orchestrator → Coder: build it", type: .delegation),
            ConversationMessage(text: "Session started", type: .system),
            ConversationMessage(text: "Coder wrote plan: ...", type: .blackboardUpdate),
        ]
    }
}
