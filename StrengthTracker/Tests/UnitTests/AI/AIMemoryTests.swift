import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("AIMemoryService")
@MainActor
struct AIMemoryServiceTests {

    private func makeService() -> (AIMemoryService, UserDefaults, String) {
        let suiteName = "ai-memory-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AIMemoryService(defaults: defaults), defaults, suiteName)
    }

    @Test("Adds trimmed memories and persists them across instances")
    func addAndPersist() throws {
        let (service, defaults, suiteName) = makeService()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let memory = try service.add("  The user's name is Gunnar.  ")
        #expect(memory.text == "The user's name is Gunnar.")
        #expect(service.memories.count == 1)

        // A fresh instance over the same defaults sees the stored memory.
        let reloaded = AIMemoryService(defaults: defaults)
        #expect(reloaded.memories.map(\.text) == ["The user's name is Gunnar."])
    }

    @Test("Rejects empty, over-length, and duplicate memories")
    func validation() throws {
        let (service, defaults, suiteName) = makeService()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(throws: AIToolError.self) { try service.add("   ") }
        #expect(throws: AIToolError.self) {
            try service.add(String(repeating: "x", count: AIMemoryService.maxLength + 1))
        }

        try service.add("User hates lunges")
        #expect(throws: AIToolError.self) { try service.add("user hates LUNGES") }
        #expect(service.memories.count == 1)
    }

    @Test("Rejects additions when the store is full")
    func fullStore() throws {
        let (service, defaults, suiteName) = makeService()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for index in 0..<AIMemoryService.maxMemories {
            try service.add("Memory number \(index)")
        }
        #expect(throws: AIToolError.self) { try service.add("One too many") }
    }

    @Test("Removes by id, matches case-insensitively, clears all")
    func removalAndMatching() throws {
        let (service, defaults, suiteName) = makeService()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let lunges = try service.add("User hates lunges")
        try service.add("User trains at Fitness24Seven")

        #expect(service.matching("LUNGES").map(\.id) == [lunges.id])
        #expect(service.matching("  ").isEmpty)

        service.remove(id: lunges.id)
        #expect(service.memories.count == 1)

        service.removeAll()
        #expect(service.memories.isEmpty)
        #expect(AIMemoryService(defaults: defaults).memories.isEmpty)
    }
}

@Suite("Memory tools")
@MainActor
struct MemoryToolsTests {

    private func makeServices() -> AIMemoryService {
        let defaults = UserDefaults(suiteName: "ai-memory-tools-\(UUID().uuidString)")!
        return AIMemoryService(defaults: defaults)
    }

    @Test("save_memory stores the fact and labels the chip")
    func saveMemory() async throws {
        let service = makeServices()
        let tool = SaveMemoryTool(memoryService: service)

        let result = try await tool.call(argumentsJSON: "{\"memory\":\"The user's name is Gunnar.\"}")
        #expect(service.memories.map(\.text) == ["The user's name is Gunnar."])
        #expect(result.outputForModel.contains("saved"))
        #expect(result.activityLabel.hasPrefix("Remembered: "))
        #expect(result.draft == nil)
    }

    @Test("Duplicate saves surface the service's error to the model")
    func saveDuplicate() async throws {
        let service = makeServices()
        try service.add("User hates lunges")
        let tool = SaveMemoryTool(memoryService: service)

        do {
            _ = try await tool.call(argumentsJSON: "{\"memory\":\"User hates lunges\"}")
            Issue.record("expected throw")
        } catch let error as AIToolError {
            #expect(error.message.contains("already saved"))
        }
    }

    @Test("forget_memory removes a unique match")
    func forgetMemory() async throws {
        let service = makeServices()
        try service.add("User hates lunges")
        try service.add("User's name is Gunnar")
        let tool = ForgetMemoryTool(memoryService: service)

        let result = try await tool.call(argumentsJSON: "{\"memory\":\"lunges\"}")
        #expect(service.memories.map(\.text) == ["User's name is Gunnar"])
        #expect(result.activityLabel.hasPrefix("Forgot: "))
    }

    @Test("forget_memory errors on zero or ambiguous matches")
    func forgetErrors() async throws {
        let service = makeServices()
        try service.add("User squats on Mondays")
        try service.add("User benches on Mondays")
        let tool = ForgetMemoryTool(memoryService: service)

        await #expect(throws: AIToolError.self) {
            _ = try await tool.call(argumentsJSON: "{\"memory\":\"deadlifts\"}")
        }
        do {
            _ = try await tool.call(argumentsJSON: "{\"memory\":\"Mondays\"}")
            Issue.record("expected ambiguity throw")
        } catch let error as AIToolError {
            #expect(error.message.contains("Multiple memories match"))
        }
        #expect(service.memories.count == 2)
    }
}

@Suite("AISystemPrompt memories")
struct AISystemPromptMemoryTests {

    @Test("Memories render as bullets in the instructions")
    func memoriesInPrompt() {
        let prompt = AISystemPrompt.build(
            weightUnit: .kg,
            memories: ["The user's name is Gunnar.", "User hates lunges."]
        )
        #expect(prompt.contains("Saved memories about the user"))
        #expect(prompt.contains("- The user's name is Gunnar."))
        #expect(prompt.contains("- User hates lunges."))
    }

    @Test("Empty memory store yields the explicit no-memories line")
    func emptyMemories() {
        let prompt = AISystemPrompt.build(weightUnit: .kg)
        #expect(prompt.contains("no saved memories about the user yet"))
        #expect(!prompt.contains("Saved memories about the user"))
    }
}
