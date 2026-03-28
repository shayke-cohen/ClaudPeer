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

    func testTaskEventTypeIsPeerChannel() {
        XCTAssertTrue(MessageType.taskEvent.isPeerChannel)
    }

    func testWorkspaceEventTypeIsPeerChannel() {
        XCTAssertTrue(MessageType.workspaceEvent.isPeerChannel)
    }

    func testAgentInviteTypeIsPeerChannel() {
        XCTAssertTrue(MessageType.agentInvite.isPeerChannel)
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

    // MARK: - PeerChannelCategory mapping

    func testPeerMessageCategory() {
        XCTAssertEqual(MessageType.peerMessage.peerChannelCategory, .messages)
    }

    func testDelegationCategory() {
        XCTAssertEqual(MessageType.delegation.peerChannelCategory, .delegations)
    }

    func testBlackboardCategory() {
        XCTAssertEqual(MessageType.blackboardUpdate.peerChannelCategory, .blackboard)
    }

    func testTaskEventCategory() {
        XCTAssertEqual(MessageType.taskEvent.peerChannelCategory, .tasks)
    }

    func testWorkspaceEventCategory() {
        XCTAssertEqual(MessageType.workspaceEvent.peerChannelCategory, .workspace)
    }

    func testAgentInviteCategory() {
        XCTAssertEqual(MessageType.agentInvite.peerChannelCategory, .invites)
    }

    func testNonPeerTypeHasNoCategory() {
        XCTAssertNil(MessageType.chat.peerChannelCategory)
        XCTAssertNil(MessageType.toolCall.peerChannelCategory)
        XCTAssertNil(MessageType.system.peerChannelCategory)
    }

    // MARK: - Filter logic (all categories enabled)

    func testFilterShowsAllWhenAllCategoriesEnabled() {
        let messages = makeMixedMessages()
        let allCategories = Set(PeerChannelCategory.allCases)
        let filtered = messages.filter { msg in
            guard let cat = msg.type.peerChannelCategory else { return true }
            return allCategories.contains(cat)
        }
        XCTAssertEqual(filtered.count, messages.count)
    }

    // MARK: - Filter logic (no categories enabled)

    func testFilterHidesAllPeerWhenNoCategoriesEnabled() {
        let messages = makeMixedMessages()
        let noCategories = Set<PeerChannelCategory>()
        let filtered = messages.filter { msg in
            guard let cat = msg.type.peerChannelCategory else { return true }
            return noCategories.contains(cat)
        }
        let peerCount = messages.filter { $0.type.isPeerChannel }.count
        XCTAssertEqual(peerCount, 6)
        XCTAssertEqual(filtered.count, messages.count - peerCount)
    }

    // MARK: - Filter logic (selective categories)

    func testFilterShowsOnlySelectedCategories() {
        let messages = makeMixedMessages()
        let enabled: Set<PeerChannelCategory> = [.messages, .tasks]
        let filtered = messages.filter { msg in
            guard let cat = msg.type.peerChannelCategory else { return true }
            return enabled.contains(cat)
        }
        // Should include: chat, toolCall, system (non-peer) + peerMessage + taskEvent = 5
        XCTAssertEqual(filtered.count, 5)
        // Should exclude: delegation, blackboardUpdate, workspaceEvent, agentInvite
        XCTAssertFalse(filtered.contains { $0.type == .delegation })
        XCTAssertFalse(filtered.contains { $0.type == .blackboardUpdate })
        XCTAssertFalse(filtered.contains { $0.type == .workspaceEvent })
        XCTAssertFalse(filtered.contains { $0.type == .agentInvite })
    }

    // MARK: - ConversationMessage creation

    func testPeerMessageCreation() {
        let msg = ConversationMessage(text: "Coder: Review this file", type: .peerMessage)
        XCTAssertEqual(msg.type, .peerMessage)
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

    func testTaskEventMessageCreation() {
        let msg = ConversationMessage(text: "Created: Implement login screen", type: .taskEvent)
        XCTAssertEqual(msg.type, .taskEvent)
        XCTAssertTrue(msg.type.isPeerChannel)
    }

    func testWorkspaceEventMessageCreation() {
        let msg = ConversationMessage(text: "Coder created workspace \"collab\"", type: .workspaceEvent)
        XCTAssertEqual(msg.type, .workspaceEvent)
        XCTAssertTrue(msg.type.isPeerChannel)
    }

    func testAgentInviteMessageCreation() {
        let msg = ConversationMessage(text: "Orchestrator invited Coder", type: .agentInvite)
        XCTAssertEqual(msg.type, .agentInvite)
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

    func testWorkspaceCreatedEventParses() {
        let json: [String: Any] = [
            "type": "workspace.created",
            "sessionId": "abc-123",
            "workspaceName": "collab",
            "agentName": "Coder"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let wire = try! JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .workspaceCreated(let sessionId, let name, let agent) = event {
            XCTAssertEqual(sessionId, "abc-123")
            XCTAssertEqual(name, "collab")
            XCTAssertEqual(agent, "Coder")
        } else {
            XCTFail("Expected workspaceCreated event, got \(String(describing: event))")
        }
    }

    func testWorkspaceJoinedEventParses() {
        let json: [String: Any] = [
            "type": "workspace.joined",
            "sessionId": "abc-456",
            "workspaceName": "collab",
            "agentName": "Tester"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let wire = try! JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .workspaceJoined(let sessionId, let name, let agent) = event {
            XCTAssertEqual(sessionId, "abc-456")
            XCTAssertEqual(name, "collab")
            XCTAssertEqual(agent, "Tester")
        } else {
            XCTFail("Expected workspaceJoined event, got \(String(describing: event))")
        }
    }

    func testAgentInvitedEventParses() {
        let json: [String: Any] = [
            "type": "agent.invited",
            "sessionId": "abc-123",
            "invitedAgent": "Coder",
            "invitedBy": "Orchestrator"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let wire = try! JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .agentInvited(let sessionId, let invited, let by) = event {
            XCTAssertEqual(sessionId, "abc-123")
            XCTAssertEqual(invited, "Coder")
            XCTAssertEqual(by, "Orchestrator")
        } else {
            XCTFail("Expected agentInvited event, got \(String(describing: event))")
        }
    }

    // MARK: - PeerChannelCategory.allCases

    func testAllCategoriesCount() {
        XCTAssertEqual(PeerChannelCategory.allCases.count, 6)
    }

    func testEachCategoryHasIcon() {
        for category in PeerChannelCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category) should have an icon")
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
            ConversationMessage(text: "Created: Login screen", type: .taskEvent),
            ConversationMessage(text: "Coder created workspace", type: .workspaceEvent),
            ConversationMessage(text: "Invited Coder", type: .agentInvite),
        ]
    }
}
