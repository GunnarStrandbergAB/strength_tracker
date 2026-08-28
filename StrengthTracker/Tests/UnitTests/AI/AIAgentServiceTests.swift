import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("AIAgentService")
@MainActor
struct AIAgentServiceTests {

    private final class StubTool: AITool {
        let name: String
        let description = "stub"
        let parametersSchema: JSONValue = AIToolRegistry.objectSchema(properties: [:])
        let result: Result<AIToolResult, Error>
        private(set) var receivedArguments: [String] = []

        init(name: String, result: Result<AIToolResult, Error>) {
            self.name = name
            self.result = result
        }

        func call(argumentsJSON: String) async throws -> AIToolResult {
            receivedArguments.append(argumentsJSON)
            return try result.get()
        }
    }

    private func makeService(
        script: [MockAIChatClient.ScriptedTurn],
        tools: [any AITool] = []
    ) -> (AIAgentService, MockAIChatClient) {
        let client = MockAIChatClient(script: script)
        let service = AIAgentService(
            client: client,
            registry: AIToolRegistry(tools: tools),
            instructionsProvider: { "test instructions" }
        )
        return (service, client)
    }

    private func collect(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
        var events: [AgentEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    @Test("Plain text turn forwards deltas and completes with accumulated text")
    func plainTextTurn() async {
        let (service, client) = makeService(script: [
            .events([
                .textDelta("Hello "),
                .textDelta("there"),
                .completed(responseID: "resp_1", fullText: "Hello there", usage: nil)
            ])
        ])

        let events = await collect(service.run(
            userText: "Hi", contextNotes: [], previousResponseID: nil, conversationID: UUID()
        ))

        guard case .assistantDelta("Hello ") = events.first else {
            Issue.record("expected first delta, got \(events)")
            return
        }
        guard case .turnCompleted(let id, let text, let activities) = events.last else {
            Issue.record("expected turnCompleted, got \(events)")
            return
        }
        #expect(id == "resp_1")
        #expect(text == "Hello there")
        #expect(activities.isEmpty)
        #expect(client.requests.count == 1)
        #expect(client.requests[0].instructions == "test instructions")
        #expect(client.requests[0].previousResponseID == nil)
    }

    @Test("Falls back to completed fullText when no deltas streamed")
    func fullTextFallback() async {
        let (service, _) = makeService(script: [
            .events([.completed(responseID: "resp_1", fullText: "Complete answer", usage: nil)])
        ])

        let events = await collect(service.run(
            userText: "Hi", contextNotes: [], previousResponseID: nil, conversationID: UUID()
        ))

        guard case .assistantDelta("Complete answer") = events.first else {
            Issue.record("expected fallback delta, got \(events)")
            return
        }
        guard case .turnCompleted(_, "Complete answer", _) = events.last else {
            Issue.record("expected turnCompleted with full text")
            return
        }
    }

    @Test("Tool call executes the tool and continues with its output")
    func toolCallRoundTrip() async {
        let tool = StubTool(
            name: "get_data",
            result: .success(AIToolResult(outputForModel: "{\"volume\":123}", activityLabel: "Read data"))
        )
        let (service, client) = makeService(
            script: [
                .events([
                    .functionCall(AIFunctionCall(callID: "call_1", name: "get_data", argumentsJSON: "{\"n\":5}")),
                    .completed(responseID: "resp_1", fullText: "", usage: nil)
                ]),
                .events([
                    .textDelta("Your volume is 123."),
                    .completed(responseID: "resp_2", fullText: "Your volume is 123.", usage: nil)
                ])
            ],
            tools: [tool]
        )

        let events = await collect(service.run(
            userText: "How much volume?", contextNotes: [], previousResponseID: "resp_0", conversationID: UUID()
        ))

        #expect(tool.receivedArguments == ["{\"n\":5}"])
        #expect(client.requests.count == 2)
        // Second request continues from the first response with the tool output.
        #expect(client.requests[1].previousResponseID == "resp_1")
        #expect(client.requests[1].input == [
            .functionCallOutput(callID: "call_1", output: "{\"volume\":123}")
        ])

        var sawStarted = false
        var sawFinished = false
        for event in events {
            if case .toolStarted("get_data") = event { sawStarted = true }
            if case .toolFinished(let activity) = event {
                sawFinished = true
                #expect(activity.label == "Read data")
            }
        }
        #expect(sawStarted && sawFinished)

        guard case .turnCompleted("resp_2", "Your volume is 123.", let activities) = events.last else {
            Issue.record("expected final turnCompleted, got \(events)")
            return
        }
        #expect(activities.count == 1)
    }

