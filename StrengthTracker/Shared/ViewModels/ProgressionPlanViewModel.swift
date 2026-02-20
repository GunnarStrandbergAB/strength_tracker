#if canImport(SwiftData)
import Foundation
import Observation

// MARK: - Draft Exercise Helper

public struct DraftPlanExercise: Identifiable, Sendable {
    public let id: UUID
    public let exercise: Exercise
    public var oneRM: Double
    public var oneRMSource: PlanExercise.OneRMSource

    public init(exercise: Exercise, oneRM: Double = 0, oneRMSource: PlanExercise.OneRMSource = .userInput) {
        self.id = exercise.id
        self.exercise = exercise
        self.oneRM = oneRM
        self.oneRMSource = oneRMSource
    }
}

// MARK: - ProgressionPlanViewModel

@MainActor
@Observable
public final class ProgressionPlanViewModel {

    // MARK: - Active Plan State

    public var activePlan: ProgressionPlan?
    public var planProgress: PlanProgress?
    public var isLoading = false

    // MARK: - Creation Wizard Draft State

    public var draftStep: Int = 1
    public var draftStatus: TrainingStatus = .beginner
    public var draftStatusIsDetecting = false
    public var draftGoal: TrainingGoal = .hypertrophy
    public var draftProgramType: ProgramType = .linear
    public var draftFrequency: Int = 3
    public var draftSelectedExercises: [DraftPlanExercise] = []
    public var draftPlanName: String = ""
    public var isSavingPlan = false
    public var errorMessage: String?

    // MARK: - Dependencies

    private let progressionPlanRepository: any ProgressionPlanRepository
    private let trainingStatusDetector: TrainingStatusDetector
    private let programDesignService: ProgramDesignService
    private let planAnalyticsService: PlanAnalyticsService
    private let exerciseRepository: any ExerciseRepository

    // MARK: - Init

    public init(
        progressionPlanRepository: any ProgressionPlanRepository,
        trainingStatusDetector: TrainingStatusDetector,
        programDesignService: ProgramDesignService,
        planAnalyticsService: PlanAnalyticsService,
        exerciseRepository: any ExerciseRepository
    ) {
        self.progressionPlanRepository = progressionPlanRepository
        self.trainingStatusDetector = trainingStatusDetector
        self.programDesignService = programDesignService
        self.planAnalyticsService = planAnalyticsService
        self.exerciseRepository = exerciseRepository
    }

    // MARK: - Active Plan

