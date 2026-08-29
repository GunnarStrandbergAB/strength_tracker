import Foundation

/// Events emitted while running one user turn (which may span several model
/// round-trips when tools are called).
public enum AgentEvent: Sendable {
    case assistantDelta(String)
    case toolStarted(name: String)
    case toolFinished(ToolActivity)
    case draftProduced(AIDraft)
    case turnCompleted(responseID: String, text: String, activities: [ToolActivity])
    case failed(message: String, conversationExpired: Bool)
}

/// Seam for AIChatViewModel so tests can script agent events without the network.
@MainActor
public protocol AIAgentRunning: Sendable {
    func run(
        userText: String,
        contextNotes: [String],
        previousResponseID: String?,
        conversationID: UUID
    ) -> AsyncStream<AgentEvent>
}

/// The agent loop: stream a model turn, execute requested tools, feed results
/// back, repeat until the model answers in plain text (or the iteration cap hits).
@MainActor
public final class AIAgentService: AIAgentRunning {

    /// Tool round-trips per user turn before the model is told to wrap up.
    static let maxIterations = 6

    private let client: any AIChatClient
    private let registry: AIToolRegistry
    private let model: String
    private let instructionsProvider: @MainActor () -> String

    public init(
        client: any AIChatClient,
        registry: AIToolRegistry,
        model: String = "grok-4.6",
        instructionsProvider: @escaping @MainActor () -> String
    ) {
        self.client = client
        self.registry = registry
        self.model = model
        self.instructionsProvider = instructionsProvider
    }

    public func run(
        userText: String,
        contextNotes: [String],
        previousResponseID: String?,
        conversationID: UUID
    ) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                await self.runTurn(
                    userText: userText,
                    contextNotes: contextNotes,
                    previousResponseID: previousResponseID,
                    conversationID: conversationID,
                    continuation: continuation
                )
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runTurn(
        userText: String,
        contextNotes: [String],
        previousResponseID: String?,
        conversationID: UUID,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async {
        let instructions = instructionsProvider()
        var input: [AIInputItem] = contextNotes.map { .message(role: "user", content: $0) }
        input.append(.user(userText))

        var previousID = previousResponseID
        var accumulatedText = ""
        var activities: [ToolActivity] = []
        var iteration = 0
        // Full turn history for stateless replay if the server loses our state
        // (expired previous_response_id, key rotation, …). Echoed function_call
        // items must precede their function_call_output with the same call_id.
        var replayItems = input
        var usedStatelessFallback = false

        while true {
            iteration += 1
            let finalRound = iteration > Self.maxIterations
            if finalRound {
                let wrapUp = AIInputItem.message(
                    role: "user",
                    content: "[Tool budget exhausted — answer now with the information you already have.]"
                )
                input.append(wrapUp)
                replayItems.append(wrapUp)
            }

            var functionCalls: [AIFunctionCall] = []
            var completedID: String?
            var completedText = ""

            var attemptInput = input
            var attemptPreviousID = previousID
            streaming: while true {
                let request = AIRequest(
                    model: model,
                    instructions: instructions,
                    input: attemptInput,
                    previousResponseID: attemptPreviousID,
                    tools: finalRound ? [] : registry.definitions,
                    conversationID: conversationID
                )
                do {
                    for try await event in client.stream(request) {
                        try Task.checkCancellation()
                        switch event {
                        case .textDelta(let delta):
                            accumulatedText += delta
                            continuation.yield(.assistantDelta(delta))
                        case .functionCall(let call):
                            functionCalls.append(call)
                        case .completed(let responseID, let fullText, _):
                            completedID = responseID
                            completedText = fullText
                        case .failed(let message):
                            continuation.yield(.failed(message: message, conversationExpired: false))
                            return
                        }
                    }
                    break streaming
                } catch is CancellationError {
                    return
                } catch AIClientError.previousResponseNotFound
                    where attemptPreviousID != nil && !usedStatelessFallback {
                    // Server-side state is gone — replay the whole turn statelessly.
                    // The HTTP error arrives before any stream events, so nothing
                    // was yielded for this attempt yet.
                    usedStatelessFallback = true
                    attemptPreviousID = nil
                    attemptInput = replayItems
                } catch let error as AIClientError {
                    continuation.yield(.failed(
                        message: error.userMessage,
                        conversationExpired: error == .previousResponseNotFound
                    ))
                    return
                } catch {
                    continuation.yield(.failed(message: error.localizedDescription, conversationExpired: false))
                    return
                }
            }

            guard let responseID = completedID, !responseID.isEmpty else {
                continuation.yield(.failed(
                    message: "The stream ended without completing.", conversationExpired: false
                ))
                return
            }

            // If streaming deltas never arrived (unrecognized event names), fall
            // back to the completed response's full text.
            if accumulatedText.isEmpty && !completedText.isEmpty {
                accumulatedText = completedText
                continuation.yield(.assistantDelta(completedText))
            }

            if functionCalls.isEmpty {
                continuation.yield(.turnCompleted(
                    responseID: responseID, text: accumulatedText, activities: activities
                ))
                return
            }

            var outputs: [AIInputItem] = []
            for call in functionCalls {
                if Task.isCancelled { return }
                continuation.yield(.toolStarted(name: call.name))
                let result = await execute(call)
                let activity = ToolActivity(name: call.name, label: result.activityLabel)
                activities.append(activity)
                continuation.yield(.toolFinished(activity))
                if let draft = result.draft {
                    continuation.yield(.draftProduced(draft))
                }
                outputs.append(.functionCallOutput(callID: call.callID, output: result.outputForModel))
            }

            replayItems += functionCalls.map {
                .functionCall(callID: $0.callID, name: $0.name, argumentsJSON: $0.argumentsJSON)
            }
            replayItems += outputs
            input = outputs
            previousID = responseID
        }
    }

    private func execute(_ call: AIFunctionCall) async -> AIToolResult {
        guard let tool = registry.tool(named: call.name) else {
            return AIToolResult(
                outputForModel: #"{"error": "Unknown tool \#(call.name)"}"#,
                activityLabel: "Unknown tool \(call.name)"
            )
        }
        do {
            return try await tool.call(argumentsJSON: call.argumentsJSON)
        } catch let error as AIToolError {
            return AIToolResult(
                outputForModel: toolErrorJSON(error.message),
                activityLabel: "\(call.name) failed"
            )
        } catch {
            return AIToolResult(
                outputForModel: toolErrorJSON(error.localizedDescription),
                activityLabel: "\(call.name) failed"
            )
        }
    }

    private func toolErrorJSON(_ message: String) -> String {
        let payload: JSONValue = .object(["error": .string(message)])
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"error": "tool failed"}"#
        }
        return json
    }
}
