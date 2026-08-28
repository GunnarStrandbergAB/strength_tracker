import Foundation
import Observation

@MainActor
@Observable
public final class AIChatViewModel {

    // MARK: - Observable state

    public private(set) var messages: [ChatMessage] = []
    public private(set) var isStreaming = false
    /// Name of the tool currently executing, for the live activity chip.
    public private(set) var activeToolName: String?
    public var errorMessage: String?

    // MARK: - Dependencies

    private let agent: any AIAgentRunning
    private let chatRepository: any ChatRepository
    private let userPreferencesService: UserPreferencesService

    /// Routes accepted drafts into the app (wired by AppContainer).
    public var onSaveDraft: (@MainActor (AIDraft) async throws -> Void)?

    // MARK: - Private state

    private var conversation: ChatConversation?
    /// Notes queued for the next turn (e.g. "[User accepted the proposed template 'Legs A']").
    private var pendingContextNotes: [String] = []
    private var currentTask: Task<Void, Never>?
    private var lastUserText: String?

    public init(
        agent: any AIAgentRunning,
        chatRepository: any ChatRepository,
        userPreferencesService: UserPreferencesService
    ) {
        self.agent = agent
        self.chatRepository = chatRepository
        self.userPreferencesService = userPreferencesService
    }

    // MARK: - Conversation lifecycle

    public func loadLatestConversation() async {
        guard conversation == nil else { return }
        do {
            if let latest = try await chatRepository.fetchConversations().first {
                conversation = latest
                messages = try await chatRepository.fetchMessages(conversationID: latest.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func startNewConversation() {
        stop()
        conversation = nil
        messages = []
        pendingContextNotes = []
        errorMessage = nil
        lastUserText = nil
    }

    // MARK: - Sending

    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        lastUserText = trimmed
        errorMessage = nil
        isStreaming = true

        currentTask = Task { [weak self] in
            await self?.runTurn(userText: trimmed)
        }
    }

    /// Re-sends the last user message after a failure.
    public func retry() {
        guard let lastUserText, !isStreaming else { return }
        messages.removeAll { $0.kind == .error }
        send(lastUserText)
    }

    public func stop() {
        currentTask?.cancel()
        currentTask = nil
        if isStreaming {
            isStreaming = false
            activeToolName = nil
            // Keep whatever partial text arrived, marked as stopped.
            if var last = messages.last, last.role == .assistant, last.kind == .text, !last.text.isEmpty {
                last.text += "\n\n*(stopped)*"
                messages[messages.count - 1] = last
                persistMessage(last, update: true)
            }
        }
    }

    // MARK: - Drafts

    public func saveDraft(messageID: UUID) async {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              let draft = decodeDraft(messages[index]) else { return }
        do {
            try await onSaveDraft?(draft)
            messages[index].draftStatus = .accepted
            persistMessage(messages[index], update: true)
            pendingContextNotes.append("[User accepted the proposed \(draftNoun(draft)) '\(draft.title)'.]")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func discardDraft(messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].draftStatus = .discarded
        persistMessage(messages[index], update: true)
        if let draft = decodeDraft(messages[index]) {
            pendingContextNotes.append("[User discarded the proposed \(draftNoun(draft)) '\(draft.title)'.]")
        }
    }

    public func decodeDraft(_ message: ChatMessage) -> AIDraft? {
        guard message.kind == .draft, let json = message.draftJSON else { return nil }
        return try? JSONDecoder().decode(AIDraft.self, from: Data(json.utf8))
    }

    // MARK: - Turn execution

    private func runTurn(userText: String) async {
        let conversation = await ensureConversation(firstMessage: userText)

        let userMessage = ChatMessage(role: .user, text: userText)
        messages.append(userMessage)
        persistMessage(userMessage)

        let notes = pendingContextNotes
        pendingContextNotes = []

        var assistantMessage: ChatMessage?

        let events = agent.run(
            userText: userText,
            contextNotes: notes,
            previousResponseID: conversation.lastResponseID,
            conversationID: conversation.id
        )

        for await event in events {
            if Task.isCancelled { break }
            switch event {
            case .assistantDelta(let delta):
                if var message = assistantMessage {
                    message.text += delta
                    assistantMessage = message
                    messages[messages.count - 1] = message
                } else {
                    let message = ChatMessage(role: .assistant, text: delta)
                    assistantMessage = message
                    messages.append(message)
                    persistMessage(message)
                }

            case .toolStarted(let name):
                activeToolName = name

            case .toolFinished(let activity):
                activeToolName = nil
                if var message = assistantMessage {
                    message.toolActivities.append(activity)
                    assistantMessage = message
                    messages[messages.count - 1] = message
                } else {
                    // Chip with no text yet: hang activities on an empty assistant message.
                    let message = ChatMessage(role: .assistant, text: "", toolActivities: [activity])
                    assistantMessage = message
                    messages.append(message)
                    persistMessage(message)
                }

            case .draftProduced(let draft):
                if let data = try? JSONEncoder().encode(draft),
                   let json = String(data: data, encoding: .utf8) {
                    let draftMessage = ChatMessage(
                        role: .assistant, kind: .draft, text: draft.title,
                        draftJSON: json, draftStatus: .pending
                    )
                    // The draft card becomes the latest message; further text
                    // deltas start a fresh bubble after it.
                    if let message = assistantMessage {
                        persistMessage(message, update: true)
                    }
                    assistantMessage = nil
                    messages.append(draftMessage)
                    persistMessage(draftMessage)
                }

            case .turnCompleted(let responseID, _, _):
                if let message = assistantMessage {
                    persistMessage(message, update: true)
                }
                var updated = conversation
                updated.lastResponseID = responseID
                updated.updatedAt = Date()
                self.conversation = updated
                persistConversation(updated)

            case .failed(let message, let conversationExpired):
                if conversationExpired {
                    // Server-side state is gone (30-day TTL). Clear the pointer so
                    // the next send starts a fresh server conversation.
                    var updated = conversation
                    updated.lastResponseID = nil
                    self.conversation = updated
                    persistConversation(updated)
                }
                let errorBubble = ChatMessage(
                    role: .assistant, kind: .error,
                    text: conversationExpired
                        ? "This conversation expired on the server. Tap retry to continue in a fresh session."
                        : message
                )
                messages.append(errorBubble)
            }
        }

        activeToolName = nil
        isStreaming = false
    }

    private func ensureConversation(firstMessage: String) async -> ChatConversation {
        if let conversation { return conversation }
        let title = String(firstMessage.prefix(60))
        let new = ChatConversation(title: title)
        conversation = new
        do {
            try await chatRepository.createConversation(new)
        } catch {
            errorMessage = error.localizedDescription
        }
        return new
    }

    // MARK: - Persistence (fire-and-forget; chat must never block on disk)

    private func persistMessage(_ message: ChatMessage, update: Bool = false) {
        guard let conversationID = conversation?.id else { return }
        let repository = chatRepository
        Task {
            if update {
                try? await repository.updateMessage(message)
            } else {
                try? await repository.appendMessage(message, to: conversationID)
            }
        }
    }

    private func persistConversation(_ conversation: ChatConversation) {
        let repository = chatRepository
        Task {
            try? await repository.updateConversation(conversation)
        }
    }

    private func draftNoun(_ draft: AIDraft) -> String {
        switch draft {
        case .exercise: return "exercise"
        case .template: return "template"
        case .plan: return "training plan"
        }
    }
}
