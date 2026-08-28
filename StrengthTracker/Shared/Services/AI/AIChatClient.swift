import Foundation

// MARK: - JSONValue

/// A Sendable, Codable representation of arbitrary JSON. Used for tool parameter
/// schemas and tolerant decoding without resorting to [String: Any].
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Wire types

/// A tool definition in the xAI Responses API's flat shape.
public struct AIToolDefinition: Sendable, Equatable {
    public var name: String
    public var description: String
    public var parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// An item in the request `input` array.
public enum AIInputItem: Sendable, Equatable {
    case message(role: String, content: String)
    case functionCallOutput(callID: String, output: String)

    public static func user(_ text: String) -> AIInputItem { .message(role: "user", content: text) }
}

public struct AIRequest: Sendable {
    public var model: String
    public var instructions: String?
    public var input: [AIInputItem]
    public var previousResponseID: String?
    public var tools: [AIToolDefinition]
    public var conversationID: UUID
    public var store: Bool

    public init(
        model: String,
        instructions: String? = nil,
        input: [AIInputItem],
        previousResponseID: String? = nil,
        tools: [AIToolDefinition] = [],
        conversationID: UUID,
        store: Bool = true
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.previousResponseID = previousResponseID
        self.tools = tools
        self.conversationID = conversationID
        self.store = store
    }
}

/// A tool call requested by the model. `argumentsJSON` is the raw JSON-encoded string.
public struct AIFunctionCall: Sendable, Equatable {
    public var callID: String
    public var name: String
    public var argumentsJSON: String

    public init(callID: String, name: String, argumentsJSON: String) {
        self.callID = callID
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct AIUsage: Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int?

    public init(inputTokens: Int, outputTokens: Int, cachedTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
    }
}

public struct AIResponse: Sendable {
    public var id: String
    public var text: String
    public var functionCalls: [AIFunctionCall]
    public var usage: AIUsage?

    public init(id: String, text: String, functionCalls: [AIFunctionCall], usage: AIUsage? = nil) {
        self.id = id
        self.text = text
        self.functionCalls = functionCalls
        self.usage = usage
    }
}

public enum AIStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case functionCall(AIFunctionCall)
    case completed(responseID: String, fullText: String, usage: AIUsage?)
    case failed(message: String)
}

// MARK: - Errors

public enum AIClientError: Error, Equatable {
    /// No API key configured.
    case notConfigured
    /// HTTP 401 — the API key was rejected.
    case invalidKey
    /// HTTP 429 — rate limited.
    case rateLimited
    /// The server rejected the previous_response_id (expired or unknown).
    case previousResponseNotFound
    /// Any other non-2xx HTTP response.
    case http(status: Int, message: String)
    /// The response body could not be decoded.
    case decoding(String)

    public var userMessage: String {
        switch self {
        case .notConfigured: return "No xAI API key configured. Add one in Settings."
        case .invalidKey: return "The xAI API key was rejected. Check it in Settings."
        case .rateLimited: return "Rate limited by xAI. Wait a moment and try again."
        case .previousResponseNotFound: return "The conversation expired on the server."
        case .http(let status, let message): return "xAI error (\(status)): \(message)"
        case .decoding(let detail): return "Could not read the xAI response: \(detail)"
        }
    }
}

// MARK: - Client protocol

/// Client for the xAI Responses API. Implemented by XAIClient; mocked in tests.
public protocol AIChatClient: Sendable {
    /// One non-streamed request/response round trip.
    func respond(_ request: AIRequest) async throws -> AIResponse
    /// Streamed round trip. The stream finishes after a `.completed` (or throws).
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
    /// Cheap key validation (GET /v1/models — no tokens consumed).
    func validateKey() async throws
}
