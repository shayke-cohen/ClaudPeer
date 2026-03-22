import Foundation

/// Builds `session.message` text for group chats: shared transcript delta + latest user line.
enum GroupPromptBuilder {
    /// Rough cap for injected transcript (characters) to avoid huge prompts.
    static let maxInjectedCharacters = 120_000

    /// When only one agent session exists, send raw user text (legacy single-chat behavior).
    static func shouldUseGroupInjection(sessionCount: Int) -> Bool {
        sessionCount > 1
    }

    static func buildMessageText(
        conversation: Conversation,
        targetSession: Session,
        latestUserMessageText: String,
        participants: [Participant]
    ) -> String {
        let sessionCount = conversation.sessions.count
        guard shouldUseGroupInjection(sessionCount: sessionCount) else {
            return latestUserMessageText
        }

        let sortedChat = conversation.messages
            .filter { $0.type == .chat }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let deltaLines = deltaTranscriptLines(
            sortedChat: sortedChat,
            lastInjectedMessageId: targetSession.lastInjectedMessageId,
            participants: participants
        )

        let transcriptBody = deltaLines.joined(separator: "\n")
        let clipped = clipTranscript(transcriptBody)

        let agentName = targetSession.agent?.name ?? "Assistant"
        return """
        --- Group thread (new since your last reply) ---
        \(clipped)
        --- End ---

        You are \(agentName). Respond to the latest user message in this group.
        Latest user message:
        \"\"\"
        \(latestUserMessageText)
        \"\"\"
        """
    }

    private static func deltaTranscriptLines(
        sortedChat: [ConversationMessage],
        lastInjectedMessageId: UUID?,
        participants: [Participant]
    ) -> [String] {
        var startIndex = 0
        if let wid = lastInjectedMessageId,
           let idx = sortedChat.firstIndex(where: { $0.id == wid }) {
            startIndex = idx + 1
        } else if lastInjectedMessageId != nil {
            startIndex = 0
        }

        guard startIndex < sortedChat.count else { return [] }

        return sortedChat[startIndex...].map { msg in
            let label = senderLabel(for: msg, participants: participants)
            let body = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? "\(label): (empty)" : "\(label): \(body)"
        }
    }

    private static func senderLabel(for message: ConversationMessage, participants: [Participant]) -> String {
        guard let sid = message.senderParticipantId,
              let p = participants.first(where: { $0.id == sid }) else {
            return "Unknown"
        }
        switch p.type {
        case .user:
            return "[You]"
        case .agentSession:
            return p.displayName
        }
    }

    private static func clipTranscript(_ text: String) -> String {
        guard text.count > maxInjectedCharacters else { return text }
        let suffix = String(text.suffix(maxInjectedCharacters))
        return "… (truncated)\n" + suffix
    }

    /// Call after persisting an assistant `ConversationMessage` for this session.
    static func advanceWatermark(session: Session, assistantMessage: ConversationMessage) {
        session.lastInjectedMessageId = assistantMessage.id
    }
}
