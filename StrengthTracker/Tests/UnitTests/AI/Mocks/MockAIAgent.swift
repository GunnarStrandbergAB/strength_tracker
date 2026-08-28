import Foundation
@testable import StrengthTrackerShared

/// Scripted AIAgentRunning: plays back one batch of AgentEvents per run() call
/// and records the inputs it received.
@MainActor
final class MockAIAgent: AIAgentRunning {
    struct RunInput {
        let userText: String
        let contextNotes: [String]
        let previousResponseID: String?
        let conversationID: UUID
    }

    var script: [[AgentEvent]]
    private(set) var runs: [RunInput] = []

    init(script: [[AgentEvent]] = []) {
        self.script = script
    }

    func run(
        userText: String,
        contextNotes: [String],
        previousResponseID: String?,
        conversationID: UUID
    ) -> AsyncStream<AgentEvent> {
        runs.append(RunInput(
            userText: userText,
            contextNotes: contextNotes,
            previousResponseID: previousResponseID,
            conversationID: conversationID
        ))
        let events = script.isEmpty ? [] : script.removeFirst()
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
