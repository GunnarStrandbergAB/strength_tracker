import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(os)
import os
#endif

/// Supplies the current API key at request time (hops to the main actor where
/// the credentials service lives).
public typealias APIKeyProvider = @Sendable () async -> String?

/// URLSession-based client for the xAI Responses API (https://api.x.ai/v1).
public final class XAIClient: AIChatClient, @unchecked Sendable {

    private let baseURL: URL
    private let session: URLSession
    private let apiKeyProvider: APIKeyProvider
    private let decoder = ResponsesStreamDecoder()

    #if canImport(os)
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "StrengthTracker",
        category: "XAIClient"
    )
    #endif

    private static func logFailure(status: Int, body: String, hadPreviousResponseID: Bool) {
        #if canImport(os)
        logger.error("xAI request failed: status=\(status, privacy: .public) previous_response_id=\(hadPreviousResponseID, privacy: .public) body=\(String(body.prefix(500)), privacy: .public)")
        #endif
    }

    public init(
        baseURL: URL = URL(string: "https://api.x.ai/v1")!,
        apiKeyProvider: @escaping APIKeyProvider,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.apiKeyProvider = apiKeyProvider
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            // Inter-byte idle timeout: generous, so long generations aren't killed mid-stream.
            config.timeoutIntervalForRequest = 180
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - AIChatClient

    public func respond(_ request: AIRequest) async throws -> AIResponse {
        let urlRequest = try await makeResponsesRequest(request, stream: false)
        let (data, response) = try await session.data(for: urlRequest)
        try Self.checkStatus(response, data: data)

        guard let payload = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let object) = payload else {
            throw AIClientError.decoding("not a JSON object")
        }
        let id = object["id"].flatMap(ResponsesStreamDecoder.asString) ?? ""
        return AIResponse(
            id: id,
            text: ResponsesStreamDecoder.outputText(in: object),
            functionCalls: ResponsesStreamDecoder.functionCalls(in: object),
            usage: ResponsesStreamDecoder.usage(in: object)
        )
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try await self.makeResponsesRequest(request, stream: true)
                    let (bytes, response) = try await self.session.bytes(for: urlRequest)

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 4096 { break }
                        }
                        Self.logFailure(
                            status: http.statusCode, body: body,
                            hadPreviousResponseID: request.previousResponseID?.isEmpty == false
                        )
                        throw Self.error(forStatus: http.statusCode, body: body)
                    }

                    // Drain to end of stream — the terminal [DONE] follows
                    // response.completed and costs only a few bytes.
                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let sseEvent = parser.parse(line: line) else { continue }
                        if sseEvent.data == "[DONE]" { break }
                        if let event = self.decoder.decode(sseEvent) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func validateKey() async throws {
        guard let key = await apiKeyProvider(), !key.isEmpty else { throw AIClientError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, data: data)
    }

    // MARK: - Request building

    private func makeResponsesRequest(_ request: AIRequest, stream: Bool) async throws -> URLRequest {
        guard let key = await apiKeyProvider(), !key.isEmpty else { throw AIClientError.notConfigured }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("responses"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Stable conversation id improves xAI's prompt-cache hit rate.
        urlRequest.setValue(request.conversationID.uuidString, forHTTPHeaderField: "x-grok-conv-id")
        urlRequest.httpBody = try JSONEncoder().encode(Self.body(for: request, stream: stream))
        return urlRequest
    }

    static func body(for request: AIRequest, stream: Bool) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "input": .array(request.input.map(inputItem)),
            "store": .bool(request.store),
            "stream": .bool(stream)
        ]
        let previous = request.previousResponseID.flatMap { $0.isEmpty ? nil : $0 }
        if let previous {
            // xAI rejects instructions alongside previous_response_id
            // ("Argument not supported: instructions and previous_response_id
            // together") — the stored turn's system prompt is reused server-side.
            body["previous_response_id"] = .string(previous)
        } else if let instructions = request.instructions {
            body["instructions"] = .string(instructions)
        }
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { tool in
                .object([
                    "type": .string("function"),
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": tool.parameters
                ])
            })
        }
        return .object(body)
    }

    private static func inputItem(_ item: AIInputItem) -> JSONValue {
        switch item {
        case .message(let role, let content):
            return .object(["role": .string(role), "content": .string(content)])
        case .functionCall(let callID, let name, let argumentsJSON):
            return .object([
                "type": .string("function_call"),
                "call_id": .string(callID),
                "name": .string(name),
                "arguments": .string(argumentsJSON)
            ])
        case .functionCallOutput(let callID, let output):
            return .object([
                "type": .string("function_call_output"),
                "call_id": .string(callID),
                "output": .string(output)
            ])
        }
    }

    // MARK: - Error mapping

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        let body = String(data: data, encoding: .utf8) ?? ""
        logFailure(status: http.statusCode, body: body, hadPreviousResponseID: false)
        throw error(forStatus: http.statusCode, body: body)
    }

    static func error(forStatus status: Int, body: String) -> AIClientError {
        switch status {
        case 401, 403:
            return .invalidKey
        case 429:
            return .rateLimited
        default:
            let message = errorMessage(fromBody: body)
            let lowered = message.lowercased()
            // Only a genuine lost-state error counts as expired; other
            // previous_response complaints (e.g. argument conflicts) must
            // surface their real message.
            let lostStateSignals = ["not found", "expired", "does not exist", "no longer"]
            if status >= 400, status < 500,
               lowered.contains("previous_response"),
               lostStateSignals.contains(where: lowered.contains) {
                return .previousResponseNotFound
            }
            return .http(status: status, message: message)
        }
    }

    private static func errorMessage(fromBody body: String) -> String {
        guard let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let object) = payload else {
            return String(body.prefix(300))
        }
        if case .string(let message)? = object["error"] { return message }
        if case .object(let error)? = object["error"],
           case .string(let message)? = error["message"] {
            return message
        }
        return String(body.prefix(300))
    }
}
