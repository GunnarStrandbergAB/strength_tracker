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
    public var draftTrainingDays: Set<Int> = []
    public var draftSelectedExercises: [DraftPlanExercise] = []
    public var draftPlanName: String = ""
    public var isSavingPlan = false
    public var errorMessage: String?

    // MARK: - Linked Template Cache

    public var linkedTemplateNames: [UUID: String] = [:]

    // MARK: - Dependencies

    private let progressionPlanRepository: any ProgressionPlanRepository
    private let trainingStatusDetector: TrainingStatusDetector
    private let programDesignService: ProgramDesignService
    private let planAnalyticsService: PlanAnalyticsService
    private let exerciseRepository: any ExerciseRepository
    private let templateRepository: any TemplateRepository

    // MARK: - Init

    public init(
        progressionPlanRepository: any ProgressionPlanRepository,
        trainingStatusDetector: TrainingStatusDetector,
        programDesignService: ProgramDesignService,
        planAnalyticsService: PlanAnalyticsService,
        exerciseRepository: any ExerciseRepository,
        templateRepository: any TemplateRepository
    ) {
        self.progressionPlanRepository = progressionPlanRepository
        self.trainingStatusDetector = trainingStatusDetector
        self.programDesignService = programDesignService
        self.planAnalyticsService = planAnalyticsService
        self.exerciseRepository = exerciseRepository
        self.templateRepository = templateRepository
    }

    // MARK: - Active Plan

    public func loadActivePlan() async {
        isLoading = true
        defer { isLoading = false }

        do {
            activePlan = try await progressionPlanRepository.fetchActive()
            if let plan = activePlan {
                planProgress = try await planAnalyticsService.generateProgress(for: plan)
                await refreshLinkedTemplateNames(for: plan)
            } else {
                planProgress = nil
                linkedTemplateNames = [:]
            }
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load plan: \(error.localizedDescription)"
        }
    }

    private func refreshLinkedTemplateNames(for plan: ProgressionPlan) async {
        var templateIds = Set<UUID>()
        for block in plan.blocks {
            for week in block.weeks {
                for session in week.sessions {
                    if let tid = session.templateId { templateIds.insert(tid) }
                }
            }
        }
        guard !templateIds.isEmpty else { linkedTemplateNames = [:]; return }
        let allTemplates = (try? await templateRepository.fetchAll()) ?? []
        var names: [UUID: String] = [:]
        for t in allTemplates where templateIds.contains(t.id) {
            names[t.id] = t.name
        }
        linkedTemplateNames = names
    }

    // MARK: - Training Status Detection

    public func detectTrainingStatus() async {
        draftStatusIsDetecting = true
        defer { draftStatusIsDetecting = false }

        do {
            let detected = try await trainingStatusDetector.detect()
            guard !Task.isCancelled else { return }
            draftStatus = detected
            applyStatusRecommendation()
        } catch {
            guard !Task.isCancelled else { return }
            draftStatus = .beginner
            applyStatusRecommendation()
        }
    }

    public func applyStatusRecommendation() {
        draftProgramType = draftStatus.recommendedProgramType
        draftFrequency = draftStatus.weeklyFrequencyRange.lowerBound
        draftTrainingDays = Set(Self.defaultDaySpread[draftFrequency] ?? Self.defaultDaySpread[3]!)
    }

    // MARK: - Weekday Selection

    /// Default day-of-week templates (ISO 8601: Mon=2..Sat=7, Sun=1).
    public static let defaultDaySpread: [Int: [Int]] = [
        2: [2, 5],              // Mon / Thu
        3: [2, 4, 6],           // Mon / Wed / Fri
        4: [2, 3, 5, 6],       // Mon / Tue / Thu / Fri
        5: [2, 3, 4, 6, 7],    // Mon / Tue / Wed / Fri / Sat
        6: [2, 3, 4, 5, 6, 7], // Mon - Sat
    ]

    public func toggleTrainingDay(_ day: Int) {
        if draftTrainingDays.contains(day) {
            guard draftTrainingDays.count > 2 else { return }
            draftTrainingDays.remove(day)
        } else {
            guard draftTrainingDays.count < 6 else { return }
            draftTrainingDays.insert(day)
        }
        draftFrequency = draftTrainingDays.count
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

            let sortedDays = draftTrainingDays.isEmpty ? nil : draftTrainingDays.sorted()

            var plan = ProgressionPlan(
                name: draftPlanName.isEmpty ? "Training Plan" : draftPlanName,
                status: .active,
                trainingStatus: draftStatus,
                programType: draftProgramType,
                primaryGoal: draftGoal,
                weeklyFrequency: draftFrequency,
                trainingDays: sortedDays,
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
        draftTrainingDays = []
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
            if let templateId = session.templateId {
                let allTemplates = try await templateRepository.fetchAll()
                if let linked = allTemplates.first(where: { $0.id == templateId }) {
                    return mergeSessionIntoTemplate(session: session, template: linked)
                }
            }
            return session.toWorkoutTemplate(exercises: exercises)
        } catch {
            errorMessage = "Failed to prepare session: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Template Linking

    public func linkTemplate(templateId: UUID, toSession sessionId: UUID) async {
        guard var plan = activePlan else { return }
        for bi in plan.blocks.indices {
            for wi in plan.blocks[bi].weeks.indices {
                if let si = plan.blocks[bi].weeks[wi].sessions
                    .firstIndex(where: { $0.id == sessionId }) {
                    plan.blocks[bi].weeks[wi].sessions[si].templateId = templateId
                    plan.updatedAt = Date()
                    do {
                        try await progressionPlanRepository.save(plan)
                        activePlan = plan
                        await refreshLinkedTemplateNames(for: plan)
                    } catch {
                        errorMessage = "Failed to link template: \(error.localizedDescription)"
                    }
                    return
                }
            }
        }
    }

    // MARK: - Session Completion

    public func handleSessionCompleted(sessionId: UUID, planId: UUID, workoutId: UUID) async {
        do {
            try await progressionPlanRepository.markSessionCompleted(sessionId, workoutId: workoutId, inPlan: planId)
            await loadActivePlan()
        } catch {
            errorMessage = "Failed to mark session completed: \(error.localizedDescription)"
        }
    }

    // MARK: - Template Merge

    public func mergeSessionIntoTemplate(session: PlannedSession, template: WorkoutTemplate) -> WorkoutTemplate {
        let plannedLookup = Dictionary(
            session.plannedExercises.map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let plannedByName = Dictionary(
            session.plannedExercises.map { ($0.exerciseName.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let mergedExercises = template.exercises.map { te -> TemplateExercise in
            let planned = plannedLookup[te.exercise.id]
                ?? plannedByName[te.exercise.name.lowercased()]
            guard let planned else { return te }
            return TemplateExercise(
                id: te.id,
                exercise: te.exercise,
                order: te.order,
                supersetGroup: te.supersetGroup,
                notes: planned.notes ?? te.notes,
                restTimerSeconds: planned.restSeconds,
                targetSets: planned.sets,
                targetReps: planned.targetReps,
                targetWeight: planned.targetWeight,
                targetDurationSeconds: te.targetDurationSeconds,
                targetDistanceMeters: te.targetDistanceMeters,
                setTargets: planned.generateSetTargets(),
                isWarmUp: planned.isWarmup
            )
        }

        return WorkoutTemplate(
            id: UUID(),
            name: template.name,
            notes: template.notes,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: mergedExercises
        )
    }
}
#endif
