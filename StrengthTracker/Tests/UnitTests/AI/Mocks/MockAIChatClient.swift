import Foundation
@testable import StrengthTrackerShared

/// Scripted AIChatClient: each call to stream() plays back the next event batch
/// and records the request it was given.
final class MockAIChatClient: AIChatClient, @unchecked Sendable {
    enum ScriptedTurn {
        case events([AIStreamEvent])
        case failure(Error)
    }

    private let lock = NSLock()
    private var script: [ScriptedTurn]
    private(set) var requests: [AIRequest] = []
    var validateKeyError: Error?

    init(script: [ScriptedTurn]) {
        self.script = script
    }

    private func nextTurn(recording request: AIRequest) -> ScriptedTurn {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        guard !script.isEmpty else {
            return .events([.completed(responseID: "resp_out_of_script", fullText: "", usage: nil)])
        }
        return script.removeFirst()
    }

    func respond(_ request: AIRequest) async throws -> AIResponse {
        switch nextTurn(recording: request) {
        case .failure(let error):
            throw error
        case .events(let events):
            var text = ""
            var calls: [AIFunctionCall] = []
            var id = ""
            for event in events {
                switch event {
                case .textDelta(let delta): text += delta
                case .functionCall(let call): calls.append(call)
                case .completed(let responseID, let fullText, _):
                    id = responseID
                    if text.isEmpty { text = fullText }
                case .failed: break
                }
            }
            return AIResponse(id: id, text: text, functionCalls: calls)
        }
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let turn = nextTurn(recording: request)
        return AsyncThrowingStream { continuation in
            switch turn {
            case .failure(let error):
                continuation.finish(throwing: error)
            case .events(let events):
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    func validateKey() async throws {
        if let validateKeyError { throw validateKeyError }
    }
}
