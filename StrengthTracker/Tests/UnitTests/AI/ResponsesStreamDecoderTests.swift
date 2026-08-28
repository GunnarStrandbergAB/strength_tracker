import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("SSEParser")
struct SSEParserTests {

    @Test("Data lines become events; event names attach to the next data line")
    func basicParsing() {
        var parser = SSEParser()

        #expect(parser.parse(line: "event: response.output_text.delta") == nil)
        let event = parser.parse(line: "data: {\"delta\":\"Hi\"}")
        #expect(event == SSEEvent(event: "response.output_text.delta", data: "{\"delta\":\"Hi\"}"))

        // Event name is consumed — the next bare data line has none.
        let second = parser.parse(line: "data: {\"x\":1}")
        #expect(second == SSEEvent(event: nil, data: "{\"x\":1}"))
    }

    @Test("Comments, ids, and unknown lines are skipped")
    func skipsNoise() {
        var parser = SSEParser()
        #expect(parser.parse(line: ": keep-alive") == nil)
        #expect(parser.parse(line: "id: 42") == nil)
        #expect(parser.parse(line: "retry: 1000") == nil)
        #expect(parser.parse(line: "garbage") == nil)
    }
}

@Suite("ResponsesStreamDecoder")
struct ResponsesStreamDecoderTests {

    private let decoder = ResponsesStreamDecoder()

    private func decode(_ json: String, eventName: String? = nil) -> AIStreamEvent? {
        decoder.decode(SSEEvent(event: eventName, data: json))
    }

    @Test("Text deltas decode")
    func textDelta() {
        let event = decode("{\"type\":\"response.output_text.delta\",\"delta\":\"Hello\"}")
        guard case .textDelta(let text)? = event else {
            Issue.record("expected textDelta, got \(String(describing: event))")
            return
        }
        #expect(text == "Hello")
    }

    @Test("Falls back to the SSE event name when payload has no type")
    func eventNameFallback() {
        let event = decode("{\"delta\":\"Hi\"}", eventName: "response.output_text.delta")
        guard case .textDelta(let text)? = event else {
            Issue.record("expected textDelta")
            return
        }
        #expect(text == "Hi")
    }

    @Test("Completed function_call output items decode with call id, name, and arguments")
    func functionCallItem() {
        let json = """
        {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_9",\
        "name":"list_exercises","arguments":"{\\"muscle_group\\":\\"quads\\"}"}}
        """
        let event = decode(json)
        guard case .functionCall(let call)? = event else {
            Issue.record("expected functionCall, got \(String(describing: event))")
            return
        }
        #expect(call.callID == "call_9")
        #expect(call.name == "list_exercises")
        #expect(call.argumentsJSON == "{\"muscle_group\":\"quads\"}")
    }

    @Test("Non-function output items done are ignored")
    func messageItemIgnored() {
        let json = "{\"type\":\"response.output_item.done\",\"item\":{\"type\":\"message\"}}"
        #expect(decode(json) == nil)
    }

    @Test("response.completed carries id, full text, and usage")
    func completed() {
        let json = """
        {"type":"response.completed","response":{"id":"resp_1","output":[\
        {"type":"message","content":[{"type":"output_text","text":"All "},{"type":"output_text","text":"done"}]}],\
        "usage":{"input_tokens":100,"output_tokens":20,"input_tokens_details":{"cached_tokens":80}}}}
        """
        let event = decode(json)
        guard case .completed(let id, let text, let usage)? = event else {
            Issue.record("expected completed, got \(String(describing: event))")
            return
        }
        #expect(id == "resp_1")
        #expect(text == "All done")
        #expect(usage == AIUsage(inputTokens: 100, outputTokens: 20, cachedTokens: 80))
    }

    @Test("Failures decode with the server's message")
    func failed() {
        let json = "{\"type\":\"response.failed\",\"response\":{\"error\":{\"message\":\"overloaded\"}}}"
        let event = decode(json)
        guard case .failed(let message)? = event else {
            Issue.record("expected failed")
            return
        }
        #expect(message == "overloaded")
    }

    @Test("Unknown events, [DONE], and malformed payloads are skipped")
    func tolerance() {
        #expect(decode("{\"type\":\"response.created\",\"response\":{}}") == nil)
        #expect(decode("{\"type\":\"response.function_call_arguments.delta\",\"delta\":\"{\\\"a\\\"\"}") == nil)
        #expect(decode("[DONE]") == nil)
        #expect(decode("not json at all") == nil)
        #expect(decode("42") == nil)
    }

    @Test("Non-streamed response object parses text and function calls together")
    func fullResponseParsing() throws {
        let json = """
        {"id":"resp_2","output":[\
        {"type":"message","content":[{"type":"output_text","text":"Let me check."}]},\
        {"type":"function_call","call_id":"c1","name":"get_training_history","arguments":"{}"},\
        {"type":"function_call","call_id":"c2","name":"get_personal_records","arguments":"{}"}]}
        """
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        guard case .object(let object) = payload else {
            Issue.record("not an object")
            return
        }
        #expect(ResponsesStreamDecoder.outputText(in: object) == "Let me check.")
        let calls = ResponsesStreamDecoder.functionCalls(in: object)
        #expect(calls.count == 2)
        #expect(calls.first?.name == "get_training_history")
        #expect(calls.last?.callID == "c2")
    }
}
