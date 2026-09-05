import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("AI context note and system prompt")
@MainActor
struct WorkoutContextNoteTests {

    private func makeExercise(_ name: String) -> Exercise {
        Exercise(id: UUID(), name: name, primaryMuscleGroup: .chest, secondaryMuscleGroups: [],
                 category: .barbell, exerciseType: .weightedReps, instructions: nil, isCustom: false, isArchived: false)
    }

    private func set(_ order: Int, weight: Double?, reps: Int?, done: Bool, rpe: Double? = nil, failure: Bool = false) -> ExerciseSet {
        var set = ExerciseSet(id: UUID(), order: order, setType: .normal, weight: weight, reps: reps,
                              durationSeconds: nil, distanceMeters: nil, rpe: nil,
                              isCompleted: done, isPersonalRecord: false, completedAt: done ? Date() : nil)
        if let rpe { set.applyRPE(rpe) }
        if failure { set.setFailureFlag(true) }
        return set
    }

    @Test("Active note lists exercises with done counts, last and next sets, and repeats numbered")
    func activeNote() {
        let bench = makeExercise("Bench Press")
        let started = Date().addingTimeInterval(-48 * 60)
        let workout = Workout(
            id: UUID(), name: "Push Day", startedAt: started, completedAt: nil, notes: "Felt good", templateId: nil,
            isDeload: true, plannedSessionId: UUID(), plannedPlanId: UUID(),
            exercises: [
                WorkoutExercise(id: UUID(), exercise: bench, order: 1, supersetGroup: nil, notes: "elbows in", restTimerSeconds: nil, sets: [
                    set(1, weight: 85, reps: 8, done: true, rpe: 9),
                    set(2, weight: 85, reps: 8, done: true, rpe: 9.5, failure: true),
                    set(3, weight: 85, reps: 8, done: false)
                ]),
                WorkoutExercise(id: UUID(), exercise: bench, order: 2, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: []),
                WorkoutExercise(id: UUID(), exercise: makeExercise("Cable Fly"), order: 3, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: [
                    set(1, weight: 15, reps: 15, done: true)
                ])
            ]
        )
        let note = ActiveWorkoutContextNoteProvider.format(workout: workout, weightUnit: .kg, intensityMetric: .rpe, now: Date())
        #expect(note.hasPrefix("[App state, auto-generated: active workout \"Push Day\""))
        #expect(note.contains("(48 min ago) · deload · plan session"))
        #expect(note.contains("1. Bench Press (1): 2/3 done · last 85kg×8 RPE9.5 F · next set 3 planned 85kg×8"))
        #expect(note.contains("notes: \"elbows in\""))
        #expect(note.contains("2. Bench Press (2): 0/0 done"))
        #expect(note.contains("3. Cable Fly: 1/1 done · last 15kg×15"))
        #expect(note.contains("Workout notes: \"Felt good\""))
        #expect(note.hasSuffix("Weights in kg. Refer to exercises by name and sets by 1-based number.]"))
    }

    @Test("Note uses the display unit and metric, and renders drop sets compactly")
    func noteUnits() {
        var drop = set(1, weight: 100, reps: 5, done: true, rpe: 8)
        drop.applyDropSets([DropSetEntry(weight: 100, reps: 5, rpe: 8), DropSetEntry(weight: 80, reps: 6)])
        let workout = Workout(
            id: UUID(), name: "W", startedAt: Date(), completedAt: nil, notes: nil, templateId: nil,
            exercises: [WorkoutExercise(id: UUID(), exercise: makeExercise("Squat"), order: 1, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: [drop])]
        )
        let note = ActiveWorkoutContextNoteProvider.format(workout: workout, weightUnit: .lbs, intensityMetric: .rir, now: Date())
        #expect(note.contains("last 220.46×5→176.37×6 RIR2"))
        #expect(note.contains("Weights in lbs."))
    }

    @Test("Provider reports no active workout when the ViewModel is idle")
    func idleNote() {
        let vm = WorkoutViewModel(workoutRepository: InMemoryWorkoutRepository(), templateRepository: InMemoryTemplateRepository(), healthKitService: NoOpHealthKitService())
        let provider = ActiveWorkoutContextNoteProvider(workoutViewModel: vm, userPreferencesService: UserPreferencesService())
        #expect(provider.note() == "[App state, auto-generated: no active workout.]")
    }

    @Test("System prompt describes the write tools, the unit word and the intensity metric")
    func prompt() {
        let prompt = AISystemPrompt.build(weightUnit: .lbs, intensityMetric: .rir, memories: ["Squats hurt my knee"])
        #expect(!prompt.contains("cannot modify"))
        #expect(prompt.contains("to_failure"))
        #expect(prompt.contains("log_set"))
        #expect(prompt.contains("means lbs"))
        #expect(prompt.contains("intensity as RIR"))
        #expect(prompt.contains("[App state"))
        #expect(prompt.contains("Squats hurt my knee"))
    }
}
