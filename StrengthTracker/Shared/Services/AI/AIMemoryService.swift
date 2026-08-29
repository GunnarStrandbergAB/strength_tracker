import Foundation
import Observation

/// One durable fact Grok has saved about the user.
public struct AIMemory: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Small on-device memory store the AI assistant reads on every conversation
/// (injected into its instructions) and writes via the save_memory /
/// forget_memory tools. Synchronous access — the instructions provider is a
/// sync closure. User-manageable in Settings.
@MainActor
@Observable
public final class AIMemoryService {

    public static let maxMemories = 100
    public static let maxLength = 300
    private static let storageKey = "aiMemories"

    public private(set) var memories: [AIMemory] = []

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([AIMemory].self, from: data) {
            memories = decoded
        }
    }

    /// Adds a memory. Throws AIToolError (message reaches the model) on empty,
    /// over-length, exact-duplicate, or full store.
    @discardableResult
    public func add(_ text: String) throws -> AIMemory {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIToolError("Memory text must not be empty.")
        }
        guard trimmed.count <= Self.maxLength else {
            throw AIToolError("Memory too long (\(trimmed.count) characters, max \(Self.maxLength)). Save a shorter summary.")
        }
        guard !memories.contains(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw AIToolError("That memory is already saved.")
        }
        guard memories.count < Self.maxMemories else {
            throw AIToolError("Memory store is full (\(Self.maxMemories)). Forget an outdated memory first.")
        }
        let memory = AIMemory(text: trimmed)
        memories.append(memory)
        persist()
        return memory
    }

    public func remove(id: UUID) {
        memories.removeAll { $0.id == id }
        persist()
    }

    /// Case-insensitive substring match; does not remove.
    public func matching(_ query: String) -> [AIMemory] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return memories.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    public func removeAll() {
        memories = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(memories) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
