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
}
