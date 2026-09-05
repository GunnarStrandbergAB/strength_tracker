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
    /// The draft message currently being saved (disables its card's buttons).
    public private(set) var savingDraftID: UUID?
    public var errorMessage: String?

    // MARK: - Dependencies

    private let agent: any AIAgentRunning
    private let chatRepository: any ChatRepository
    private let userPreferencesService: UserPreferencesService

    /// Routes accepted drafts into the app (wired by AppContainer).
    public var onSaveDraft: (@MainActor (AIDraft) async throws -> Void)?
    /// Per-turn app-state note (e.g. the active workout), prepended to every
    /// turn's input because the system prompt is frozen per conversation.
    public var contextNoteProvider: (@MainActor () -> String?)?

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
                replaceMessage(last)
                persistMessage(last, update: true)
            }
        }
    }

    // MARK: - Drafts

    public func saveDraft(messageID: UUID) async {
        // Re-entrancy guard: the card's Save stays tappable until this returns.
        guard savingDraftID == nil,
              let message = messages.first(where: { $0.id == messageID }),
              message.draftStatus == .pending,
              let draft = decodeDraft(message) else { return }
        savingDraftID = messageID
        defer { savingDraftID = nil }
        do {
            try await onSaveDraft?(draft)
            // The object is saved — persist the accepted status unconditionally
            // (even if the visible chat changed during the await, the stored
            // card must never re-arm a duplicate save after relaunch).
            var accepted = message
            accepted.draftStatus = .accepted
            persistMessage(accepted, update: true)
            // Update the in-memory list only if the message is still shown.
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].draftStatus = .accepted
            }
            pendingContextNotes.append(acceptanceNote(for: draft, accepted: true))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func discardDraft(messageID: UUID) {
        guard savingDraftID != messageID,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].draftStatus == .pending else { return }
        messages[index].draftStatus = .discarded
        persistMessage(messages[index], update: true)
        if let draft = decodeDraft(messages[index]) {
            pendingContextNotes.append(acceptanceNote(for: draft, accepted: false))
        }
    }

    public func decodeDraft(_ message: ChatMessage) -> AIDraft? {
        guard message.kind == .draft, let json = message.draftJSON else { return nil }
        return try? JSONDecoder().decode(AIDraft.self, from: Data(json.utf8))
    }

    public func decodeReceipt(_ message: ChatMessage) -> AIReceipt? {
        guard message.kind == .receipt, let json = message.receiptJSON else { return nil }
        return try? JSONDecoder().decode(AIReceipt.self, from: Data(json.utf8))
    }

    private func acceptanceNote(for draft: AIDraft, accepted: Bool) -> String {
        switch draft {
        case .action(let action):
            return accepted
                ? "[User confirmed and the app executed the action '\(action.title)'.]"
                : "[User declined the action '\(action.title)'. Nothing was changed.]"
        default:
            return accepted
                ? "[User accepted the proposed \(draftNoun(draft)) '\(draft.title)'.]"
                : "[User discarded the proposed \(draftNoun(draft)) '\(draft.title)'.]"
        }
    }

    // MARK: - Turn execution

    private func runTurn(userText: String) async {
        let conversation = await ensureConversation(firstMessage: userText)

        let userMessage = ChatMessage(role: .user, text: userText)
        messages.append(userMessage)
        persistMessage(userMessage)

        var notes: [String] = []
        if let stateNote = contextNoteProvider?() {
            notes.append(stateNote)
        }
        notes += pendingContextNotes
        pendingContextNotes = []

        var assistantMessage: ChatMessage?
        /// The receipt card consecutive write receipts merge into.
        var receiptMessage: ChatMessage?

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
                    replaceMessage(message)
                } else {
                    let message = ChatMessage(role: .assistant, text: delta)
                    assistantMessage = message
                    messages.append(message)
                    persistMessage(message)
                    // Text after a card: later receipts start a new card.
                    receiptMessage = nil
                }

            case .toolStarted(let name):
                activeToolName = name

            case .toolFinished(let activity):
                activeToolName = nil
                if var message = assistantMessage {
                    message.toolActivities.append(activity)
                    assistantMessage = message
                    replaceMessage(message)
                } else if var card = receiptMessage {
                    // Chips between merged receipt sections hang on the card itself.
                    card.toolActivities.append(activity)
                    receiptMessage = card
                    replaceMessage(card)
                    persistMessage(card, update: true)
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
                    receiptMessage = nil
                    messages.append(draftMessage)
                    persistMessage(draftMessage)
                }

            case .receiptProduced(let receipt):
                if var card = receiptMessage,
                   var existing = decodeReceipt(card),
                   existing.canMerge(receipt) {
                    existing.merge(receipt)
                    if let json = encode(existing) {
                        card.receiptJSON = json
                        card.text = existing.headline
                        receiptMessage = card
                        replaceMessage(card)
                        persistMessage(card, update: true)
                    }
                } else if let json = encode(receipt) {
                    if var message = assistantMessage, message.text.isEmpty {
                        // A chip-only bubble (tool ran before any text): turn it
                        // into the card so the chips sit on the receipt.
                        message.kind = .receipt
                        message.text = receipt.headline
                        message.receiptJSON = json
                        assistantMessage = nil
                        receiptMessage = message
                        replaceMessage(message)
                        persistMessage(message, update: true)
                    } else {
                        let card = ChatMessage(
                            role: .assistant, kind: .receipt, text: receipt.headline,
                            receiptJSON: json
                        )
                        // The card becomes the latest message; further text deltas
                        // start a fresh bubble after it.
                        if let message = assistantMessage {
                            persistMessage(message, update: true)
                        }
                        assistantMessage = nil
                        receiptMessage = card
                        messages.append(card)
                        persistMessage(card)
                    }
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
                // Later deltas must start a fresh bubble, never overwrite the error.
                assistantMessage = nil
                receiptMessage = nil
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

    /// Replaces a message by id — never by positional index, which can go
    /// stale whenever the array shrinks.
    private func replaceMessage(_ message: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index] = message
    }

    // MARK: - Persistence (fire-and-forget; chat must never block on disk)

    private func persistMessage(_ message: ChatMessage, update: Bool = false) {
        let repository = chatRepository
        if update {
            // Updates address the message by id — they must go through even
            // when the visible conversation has changed (e.g. draft accepted
            // while the user already started a new chat).
            Task { try? await repository.updateMessage(message) }
            return
        }
        guard let conversationID = conversation?.id else { return }
        Task { try? await repository.appendMessage(message, to: conversationID) }
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
        case .action: return "action"
        }
    }

    private func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
