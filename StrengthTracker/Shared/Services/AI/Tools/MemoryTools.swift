import Foundation

// Memory tools: direct writes (no Save/Discard card) — memories are low-stakes,
// visible as chips in the chat, and user-manageable in Settings.

private func memoryLabel(_ verb: String, _ text: String) -> String {
    let prefix = text.count > 40 ? String(text.prefix(40)) + "…" : text
    return "\(verb): \(prefix)"
}

// MARK: - save_memory

@MainActor
public final class SaveMemoryTool: AITool {
    private let memoryService: AIMemoryService

    public init(memoryService: AIMemoryService) {
        self.memoryService = memoryService
    }

    public let name = "save_memory"
    public let description = """
    Save a concise, durable fact about the user (name, preferences, injuries, \
    long-term goals). Saved memories appear in your instructions in future \
    conversations. Use when the user asks you to remember something or shares a \
    lasting fact — never for transient workout details.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(
            properties: [
                "memory": AIToolRegistry.stringSchema("The fact to remember, one short sentence (max \(AIMemoryService.maxLength) characters)")
            ],
            required: ["memory"]
        )
    }

    private struct Arguments: Decodable {
        var memory: String
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let saved = try memoryService.add(args.memory)
        return AIToolResult(
            outputForModel: #"{"status":"saved"}"#,
            activityLabel: memoryLabel("Remembered", saved.text)
        )
    }
}

// MARK: - forget_memory

@MainActor
public final class ForgetMemoryTool: AITool {
    private let memoryService: AIMemoryService

    public init(memoryService: AIMemoryService) {
        self.memoryService = memoryService
    }

    public let name = "forget_memory"
    public let description = """
    Delete a saved memory about the user. Pass distinctive text from the memory \
    (your saved memories are listed in your instructions). Use when the user asks \
    you to forget something or a saved fact is no longer true.
    """

    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(
            properties: [
                "memory": AIToolRegistry.stringSchema("Distinctive text from the memory to delete")
            ],
            required: ["memory"]
        )
    }

    private struct Arguments: Decodable {
        var memory: String
    }

    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let args = try decodeArguments(Arguments.self, from: argumentsJSON)
        let matches = memoryService.matching(args.memory)
        switch matches.count {
        case 0:
            throw AIToolError("No saved memory matches '\(args.memory)'. Check your instructions for the saved memories.")
        case 1:
            let memory = matches[0]
            memoryService.remove(id: memory.id)
            return AIToolResult(
                outputForModel: #"{"status":"forgotten"}"#,
                activityLabel: memoryLabel("Forgot", memory.text)
            )
        default:
            let listed = matches.map { "'\($0.text)'" }.joined(separator: ", ")
            throw AIToolError("Multiple memories match: \(listed). Call forget_memory again with more distinctive text.")
        }
    }
}
