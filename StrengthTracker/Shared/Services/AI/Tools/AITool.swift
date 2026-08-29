import Foundation

/// A capability the model can invoke. Mirrors the shape of Apple's
/// FoundationModels `Tool` protocol so a future migration stays cheap.
@MainActor
public protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    /// JSON-schema for the arguments; root must be `"type": "object"`.
    var parametersSchema: JSONValue { get }
    /// Execute with the model's raw JSON argument string. Thrown errors are
    /// reported back to the model as tool output so it can self-correct.
    func call(argumentsJSON: String) async throws -> AIToolResult
}

public struct AIToolResult: Sendable {
    /// Compact JSON (or plain text) sent back to the model as function_call_output.
    public var outputForModel: String
    /// Present only for propose_* tools: the draft to card in the chat.
    public var draft: AIDraft?
    /// Short label for the activity chip, e.g. "Read 12 workouts".
    public var activityLabel: String

    public init(outputForModel: String, draft: AIDraft? = nil, activityLabel: String) {
        self.outputForModel = outputForModel
        self.draft = draft
        self.activityLabel = activityLabel
    }
}

/// Thrown by tools for invalid arguments; the message is sent to the model.
/// Also used by draft-save routing — LocalizedError so alerts show the real
/// message instead of "The operation couldn't be completed…".
public struct AIToolError: Error, Sendable, LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Small helpers shared by tool implementations.
public enum AIJSON {
    /// Compact JSON string for a JSONValue payload.
    public static func string(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// ISO date (yyyy-MM-dd), for compact tool payloads.
    public static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    public static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    /// Round to one decimal to keep payloads compact.
    public static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

public extension AITool {
    var definition: AIToolDefinition {
        AIToolDefinition(name: name, description: description, parameters: parametersSchema)
    }

    /// Decode the model's argument JSON into a typed value.
    func decodeArguments<Arguments: Decodable>(_ type: Arguments.Type, from json: String) throws -> Arguments {
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw AIToolError("Invalid arguments for \(name): \(error.localizedDescription)")
        }
    }
}
