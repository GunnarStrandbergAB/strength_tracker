import Foundation

/// Decodes xAI `/v1/responses` SSE payloads into `AIStreamEvent`s.
///
/// xAI does not publish its streaming event catalog; it mirrors OpenAI's
/// Responses events (`response.output_text.delta`, `response.output_item.done`,
/// `response.completed`, …). This decoder is deliberately tolerant: events it
/// does not recognize are skipped, so at worst streaming degrades to the full
/// text arriving with `response.completed`.
public struct ResponsesStreamDecoder: Sendable {

    public init() {}

    /// Decode one SSE event. Returns nil for events that carry nothing we need.
    public func decode(_ sseEvent: SSEEvent) -> AIStreamEvent? {
        let data = sseEvent.data
        if data == "[DONE]" { return nil }
        guard let jsonData = data.data(using: .utf8),
              let payload = try? JSONDecoder().decode(JSONValue.self, from: jsonData),
              case .object(let object) = payload else {
            return nil
        }

        // The payload's own "type" field is authoritative; the SSE event name is the fallback.
        let type = object["type"].flatMap(Self.asString) ?? sseEvent.event ?? ""

        switch type {
        case "response.output_text.delta":
            guard let delta = object["delta"].flatMap(Self.asString) else { return nil }
            return .textDelta(delta)

        case "response.output_item.done":
            guard case .object(let item)? = object["item"] else { return nil }
            return Self.functionCall(fromOutputItem: item).map { .functionCall($0) }

        case "response.completed":
            guard case .object(let response)? = object["response"] else { return nil }
            return Self.completed(fromResponse: response)

        case "response.failed", "error":
            let message = Self.errorMessage(in: object) ?? "The model reported a failure."
            return .failed(message: message)

        default:
            return nil
        }
    }

    // MARK: - Shared response decoding (also used by the non-streamed path)

    /// Extracts a function call from an output item object, if it is one.
    public static func functionCall(fromOutputItem item: [String: JSONValue]) -> AIFunctionCall? {
        guard item["type"].flatMap(asString) == "function_call",
              let callID = item["call_id"].flatMap(asString) ?? item["id"].flatMap(asString),
              let name = item["name"].flatMap(asString) else {
            return nil
        }
        let arguments = item["arguments"].flatMap(asString) ?? "{}"
        return AIFunctionCall(callID: callID, name: name, argumentsJSON: arguments)
    }

    /// Builds a `.completed` event from a full response object.
    public static func completed(fromResponse response: [String: JSONValue]) -> AIStreamEvent {
        let id = response["id"].flatMap(asString) ?? ""
        return .completed(responseID: id, fullText: outputText(in: response), usage: usage(in: response))
    }

    /// Concatenated output_text of all message items in a response object.
    public static func outputText(in response: [String: JSONValue]) -> String {
        guard case .array(let output)? = response["output"] else { return "" }
        var text = ""
        for case .object(let item) in output where item["type"].flatMap(asString) == "message" {
            guard case .array(let content)? = item["content"] else { continue }
            for case .object(let part) in content where part["type"].flatMap(asString) == "output_text" {
                text += part["text"].flatMap(asString) ?? ""
            }
        }
        return text
    }

    /// All function calls in a response object's output array.
    public static func functionCalls(in response: [String: JSONValue]) -> [AIFunctionCall] {
        guard case .array(let output)? = response["output"] else { return [] }
        var calls: [AIFunctionCall] = []
        for case .object(let item) in output {
            if let call = functionCall(fromOutputItem: item) {
                calls.append(call)
            }
        }
        return calls
    }

    public static func usage(in response: [String: JSONValue]) -> AIUsage? {
        guard case .object(let usage)? = response["usage"] else { return nil }
        let input = usage["input_tokens"].flatMap(asInt) ?? 0
        let output = usage["output_tokens"].flatMap(asInt) ?? 0
        var cached: Int?
        if case .object(let details)? = usage["input_tokens_details"] {
            cached = details["cached_tokens"].flatMap(asInt)
        }
        return AIUsage(inputTokens: input, outputTokens: output, cachedTokens: cached)
    }

    private static func errorMessage(in object: [String: JSONValue]) -> String? {
        if case .object(let error)? = object["error"], let message = error["message"].flatMap(asString) {
            return message
        }
        if case .object(let response)? = object["response"],
           case .object(let error)? = response["error"],
           let message = error["message"].flatMap(asString) {
            return message
        }
        return object["message"].flatMap(asString)
    }

    static func asString(_ value: JSONValue) -> String? {
        if case .string(let string) = value { return string }
        return nil
    }

    static func asInt(_ value: JSONValue) -> Int? {
        if case .number(let number) = value { return Int(number) }
        return nil
    }
}
