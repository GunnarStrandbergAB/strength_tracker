import Foundation

@MainActor
public protocol ChatRepository: Sendable {
    /// Conversation metadata (no messages), newest first.
    func fetchConversations() async throws -> [ChatConversation]
    /// Messages of one conversation, oldest first.
    func fetchMessages(conversationID: UUID) async throws -> [ChatMessage]
    func createConversation(_ conversation: ChatConversation) async throws
    func updateConversation(_ conversation: ChatConversation) async throws
    func appendMessage(_ message: ChatMessage, to conversationID: UUID) async throws
    func updateMessage(_ message: ChatMessage) async throws
    func deleteConversation(id: UUID) async throws
}