    public func loadActivePlan() async {
        isLoading = true
        defer { isLoading = false }

        do {
            activePlan = try await progressionPlanRepository.fetchActive()
            if let plan = activePlan {
                planProgress = try await planAnalyticsService.generateProgress(for: plan)
            } else {
                planProgress = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load plan: \(error.localizedDescription)"
        }
    }

    // MARK: - Training Status Detection

    public func detectTrainingStatus() async {
        draftStatusIsDetecting = true
        defer { draftStatusIsDetecting = false }

        do {
            let detected = try await trainingStatusDetector.detect()
            draftStatus = detected
            applyStatusRecommendation()
        } catch {
            draftStatus = .beginner
            applyStatusRecommendation()
        }
    }

    public func applyStatusRecommendation() {
        draftProgramType = draftStatus.recommendedProgramType
        draftFrequency = draftStatus.weeklyFrequencyRange.lowerBound
    }

    // MARK: - Exercise Management

    public func addExercise(_ exercise: Exercise) {
        guard !draftSelectedExercises.contains(where: { $0.id == exercise.id }) else { return }
        draftSelectedExercises.append(DraftPlanExercise(exercise: exercise))
    }

    public func removeExercise(id: UUID) {
        draftSelectedExercises.removeAll { $0.id == id }
    }

    public func updateOneRM(for exerciseId: UUID, value: Double) {
        guard let index = draftSelectedExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        draftSelectedExercises[index].oneRM = value
        draftSelectedExercises[index].oneRMSource = .userInput
    }

    public func loadOneRMEstimate(for exercise: DraftPlanExercise) async {
        guard let index = draftSelectedExercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        // Only auto-fill if user hasn't already entered a value
        guard draftSelectedExercises[index].oneRM == 0 else { return }

        do {
            if let estimate = try await trainingStatusDetector.estimateOneRM(exerciseId: exercise.id) {
                // Re-check index in case array changed during await
                guard let currentIndex = draftSelectedExercises.firstIndex(where: { $0.id == exercise.id }),
                      draftSelectedExercises[currentIndex].oneRM == 0 else { return }
                draftSelectedExercises[currentIndex].oneRM = estimate.value
                draftSelectedExercises[currentIndex].oneRMSource = .estimated
            }
        } catch {
            // Silently fail — user can enter manually
        }
    }

    // MARK: - Plan Generation

    public func generateAndSavePlan() async {
        isSavingPlan = true
        errorMessage = nil
        defer { isSavingPlan = false }

        do {
            let planExercises = draftSelectedExercises.enumerated().map { index, draft in
                PlanExercise(
                    exerciseId: draft.exercise.id,
                    exerciseName: draft.exercise.name,
                    primaryMuscleGroup: draft.exercise.primaryMuscleGroup,
                    category: draft.exercise.category,
                    estimated1RM: draft.oneRM,
                    oneRMSource: draft.oneRMSource,
                    current1RM: draft.oneRM,
                    isCompound: draft.exercise.category == .barbell || draft.exercise.category == .dumbbell,
                    order: index
                )
            }

            var plan = ProgressionPlan(
                name: draftPlanName.isEmpty ? "Training Plan" : draftPlanName,
                status: .active,
                trainingStatus: draftStatus,
                programType: draftProgramType,
                primaryGoal: draftGoal,
                weeklyFrequency: draftFrequency,
                exercises: planExercises,
                creationSource: .structuredFlow
            )

            let blocks = programDesignService.generateProgram(for: plan)
            plan.blocks = blocks

            // Calculate target end date
            let totalWeeks = plan.totalWeeks
            plan.targetEndDate = Calendar.current.date(byAdding: .weekOfYear, value: totalWeeks, to: plan.startDate)

            try await progressionPlanRepository.save(plan)
            activePlan = plan
            planProgress = try await planAnalyticsService.generateProgress(for: plan)
        } catch {
            errorMessage = "Failed to generate plan: \(error.localizedDescription)"
        }
    }

    // MARK: - Draft Reset

    public func resetDraft() {
        draftStep = 1
        draftStatus = .beginner
        draftStatusIsDetecting = false
        draftGoal = .hypertrophy
        draftProgramType = .linear
        draftFrequency = 3
        draftSelectedExercises = []
        draftPlanName = ""
        isSavingPlan = false
        errorMessage = nil
    }

    // MARK: - Plan Actions

    public func pausePlan() async {
        guard let plan = activePlan else { return }
        do {
            try await progressionPlanRepository.updateStatus(plan.id, status: .paused)
            activePlan?.status = .paused
        } catch {
            errorMessage = "Failed to pause plan: \(error.localizedDescription)"
        }
    }

    public func abandonPlan() async {
        guard let plan = activePlan else { return }
        do {
            try await progressionPlanRepository.updateStatus(plan.id, status: .abandoned)
            activePlan = nil
            planProgress = nil
        } catch {
            errorMessage = "Failed to abandon plan: \(error.localizedDescription)"
        }
    }

    // MARK: - Computed Properties

    public var currentBlockName: String? {
        activePlan?.currentBlock?.name
    }

    public var currentWeekNumber: Int? {
        activePlan?.currentWeek?.absoluteWeekNumber
    }

    public var nextSessionLabel: String? {
        guard let week = activePlan?.currentWeek else { return nil }
        return week.sessions.first { !$0.isCompleted }?.sessionLabel
    }

    public var adherencePercent: Int {
        guard let progress = planProgress else { return 0 }
        return Int(progress.overallAdherence * 100)
    }

    // MARK: - Session Template

    public func prepareSessionTemplate(for session: PlannedSession) async -> WorkoutTemplate? {
        do {
            let exercises = try await exerciseRepository.fetchAll()
            return session.toWorkoutTemplate(exercises: exercises)
        } catch {
            errorMessage = "Failed to prepare session: \(error.localizedDescription)"
            return nil
        }
    }
}
#endif
