#if canImport(WidgetKit)
import AppIntents
import WidgetKit
import StrengthTrackerShared

// MARK: - Complete Set Intent

struct CompleteSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Set"
    static let description: IntentDescription = "Mark the next set as completed"

    func perform() async throws -> some IntentResult {
        let service = WidgetDataService()
        let data = service.readWidgetData()

        guard let active = data.activeWorkout else {
            return .result()
        }

        // Record pending completion for the app to persist
        let completion = WidgetPendingCompletion(
            exerciseId: active.currentExerciseId,
            setIndex: active.completedSets,
            completedAt: Date()
        )
        service.appendPendingCompletion(completion)

        // Optimistically update widget state
        let newCompleted = active.completedSets + 1
        let updated = WidgetActiveWorkout(
            workoutName: active.workoutName,
            currentExerciseName: active.currentExerciseName,
            currentExerciseId: active.currentExerciseId,
            completedSets: newCompleted,
            totalPlannedSets: active.totalPlannedSets,
            startedAt: active.startedAt,
            isResting: true,
            restEndDate: Date().addingTimeInterval(90), // default 90s rest
            nextSetWeight: active.nextSetWeight,
            nextSetReps: active.nextSetReps,
            nextExerciseName: active.nextExerciseName
        )
        service.updateActiveWorkoutState(updated)

        return .result()
    }
}

// MARK: - Skip Exercise Intent

struct SkipExerciseIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Exercise"
    static let description: IntentDescription = "Skip to the next exercise"

    func perform() async throws -> some IntentResult {
        let service = WidgetDataService()
        let data = service.readWidgetData()

        guard let active = data.activeWorkout, let nextName = active.nextExerciseName else {
            return .result()
        }

        // Update widget to show next exercise
        let updated = WidgetActiveWorkout(
            workoutName: active.workoutName,
            currentExerciseName: nextName,
            currentExerciseId: active.currentExerciseId,
            completedSets: active.completedSets,
            totalPlannedSets: active.totalPlannedSets,
            startedAt: active.startedAt,
            isResting: false,
            restEndDate: nil,
            nextSetWeight: nil,
            nextSetReps: nil,
            nextExerciseName: nil
        )
        service.updateActiveWorkoutState(updated)

        return .result()
    }
}

// MARK: - Start Workout Intent

struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Workout"
    static let description: IntentDescription = "Open the app to start a workout"
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Template ID")
    var templateId: String?

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Skip Rest Timer Intent

struct SkipRestTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Rest"
    static let description: IntentDescription = "Skip the rest timer"

    func perform() async throws -> some IntentResult {
        let service = WidgetDataService()
        let data = service.readWidgetData()

        guard let active = data.activeWorkout else {
            return .result()
        }

        let updated = WidgetActiveWorkout(
            workoutName: active.workoutName,
            currentExerciseName: active.currentExerciseName,
            currentExerciseId: active.currentExerciseId,
            completedSets: active.completedSets,
            totalPlannedSets: active.totalPlannedSets,
            startedAt: active.startedAt,
            isResting: false,
            restEndDate: nil,
            nextSetWeight: active.nextSetWeight,
            nextSetReps: active.nextSetReps,
            nextExerciseName: active.nextExerciseName
        )
        service.updateActiveWorkoutState(updated)

        return .result()
    }
}

// MARK: - Add Rest Time Intent

struct AddRestTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add 15 Seconds"
    static let description: IntentDescription = "Add 15 seconds to the rest timer"

    func perform() async throws -> some IntentResult {
        let service = WidgetDataService()
        let data = service.readWidgetData()

        guard let active = data.activeWorkout, active.isResting, let endDate = active.restEndDate else {
            return .result()
        }

        let updated = WidgetActiveWorkout(
            workoutName: active.workoutName,
            currentExerciseName: active.currentExerciseName,
            currentExerciseId: active.currentExerciseId,
            completedSets: active.completedSets,
            totalPlannedSets: active.totalPlannedSets,
            startedAt: active.startedAt,
            isResting: true,
            restEndDate: endDate.addingTimeInterval(15),
            nextSetWeight: active.nextSetWeight,
            nextSetReps: active.nextSetReps,
            nextExerciseName: active.nextExerciseName
        )
        service.updateActiveWorkoutState(updated)

        return .result()
    }
}
#endif