    @Test("Parallel tool calls all execute and return outputs in one follow-up")
    func parallelToolCalls() async {
        let toolA = StubTool(name: "a", result: .success(AIToolResult(outputForModel: "1", activityLabel: "A")))
        let toolB = StubTool(name: "b", result: .success(AIToolResult(outputForModel: "2", activityLabel: "B")))
        let (service, client) = makeService(
            script: [
                .events([
                    .functionCall(AIFunctionCall(callID: "c1", name: "a", argumentsJSON: "{}")),
                    .functionCall(AIFunctionCall(callID: "c2", name: "b", argumentsJSON: "{}")),
                    .completed(responseID: "resp_1", fullText: "", usage: nil)
                ]),
                .events([.completed(responseID: "resp_2", fullText: "done", usage: nil)])
            ],
            tools: [toolA, toolB]
        )

        _ = await collect(service.run(
            userText: "go", contextNotes: [], previousResponseID: nil, conversationID: UUID()
        ))

        #expect(client.requests[1].input == [
            .functionCallOutput(callID: "c1", output: "1"),
            .functionCallOutput(callID: "c2", output: "2")
        ])
    }

    @Test("Tool errors are reported to the model, not the user")
    func toolErrorFeedback() async {
        let tool = StubTool(name: "flaky", result: .failure(AIToolError("bad muscle_group value")))
        let (service, client) = makeService(
            script: [
                .events([
                    .functionCall(AIFunctionCall(callID: "c1", name: "flaky", argumentsJSON: "{}")),
                    .completed(responseID: "resp_1", fullText: "", usage: nil)
                ]),
                .events([.completed(responseID: "resp_2", fullText: "recovered", usage: nil)])
            ],
            tools: [tool]
        )

        let events = await collect(service.run(
            userText: "go", contextNotes: [], previousResponseID: nil, conversationID: UUID()
        ))

        // No .failed event — the loop continues.
        for event in events {
            if case .failed = event {
                Issue.record("tool error must not fail the turn")
            }
        }
        guard case .functionCallOutput(_, let output) = client.requests[1].input.first else {
            Issue.record("expected tool output")
            return
        }
        #expect(output.contains("bad muscle_group value"))
    }

    @Test("Unknown tool produces an error output for the model")
    func unknownTool() async {
        let (service, client) = makeService(script: [
            .events([
                .functionCall(AIFunctionCall(callID: "c1", name: "nope", argumentsJSON: "{}")),
                .completed(responseID: "resp_1", fullText: "", usage: nil)
            ]),
            .events([.completed(responseID: "resp_2", fullText: "ok", usage: nil)])
        ])

        _ = await collect(service.run(
            userText: "go", contextNotes: [], previousResponseID: nil, conversationID: UUID()
        ))

        guard case .functionCallOutput(_, let output) = client.requests[1].input.first else {
            Issue.record("expected output item")
            return
        }
        #expect(output.contains("Unknown tool"))
    }

    @Test("Iteration cap forces a final tool-free round")
    func iterationCap() async {
        let tool = StubTool(name: "loop", result: .success(AIToolResult(outputForModel: "{}", activityLabel: "L")))
        // Every round requests another tool call — the service must cut it off.
        var script: [MockAIChatClient.ScriptedTurn] = []
        for index in 0..<AIAgentService.maxIterations {
            script.append(.events([
                .functionCall(AIFunctionCall(callID: "c\(index)", name: "loop", argumentsJSON: "{}")),
                .completed(responseID: "resp_\(index)", fullText: "", usage: nil)
            ]))
        }
        script.append(.events([.completed(responseID: "resp_final", fullText: "capped answer", usage: nil)]))

        let (service, client) = makeService(script: script, tools: [tool])
        let events = await collect(service.run(
            userText: "go", contextNotes: [], previousResponseID: nil, conversationID: UUID()
        ))

        let finalRequest = client.requests.last
        #expect(finalRequest?.tools.isEmpty == true)
        #expect(finalRequest?.input.contains(where: { item in
            if case .message(_, let content) = item { return content.contains("Tool budget exhausted") }
            return false
        }) == true)
        guard case .turnCompleted("resp_final", let text, _) = events.last else {
            Issue.record("expected capped completion, got \(String(describing: events.last))")
            return
        }
        #expect(text == "capped answer")
    }

    @Test("Client errors surface as failed, flagging expired conversations")
    func clientErrors() async {
        let (service, _) = makeService(script: [.failure(AIClientError.previousResponseNotFound)])
        let events = await collect(service.run(
            userText: "go", contextNotes: [], previousResponseID: "resp_old", conversationID: UUID()
        ))

        guard case .failed(_, let expired) = events.last else {
            Issue.record("expected failed event")
            return
        }
        #expect(expired)
    }

    @Test("Context notes precede the user message in the input")
    func contextNotes() async {
        let (service, client) = makeService(script: [
            .events([.completed(responseID: "r", fullText: "ok", usage: nil)])
        ])
        _ = await collect(service.run(
            userText: "hello",
            contextNotes: ["[User accepted the proposed template 'Legs A'.]"],
            previousResponseID: nil,
            conversationID: UUID()
        ))

        #expect(client.requests[0].input == [
            .message(role: "user", content: "[User accepted the proposed template 'Legs A'.]"),
            .message(role: "user", content: "hello")
        ])
    }
}
