import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("XAIClient request encoding")
struct XAIClientEncodingTests {

    private func encodeBody(_ request: AIRequest, stream: Bool) throws -> [String: JSONValue] {
        let body = XAIClient.body(for: request, stream: stream)
        guard case .object(let object) = body else {
            Issue.record("body is not an object")
            return [:]
        }
        // Round-trip through JSONEncoder/Decoder to prove it serializes.
        let data = try JSONEncoder().encode(body)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == body)
        return object
    }

    @Test("Minimal request carries model, input, store, and stream flags")
    func minimalRequest() throws {
        let request = AIRequest(
            model: "grok-4.6",
            input: [.user("Hello")],
            conversationID: UUID()
        )
        let object = try encodeBody(request, stream: true)

        #expect(object["model"] == .string("grok-4.6"))
        #expect(object["stream"] == .bool(true))
        #expect(object["store"] == .bool(true))
        #expect(object["instructions"] == nil)
        #expect(object["previous_response_id"] == nil)
        #expect(object["tools"] == nil)
        #expect(object["input"] == .array([
            .object(["role": .string("user"), "content": .string("Hello")])
        ]))
    }

    @Test("Instructions, previous response id, and tools are encoded")
    func fullRequest() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object(["query": .object(["type": .string("string")])])
        ])
        let request = AIRequest(
            model: "grok-4.6",
            instructions: "You are a coach.",
            input: [.user("Hi")],
            previousResponseID: "resp_abc",
            tools: [AIToolDefinition(name: "list_exercises", description: "List exercises", parameters: schema)],
            conversationID: UUID()
        )
        let object = try encodeBody(request, stream: false)

        #expect(object["instructions"] == .string("You are a coach."))
        #expect(object["previous_response_id"] == .string("resp_abc"))
        #expect(object["stream"] == .bool(false))
        #expect(object["tools"] == .array([
            .object([
                "type": .string("function"),
                "name": .string("list_exercises"),
                "description": .string("List exercises"),
                "parameters": schema
            ])
        ]))
    }

    @Test("Function call outputs encode as function_call_output items")
    func functionCallOutput() throws {
        let request = AIRequest(
            model: "grok-4.6",
            input: [.functionCallOutput(callID: "call_1", output: "{\"ok\":true}")],
            conversationID: UUID()
        )
        let object = try encodeBody(request, stream: true)

        #expect(object["input"] == .array([
            .object([
                "type": .string("function_call_output"),
                "call_id": .string("call_1"),
                "output": .string("{\"ok\":true}")
            ])
        ]))
    }

    @Test("HTTP status codes map to typed errors")
    func errorMapping() {
        #expect(XAIClient.error(forStatus: 401, body: "") == .invalidKey)
        #expect(XAIClient.error(forStatus: 403, body: "") == .invalidKey)
        #expect(XAIClient.error(forStatus: 429, body: "") == .rateLimited)
        #expect(XAIClient.error(
            forStatus: 404,
            body: "{\"error\": {\"message\": \"previous_response_id not found\"}}"
        ) == .previousResponseNotFound)
        #expect(XAIClient.error(
            forStatus: 500,
            body: "{\"error\": {\"message\": \"boom\"}}"
        ) == .http(status: 500, message: "boom"))
        #expect(XAIClient.error(forStatus: 502, body: "gateway") == .http(status: 502, message: "gateway"))
    }
}
