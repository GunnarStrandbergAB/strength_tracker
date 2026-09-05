import Testing
import Foundation
@testable import StrengthTrackerShared

// Mapper-only tests: entities are created standalone, never inserted into a
// second ModelContainer (see the hosted-test #Predicate trap).
@Suite("ChatMapper")
@MainActor
struct ChatMapperTests {

    @Test("Message round-trips through the entity")
    func messageRoundTrip() {
        let activity = ToolActivity(name: "list_exercises", label: "Browsed 12 exercises")
        let original = ChatMessage(
            role: .assistant,
            kind: .text,
            text: "Here's a summary.",
            toolActivities: [activity]
        )

        let entity = ChatMapper.toEntity(original)
        let mapped = ChatMapper.toDomain(entity)

        #expect(mapped == original)
    }

    @Test("Draft message round-trips with its payload and status")
    func draftRoundTrip() throws {
        let draft = AIDraft.exercise(Exercise(
            id: UUID(),
            name: "Cable Fly",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: true,
            isArchived: false
        ))
        let json = String(data: try JSONEncoder().encode(draft), encoding: .utf8)
        let original = ChatMessage(
            role: .assistant,
            kind: .draft,
            text: "Cable Fly",
            draftJSON: json,
            draftStatus: .pending
        )

        let mapped = ChatMapper.toDomain(ChatMapper.toEntity(original))
        #expect(mapped == original)
        let decoded = try JSONDecoder().decode(AIDraft.self, from: Data(mapped.draftJSON!.utf8))
        #expect(decoded == draft)
    }

    @Test("Undecodable draft payload degrades to plain text instead of crashing")
    func brokenDraftDegrades() {
        let entity = ChatMapper.toEntity(ChatMessage(
            role: .assistant,
            kind: .draft,
            text: "",
            draftJSON: "{\"not\": \"a draft\"}",
            draftStatus: .pending
        ))

        let mapped = ChatMapper.toDomain(entity)
        #expect(mapped.kind == .text)
        #expect(mapped.draftJSON == nil)
        #expect(!mapped.text.isEmpty)
    }

    @Test("Conversation round-trips")
    func conversationRoundTrip() {
        let original = ChatConversation(title: "Legs day planning", lastResponseID: "resp_1")
        let mapped = ChatMapper.toDomain(ChatMapper.toEntity(original))
        #expect(mapped.id == original.id)
        #expect(mapped.title == original.title)
        #expect(mapped.lastResponseID == "resp_1")
    }

    @Test("Receipt message round-trips and a broken payload degrades to text")
    func receiptRoundTrip() throws {
        let receipt = AIReceipt(scope: .historyWorkout, workoutID: UUID(), headline: "Legs · Sep 3",
                                sections: [.init(symbol: "checkmark.circle.fill", title: "Squat · set 2", lines: ["100 kg × 5", "RPE 8"])])
        let json = String(data: try JSONEncoder().encode(receipt), encoding: .utf8)
        let original = ChatMessage(role: .assistant, kind: .receipt, text: receipt.headline, receiptJSON: json)

        let mapped = ChatMapper.toDomain(ChatMapper.toEntity(original))
        #expect(mapped == original)

        let broken = ChatMapper.toEntity(ChatMessage(role: .assistant, kind: .receipt, text: "", receiptJSON: "{not json"))
        let degraded = ChatMapper.toDomain(broken)
        #expect(degraded.kind == .text)
        #expect(degraded.receiptJSON == nil)
        #expect(degraded.text == "(This receipt is no longer available.)")
    }

    @Test("Action draft round-trips with its kind payload")
    func actionDraftRoundTrip() throws {
        let action = AIPendingAction(
            kind: .removeSet(workoutID: UUID(), exerciseID: UUID(), setID: UUID()),
            title: "Remove set 3?", summaryLines: ["85 kg × 8"], confirmLabel: "Remove"
        )
        let json = String(data: try JSONEncoder().encode(AIDraft.action(action)), encoding: .utf8)
        let original = ChatMessage(role: .assistant, kind: .draft, text: action.title, draftJSON: json, draftStatus: .pending)

        let mapped = ChatMapper.toDomain(ChatMapper.toEntity(original))
        #expect(mapped == original)
        let decoded = try JSONDecoder().decode(AIDraft.self, from: Data(mapped.draftJSON!.utf8))
        #expect(decoded == .action(action))
    }
}
