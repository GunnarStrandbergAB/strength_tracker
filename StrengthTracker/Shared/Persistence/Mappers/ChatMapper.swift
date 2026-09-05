#if canImport(SwiftData)
import Foundation

public enum ChatMapper {

    public static func toDomain(_ entity: ChatConversationEntity) -> ChatConversation {
        ChatConversation(
            id: entity.id,
            title: entity.title,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            lastResponseID: entity.lastResponseID
        )
    }

    public static func toEntity(_ domain: ChatConversation) -> ChatConversationEntity {
        ChatConversationEntity(
            id: domain.id,
            title: domain.title,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            lastResponseID: domain.lastResponseID
        )
    }

    public static func updateEntity(_ entity: ChatConversationEntity, from domain: ChatConversation) {
        entity.title = domain.title
        entity.updatedAt = domain.updatedAt
        entity.lastResponseID = domain.lastResponseID
    }

    public static func toDomain(_ entity: ChatMessageEntity) -> ChatMessage {
        var kind = MessageKind(rawValue: entity.kind) ?? .text
        var text = entity.text
        var draftJSON = entity.draftJSON
        var receiptJSON = entity.receiptJSON

        // A draft message whose payload no longer decodes (e.g. after a model
        // change) degrades to plain text instead of crashing history.
        if kind == .draft {
            let decodable = draftJSON
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONDecoder().decode(AIDraft.self, from: $0) }
            if decodable == nil {
                kind = .text
                draftJSON = nil
                if text.isEmpty { text = "(This proposal is no longer available.)" }
            }
        }

        if kind == .receipt {
            let decodable = receiptJSON
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONDecoder().decode(AIReceipt.self, from: $0) }
            if decodable == nil {
                kind = .text
                receiptJSON = nil
                if text.isEmpty { text = "(This receipt is no longer available.)" }
            }
        }

        let activities = entity.toolActivityJSON
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([ToolActivity].self, from: $0) }

        return ChatMessage(
            id: entity.id,
            role: ChatRole(rawValue: entity.role) ?? .assistant,
            kind: kind,
            text: text,
            createdAt: entity.createdAt,
            draftJSON: draftJSON,
            draftStatus: entity.draftStatus.flatMap { DraftStatus(rawValue: $0) },
            receiptJSON: receiptJSON,
            toolActivities: activities ?? []
        )
    }

    public static func toEntity(_ domain: ChatMessage) -> ChatMessageEntity {
        ChatMessageEntity(
            id: domain.id,
            role: domain.role.rawValue,
            kind: domain.kind.rawValue,
            text: domain.text,
            createdAt: domain.createdAt,
            draftJSON: domain.draftJSON,
            draftStatus: domain.draftStatus?.rawValue,
            toolActivityJSON: encodeActivities(domain.toolActivities),
            receiptJSON: domain.receiptJSON
        )
    }

    public static func updateEntity(_ entity: ChatMessageEntity, from domain: ChatMessage) {
        entity.role = domain.role.rawValue
        entity.kind = domain.kind.rawValue
        entity.text = domain.text
        entity.createdAt = domain.createdAt
        entity.draftJSON = domain.draftJSON
        entity.draftStatus = domain.draftStatus?.rawValue
        entity.toolActivityJSON = encodeActivities(domain.toolActivities)
        entity.receiptJSON = domain.receiptJSON
    }

    private static func encodeActivities(_ activities: [ToolActivity]) -> String? {
        guard !activities.isEmpty,
              let data = try? JSONEncoder().encode(activities) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
#endif
