import XCTest
import SwiftData
@testable import ClaudPeer

@MainActor
final class GroupPromptBuilderTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testSingleSessionReturnsRawUserText() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let agent = Agent(name: "Solo")
        ctx.insert(agent)
        let convo = Conversation()
        let session = Session(agent: agent, workingDirectory: "/tmp")
        session.conversations = [convo]
        convo.sessions = [session]
        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        ctx.insert(convo)
        ctx.insert(session)
        ctx.insert(user)

        let text = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: session,
            latestUserMessageText: "Hello",
            participants: convo.participants
        )
        XCTAssertEqual(text, "Hello")
    }

    func testTwoSessionsIncludesGroupTranscript() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let m1 = ConversationMessage(senderParticipantId: user.id, text: "Hi room", type: .chat, conversation: convo)
        convo.messages.append(m1)

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(m1)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Next",
            participants: convo.participants
        )
        XCTAssertTrue(built.contains("Group thread"))
        XCTAssertTrue(built.contains("[You]:"))
        XCTAssertTrue(built.contains("Hi room"))
        XCTAssertTrue(built.contains("You are A1"))
        XCTAssertTrue(built.contains("Next"))
    }

    func testWatermarkOmitsEarlierMessages() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let oldMsg = ConversationMessage(senderParticipantId: user.id, text: "OLD", type: .chat, conversation: convo)
        let newMsg = ConversationMessage(senderParticipantId: user.id, text: "NEW", type: .chat, conversation: convo)
        convo.messages.append(contentsOf: [oldMsg, newMsg])
        s1.lastInjectedMessageId = oldMsg.id

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(oldMsg)
        ctx.insert(newMsg)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Latest",
            participants: convo.participants
        )
        XCTAssertFalse(built.contains("OLD"))
        XCTAssertTrue(built.contains("NEW"))
    }

    func testShouldUseGroupInjection() {
        XCTAssertFalse(GroupPromptBuilder.shouldUseGroupInjection(sessionCount: 1))
        XCTAssertFalse(GroupPromptBuilder.shouldUseGroupInjection(sessionCount: 0))
        XCTAssertTrue(GroupPromptBuilder.shouldUseGroupInjection(sessionCount: 2))
    }

    func testAdvanceWatermarkSetsLastInjectedMessageId() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let agent = Agent(name: "A")
        ctx.insert(agent)
        let session = Session(agent: agent, workingDirectory: "/tmp")
        let msg = ConversationMessage(text: "Reply", type: .chat)
        ctx.insert(session)
        ctx.insert(msg)

        XCTAssertNil(session.lastInjectedMessageId)
        GroupPromptBuilder.advanceWatermark(session: session, assistantMessage: msg)
        XCTAssertEqual(session.lastInjectedMessageId, msg.id)
    }

    func testNonChatMessagesExcludedFromTranscript() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let userChat = ConversationMessage(senderParticipantId: user.id, text: "visible", type: .chat, conversation: convo)
        let systemMsg = ConversationMessage(senderParticipantId: nil, text: "HIDDEN_SYSTEM", type: .system, conversation: convo)
        convo.messages.append(contentsOf: [userChat, systemMsg])

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(userChat)
        ctx.insert(systemMsg)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Next",
            participants: convo.participants
        )
        XCTAssertTrue(built.contains("visible"))
        XCTAssertFalse(built.contains("HIDDEN_SYSTEM"))
    }

    func testAgentMessageUsesParticipantDisplayName() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: "Display A1")
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let fromAgent = ConversationMessage(senderParticipantId: p1.id, text: "from agent line", type: .chat, conversation: convo)
        convo.messages.append(fromAgent)

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(fromAgent)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s2,
            latestUserMessageText: "Q",
            participants: convo.participants
        )
        XCTAssertTrue(built.contains("Display A1: from agent line"))
    }

    func testTranscriptTruncationPrefixWhenHuge() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let huge = String(repeating: "x", count: GroupPromptBuilder.maxInjectedCharacters + 5_000)
        let m1 = ConversationMessage(senderParticipantId: user.id, text: huge, type: .chat, conversation: convo)
        convo.messages.append(m1)

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(m1)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "short",
            participants: convo.participants
        )
        XCTAssertTrue(built.contains("… (truncated)"))
        XCTAssertTrue(built.count < huge.count + 500)
    }
}
