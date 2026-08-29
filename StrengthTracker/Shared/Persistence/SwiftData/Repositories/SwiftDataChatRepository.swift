#if canImport(SwiftData)
import SwiftData
import Foundation

@MainActor
public final class SwiftDataChatRepository: ChatRepository, Sendable {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func fetchConversations() async throws -> [ChatConversation] {
        let descriptor = FetchDescriptor<ChatConversationEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { ChatMapper.toDomain($0) }
    }

    public func fetchMessages(conversationID: UUID) async throws -> [ChatMessage] {
        guard let entity = try fetchConversationEntity(id: conversationID) else { return [] }
        return entity.messages
            .sorted { $0.createdAt < $1.createdAt }
            .map { ChatMapper.toDomain($0) }
    }

    public func createConversation(_ conversation: ChatConversation) async throws {
        modelContext.insert(ChatMapper.toEntity(conversation))
        try modelContext.save()
    }

    public func updateConversation(_ conversation: ChatConversation) async throws {
        guard let entity = try fetchConversationEntity(id: conversation.id) else { return }
        ChatMapper.updateEntity(entity, from: conversation)
        try modelContext.save()
    }

    public func appendMessage(_ message: ChatMessage, to conversationID: UUID) async throws {
        guard let conversation = try fetchConversationEntity(id: conversationID) else { return }
        let entity = ChatMapper.toEntity(message)
        // Insert the unattached entity first, then wire the relationship —
        // setting the parent on an un-inserted model implicitly registers it,
        // and a second explicit insert of the same unique id is fragile.
        modelContext.insert(entity)
        entity.conversation = conversation
        conversation.updatedAt = message.createdAt
        try modelContext.save()
    }

    public func updateMessage(_ message: ChatMessage) async throws {
        let messageID = message.id
        let descriptor = FetchDescriptor<ChatMessageEntity>(
            predicate: #Predicate { entity in
                entity.id == messageID
            }
        )
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        ChatMapper.updateEntity(entity, from: message)
        try modelContext.save()
    }

    public func deleteConversation(id: UUID) async throws {
        guard let entity = try fetchConversationEntity(id: id) else { return }
        modelContext.delete(entity)
        try modelContext.save()
    }

    private func fetchConversationEntity(id: UUID) throws -> ChatConversationEntity? {
        let descriptor = FetchDescriptor<ChatConversationEntity>(
            predicate: #Predicate { entity in
                entity.id == id
            }
        )
        return try modelContext.fetch(descriptor).first
    }
}
#endif
