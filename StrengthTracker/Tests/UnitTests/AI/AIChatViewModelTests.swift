import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("AIChatViewModel")
@MainActor
struct AIChatViewModelTests {

    private func makeViewModel(
        script: [[AgentEvent]]
    ) -> (AIChatViewModel, MockAIAgent, InMemoryChatRepository) {
        let agent = MockAIAgent(script: script)
        let repository = InMemoryChatRepository()
        let viewModel = AIChatViewModel(
            agent: agent,
            chatRepository: repository,
            userPreferencesService: UserPreferencesService()
        )
        return (viewModel, agent, repository)
    }

    private func waitForTurnEnd(_ viewModel: AIChatViewModel) async {
        for _ in 0..<200 where viewModel.isStreaming {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        // Let fire-and-forget persistence tasks drain.
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    private func makeDraft() -> AIDraft {
        .exercise(Exercise(
            id: UUID(),
            name: "Cable Fly",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: true,
            isArchived: false
        ))
    }

    @Test("Sending appends user and assistant messages and persists the conversation")
    func basicSend() async {
        let (viewModel, agent, repository) = makeViewModel(script: [[
            .assistantDelta("Hi "),
            .assistantDelta("Gunnar"),
            .turnCompleted(responseID: "resp_1", text: "Hi Gunnar", activities: [])
        ]])

        viewModel.send("Hello")
        await waitForTurnEnd(viewModel)

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.messages[0].text == "Hello")
        #expect(viewModel.messages[1].role == .assistant)
        #expect(viewModel.messages[1].text == "Hi Gunnar")
        #expect(!viewModel.isStreaming)

        let conversations = try? await repository.fetchConversations()
        #expect(conversations?.count == 1)
        #expect(conversations?.first?.lastResponseID == "resp_1")
        #expect(agent.runs.count == 1)
        #expect(agent.runs[0].previousResponseID == nil)
    }

    @Test("Second turn continues with the previous response id")
    func continuation() async {
        let (viewModel, agent, _) = makeViewModel(script: [
            [.assistantDelta("One"), .turnCompleted(responseID: "resp_1", text: "One", activities: [])],
            [.assistantDelta("Two"), .turnCompleted(responseID: "resp_2", text: "Two", activities: [])]
        ])

        viewModel.send("First")
        await waitForTurnEnd(viewModel)
        viewModel.send("Second")
        await waitForTurnEnd(viewModel)

        #expect(agent.runs.count == 2)
        #expect(agent.runs[1].previousResponseID == "resp_1")
        #expect(agent.runs[1].conversationID == agent.runs[0].conversationID)
    }

    @Test("Tool activity attaches chips to the assistant message")
    func toolActivities() async {
        let activity = ToolActivity(name: "get_training_history", label: "Read 12 workouts")
        let (viewModel, _, _) = makeViewModel(script: [[
            .toolStarted(name: "get_training_history"),
            .toolFinished(activity),
            .assistantDelta("You trained hard."),
            .turnCompleted(responseID: "resp_1", text: "You trained hard.", activities: [activity])
        ]])

        viewModel.send("Summarize my training")
        await waitForTurnEnd(viewModel)

        let assistant = viewModel.messages.last
        #expect(assistant?.toolActivities == [activity])
        #expect(assistant?.text == "You trained hard.")
        #expect(viewModel.activeToolName == nil)
    }

    @Test("Drafts become pending draft messages")
    func draftMessage() async {
        let draft = makeDraft()
        let (viewModel, _, repository) = makeViewModel(script: [[
            .assistantDelta("How about this?"),
            .draftProduced(draft),
            .turnCompleted(responseID: "resp_1", text: "How about this?", activities: [])
        ]])

        viewModel.send("Propose an exercise")
        await waitForTurnEnd(viewModel)

        let draftMessage = viewModel.messages.first { $0.kind == .draft }
        #expect(draftMessage != nil)
        #expect(draftMessage?.draftStatus == .pending)
        #expect(viewModel.decodeDraft(draftMessage!) == draft)

        let conversationID = try? await repository.fetchConversations().first?.id
        let persisted = try? await repository.fetchMessages(conversationID: conversationID ?? UUID())
        #expect(persisted?.contains { $0.kind == .draft } == true)
    }

    @Test("Saving a draft routes it and queues an acceptance note for the next turn")
    func saveDraft() async {
        let draft = makeDraft()
        let (viewModel, agent, _) = makeViewModel(script: [
            [.draftProduced(draft), .turnCompleted(responseID: "resp_1", text: "", activities: [])],
            [.turnCompleted(responseID: "resp_2", text: "Nice", activities: [])]
        ])

        var savedDrafts: [AIDraft] = []
        viewModel.onSaveDraft = { savedDrafts.append($0) }

        viewModel.send("Propose an exercise")
        await waitForTurnEnd(viewModel)

        let draftMessage = viewModel.messages.first { $0.kind == .draft }!
        await viewModel.saveDraft(messageID: draftMessage.id)

        #expect(savedDrafts == [draft])
        #expect(viewModel.messages.first { $0.kind == .draft }?.draftStatus == .accepted)

        viewModel.send("Thanks")
        await waitForTurnEnd(viewModel)
        #expect(agent.runs[1].contextNotes == ["[User accepted the proposed exercise 'Cable Fly'.]"])
    }

    @Test("saveDraft is not re-entrant: a second call while in flight is a no-op")
    func saveDraftReentrancy() async {
        let draft = makeDraft()
        let (viewModel, _, _) = makeViewModel(script: [
            [.draftProduced(draft), .turnCompleted(responseID: "resp_1", text: "", activities: [])]
        ])

        var saveCount = 0
        viewModel.onSaveDraft = { _ in
            saveCount += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        viewModel.send("Propose")
        await waitForTurnEnd(viewModel)
        let draftMessage = viewModel.messages.first { $0.kind == .draft }!

        async let first: Void = viewModel.saveDraft(messageID: draftMessage.id)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(viewModel.savingDraftID == draftMessage.id)
        await viewModel.saveDraft(messageID: draftMessage.id)   // double tap
        await first

        #expect(saveCount == 1)
        #expect(viewModel.savingDraftID == nil)
        #expect(viewModel.messages.first { $0.kind == .draft }?.draftStatus == .accepted)
    }

    @Test("saveDraft survives the messages array changing during the save")
    func saveDraftStaleIndex() async {
        let draft = makeDraft()
        let (viewModel, _, repository) = makeViewModel(script: [
            [.draftProduced(draft), .turnCompleted(responseID: "resp_1", text: "", activities: [])]
        ])

        viewModel.onSaveDraft = { [weak viewModel] _ in
            // Simulate the user clearing the chat mid-save (toolbar "New chat").
            viewModel?.startNewConversation()
        }

        viewModel.send("Propose")
        await waitForTurnEnd(viewModel)
        let conversationID = try? await repository.fetchConversations().first?.id
        let draftMessage = viewModel.messages.first { $0.kind == .draft }!

        await viewModel.saveDraft(messageID: draftMessage.id)   // must not trap
        try? await Task.sleep(nanoseconds: 30_000_000)          // let persistence drain

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.savingDraftID == nil)

        // The stored card must be marked accepted even though the visible chat
        // changed — otherwise it re-arms a duplicate save after relaunch.
        let persisted = try? await repository.fetchMessages(conversationID: conversationID ?? UUID())
        #expect(persisted?.first { $0.id == draftMessage.id }?.draftStatus == .accepted)
    }

    @Test("An already-accepted draft cannot be saved again")
    func saveDraftIdempotent() async {
        let draft = makeDraft()
        let (viewModel, _, _) = makeViewModel(script: [
            [.draftProduced(draft), .turnCompleted(responseID: "resp_1", text: "", activities: [])]
        ])
        var saveCount = 0
        viewModel.onSaveDraft = { _ in saveCount += 1 }

        viewModel.send("Propose")
        await waitForTurnEnd(viewModel)
        let draftMessage = viewModel.messages.first { $0.kind == .draft }!

        await viewModel.saveDraft(messageID: draftMessage.id)
        await viewModel.saveDraft(messageID: draftMessage.id)
        viewModel.discardDraft(messageID: draftMessage.id)      // accepted, not pending — no-op

        #expect(saveCount == 1)
        #expect(viewModel.messages.first { $0.kind == .draft }?.draftStatus == .accepted)
    }

    @Test("A delta after a failure starts a new bubble instead of overwriting the error")
    func deltaAfterFailure() async {
        let (viewModel, _, _) = makeViewModel(script: [[
            .assistantDelta("Working on it"),
            .failed(message: "tool exploded", conversationExpired: false),
            .assistantDelta("Recovered text")
        ]])

        viewModel.send("Go")
        await waitForTurnEnd(viewModel)

        let errorBubble = viewModel.messages.first { $0.kind == .error }
        #expect(errorBubble?.text == "tool exploded")
        #expect(viewModel.messages.last?.text == "Recovered text")
        #expect(viewModel.messages.last?.kind == .text)
    }

    @Test("Save failures keep the draft pending and surface an error")
    func saveDraftFailure() async {
        let draft = makeDraft()
        let (viewModel, _, _) = makeViewModel(script: [
            [.draftProduced(draft), .turnCompleted(responseID: "resp_1", text: "", activities: [])]
        ])
        struct SaveError: Error {}
        viewModel.onSaveDraft = { _ in throw SaveError() }

        viewModel.send("Propose")
        await waitForTurnEnd(viewModel)
        let draftMessage = viewModel.messages.first { $0.kind == .draft }!
        await viewModel.saveDraft(messageID: draftMessage.id)

        #expect(viewModel.messages.first { $0.kind == .draft }?.draftStatus == .pending)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("Discarding a draft marks it and queues a note")
    func discardDraft() async {
        let draft = makeDraft()
        let (viewModel, agent, _) = makeViewModel(script: [
            [.draftProduced(draft), .turnCompleted(responseID: "resp_1", text: "", activities: [])],
            [.turnCompleted(responseID: "resp_2", text: "Ok", activities: [])]
        ])

        viewModel.send("Propose")
        await waitForTurnEnd(viewModel)
        let draftMessage = viewModel.messages.first { $0.kind == .draft }!
        viewModel.discardDraft(messageID: draftMessage.id)

        #expect(viewModel.messages.first { $0.kind == .draft }?.draftStatus == .discarded)

        viewModel.send("Next")
        await waitForTurnEnd(viewModel)
        #expect(agent.runs[1].contextNotes == ["[User discarded the proposed exercise 'Cable Fly'.]"])
    }

    @Test("Failure adds an error bubble; expired conversations clear the response id")
    func expiredConversation() async {
        let (viewModel, agent, repository) = makeViewModel(script: [
            [.turnCompleted(responseID: "resp_1", text: "First", activities: []), .assistantDelta("First")],
            [.failed(message: "expired", conversationExpired: true)],
            [.turnCompleted(responseID: "resp_3", text: "Fresh", activities: [])]
        ])

        viewModel.send("One")
        await waitForTurnEnd(viewModel)
        viewModel.send("Two")
        await waitForTurnEnd(viewModel)

        #expect(viewModel.messages.last?.kind == .error)
        let conversations = try? await repository.fetchConversations()
        #expect(conversations?.first?.lastResponseID == nil)

        viewModel.send("Three")
        await waitForTurnEnd(viewModel)
        #expect(agent.runs[2].previousResponseID == nil)
    }

    @Test("Retry re-sends the last user text and drops error bubbles")
    func retry() async {
        let (viewModel, agent, _) = makeViewModel(script: [
            [.failed(message: "boom", conversationExpired: false)],
            [.assistantDelta("Recovered"), .turnCompleted(responseID: "resp_1", text: "Recovered", activities: [])]
        ])

        viewModel.send("Try this")
        await waitForTurnEnd(viewModel)
        #expect(viewModel.messages.contains { $0.kind == .error })

        viewModel.retry()
        await waitForTurnEnd(viewModel)

        #expect(!viewModel.messages.contains { $0.kind == .error })
        #expect(agent.runs.count == 2)
        #expect(agent.runs[1].userText == "Try this")
        #expect(viewModel.messages.last?.text == "Recovered")
    }

    @Test("New conversation resets state")
    func newConversation() async {
        let (viewModel, agent, _) = makeViewModel(script: [
            [.assistantDelta("Hi"), .turnCompleted(responseID: "resp_1", text: "Hi", activities: [])],
            [.turnCompleted(responseID: "resp_2", text: "Hello again", activities: [])]
        ])

        viewModel.send("One")
        await waitForTurnEnd(viewModel)
        viewModel.startNewConversation()

        #expect(viewModel.messages.isEmpty)

        viewModel.send("Two")
        await waitForTurnEnd(viewModel)
        #expect(agent.runs[1].previousResponseID == nil)
        #expect(agent.runs[1].conversationID != agent.runs[0].conversationID)
    }

    @Test("loadLatestConversation restores persisted messages")
    func loadLatest() async {
        let repository = InMemoryChatRepository()
        let conversation = ChatConversation(title: "Old chat", lastResponseID: "resp_9")
        try? await repository.createConversation(conversation)
        try? await repository.appendMessage(ChatMessage(role: .user, text: "Earlier"), to: conversation.id)

        let agent = MockAIAgent(script: [[.turnCompleted(responseID: "resp_10", text: "", activities: [])]])
        let viewModel = AIChatViewModel(
            agent: agent,
            chatRepository: repository,
            userPreferencesService: UserPreferencesService()
        )

        await viewModel.loadLatestConversation()
        #expect(viewModel.messages.map(\.text) == ["Earlier"])

        viewModel.send("Continue")
        await waitForTurnEnd(viewModel)
        #expect(agent.runs[0].previousResponseID == "resp_9")
    }

    // MARK: - Receipts, context notes, action drafts

    private func makeReceipt(workoutID: UUID, title: String) -> AIReceipt {
        AIReceipt(scope: .activeWorkout, workoutID: workoutID, headline: "Active workout · Push",
                  sections: [.init(symbol: "checkmark.circle.fill", title: title, lines: ["85 kg × 8"])])
    }

    @Test("Consecutive receipts for the same workout merge into one card")
    func receiptsMerge() async throws {
        let workoutID = UUID()
        let (viewModel, _, repository) = makeViewModel(script: [[
            .toolStarted(name: "log_set"),
            .toolFinished(ToolActivity(name: "log_set", label: "Logged set 1")),
            .receiptProduced(makeReceipt(workoutID: workoutID, title: "Bench · set 1")),
            .toolStarted(name: "log_set"),
            .toolFinished(ToolActivity(name: "log_set", label: "Logged set 2")),
            .receiptProduced(makeReceipt(workoutID: workoutID, title: "Bench · set 2")),
            .assistantDelta("Logged both."),
            .turnCompleted(responseID: "resp_1", text: "Logged both.", activities: [])
        ]])

        viewModel.send("log two sets")
        await waitForTurnEnd(viewModel)

        let cards = viewModel.messages.filter { $0.kind == .receipt }
        #expect(cards.count == 1)
        let receipt = try #require(viewModel.decodeReceipt(cards[0]))
        #expect(receipt.sections.map(\.title) == ["Bench · set 1", "Bench · set 2"])
        #expect(cards[0].toolActivities.count == 2, "chips between merged sections hang on the card")
        #expect(viewModel.messages.last?.text == "Logged both.")

        let conversationID = try #require(try await repository.fetchConversations().first?.id)
        let stored = try await repository.fetchMessages(conversationID: conversationID)
        let storedCard = try #require(stored.first { $0.kind == .receipt })
        #expect(storedCard.receiptJSON != nil)
    }

    @Test("Text between receipts, or a different workout, starts a new card")
    func receiptsSplit() async {
        let (viewModel, _, _) = makeViewModel(script: [[
            .receiptProduced(makeReceipt(workoutID: UUID(), title: "A")),
            .assistantDelta("Done. "),
            .receiptProduced(makeReceipt(workoutID: UUID(), title: "B")),
            .receiptProduced(AIReceipt(scope: .session, workoutID: nil, headline: "Finished", sections: [])),
            .turnCompleted(responseID: "resp_1", text: "Done. ", activities: [])
        ]])

        viewModel.send("go")
        await waitForTurnEnd(viewModel)

        let kinds = viewModel.messages.map(\.kind)
        #expect(kinds == [.text, .receipt, .text, .receipt, .receipt])
    }

    @Test("The app-state note precedes queued acceptance notes on every turn")
    func contextNoteOrdering() async {
        let (viewModel, agent, _) = makeViewModel(script: [
            [.draftProduced(makeDraft()), .turnCompleted(responseID: "resp_1", text: "", activities: [])],
            [.assistantDelta("ok"), .turnCompleted(responseID: "resp_2", text: "ok", activities: [])]
        ])
        viewModel.contextNoteProvider = { "[App state, auto-generated: no active workout.]" }
        viewModel.onSaveDraft = { _ in }

        viewModel.send("propose")
        await waitForTurnEnd(viewModel)
        let draftID = viewModel.messages.first { $0.kind == .draft }!.id
        await viewModel.saveDraft(messageID: draftID)
        viewModel.send("next")
        await waitForTurnEnd(viewModel)

        #expect(agent.runs[0].contextNotes == ["[App state, auto-generated: no active workout.]"])
        #expect(agent.runs[1].contextNotes.count == 2)
        #expect(agent.runs[1].contextNotes[0].hasPrefix("[App state"))
        #expect(agent.runs[1].contextNotes[1] == "[User accepted the proposed exercise 'Cable Fly'.]")
    }

    @Test("Action drafts route through onSaveDraft and produce confirm/decline notes")
    func actionDraft() async {
        let action = AIPendingAction(kind: .cancelWorkout(workoutID: UUID()), title: "Cancel 'Legs'?", summaryLines: ["3 sets"], confirmLabel: "Cancel Workout")
        let (viewModel, agent, _) = makeViewModel(script: [
            [.draftProduced(.action(action)), .turnCompleted(responseID: "resp_1", text: "", activities: [])],
            [.draftProduced(.action(action)), .turnCompleted(responseID: "resp_2", text: "", activities: [])],
            [.assistantDelta("ok"), .turnCompleted(responseID: "resp_3", text: "ok", activities: [])]
        ])
        var executed = 0
        viewModel.onSaveDraft = { draft in
            if case .action = draft { executed += 1 }
        }

        viewModel.send("cancel")
        await waitForTurnEnd(viewModel)
        let first = viewModel.messages.first { $0.kind == .draft }!.id
        await viewModel.saveDraft(messageID: first)
        #expect(executed == 1)
        #expect(viewModel.messages.first { $0.id == first }?.draftStatus == .accepted)

        viewModel.send("again")
        await waitForTurnEnd(viewModel)
        let second = viewModel.messages.last { $0.kind == .draft }!.id
        viewModel.discardDraft(messageID: second)
        viewModel.send("done")
        await waitForTurnEnd(viewModel)

        #expect(agent.runs[1].contextNotes.contains("[User confirmed and the app executed the action 'Cancel 'Legs'?'.]"))
        #expect(agent.runs[2].contextNotes.contains("[User declined the action 'Cancel 'Legs'?'. Nothing was changed.]"))
    }
}
