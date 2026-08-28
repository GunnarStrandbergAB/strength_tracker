import Foundation
@testable import StrengthTrackerShared

@MainActor
final class InMemoryChatRepository: ChatRepository {
    private(set) var conversations: [UUID: ChatConversation] = [:]
    private(set) var messagesByConversation: [UUID: [ChatMessage]] = [:]

    func fetchConversations() async throws -> [ChatConversation] {
        conversations.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchMessages(conversationID: UUID) async throws -> [ChatMessage] {
        (messagesByConversation[conversationID] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func createConversation(_ conversation: ChatConversation) async throws {
        conversations[conversation.id] = conversation
        messagesByConversation[conversation.id] = []
    }

    func updateConversation(_ conversation: ChatConversation) async throws {
        guard conversations[conversation.id] != nil else { return }
        conversations[conversation.id] = conversation
    }

    func appendMessage(_ message: ChatMessage, to conversationID: UUID) async throws {
        messagesByConversation[conversationID, default: []].append(message)
        conversations[conversationID]?.updatedAt = message.createdAt
    }

    func updateMessage(_ message: ChatMessage) async throws {
        for (conversationID, messages) in messagesByConversation {
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messagesByConversation[conversationID]?[index] = message
                return
            }
        }
    }

    func deleteConversation(id: UUID) async throws {
        conversations[id] = nil
        messagesByConversation[id] = nil
    }
}
