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
    public var hasLoadedOnce = false

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
    public var draftStartDate: Date = Date()
    public var draftStartDateManuallySet: Bool = false
    public var draftDaySchedule: [Int: DraftDayEntry] = [:]  // keyed by ISO day
    public var draftUseCustomDeloadDays: Bool = false
    public var draftDeloadDays: Set<Int> = []
    public var isSavingPlan = false
    public var errorMessage: String?

    // MARK: - Draft Day Entry

    public struct DraftDayEntry {
        public var templateId: UUID?
        public var templateName: String?
        public var exerciseIds: Set<UUID>   // library exercise IDs

        public init(templateId: UUID? = nil, templateName: String? = nil, exerciseIds: Set<UUID> = []) {
            self.templateId = templateId
            self.templateName = templateName
            self.exerciseIds = exerciseIds
        }
    }

    // MARK: - Linked Template Cache

    public var linkedTemplateNames: [UUID: String] = [:]

    // MARK: - Dependencies

    private let progressionPlanRepository: any ProgressionPlanRepository
    private let trainingStatusDetector: TrainingStatusDetector
    private let programDesignService: ProgramDesignService
    private let planAnalyticsService: PlanAnalyticsService
    private let exerciseRepository: any ExerciseRepository
    private let templateRepository: any TemplateRepository
    private let userPreferencesService: UserPreferencesService?
    private let workoutRepository: (any WorkoutRepository)?
    private let sessionExecutionService: SessionExecutionService
    private let adaptiveAdjustmentService: AdaptiveAdjustmentService?
    private let coachingCommunicationService: CoachingCommunicationService?
    private let bodyWeightProvider: BodyWeightProvider?

    public var weightUnit: WeightUnit { userPreferencesService?.weightUnit ?? .kg }
    private var bodyWeightKg: Double {
        bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }

    // MARK: - Init

    public init(
        progressionPlanRepository: any ProgressionPlanRepository,
        trainingStatusDetector: TrainingStatusDetector,
        programDesignService: ProgramDesignService,
        planAnalyticsService: PlanAnalyticsService,
        exerciseRepository: any ExerciseRepository,
        templateRepository: any TemplateRepository,
        userPreferencesService: UserPreferencesService? = nil,
        workoutRepository: (any WorkoutRepository)? = nil,
        sessionExecutionService: SessionExecutionService = SessionExecutionService(),
        adaptiveAdjustmentService: AdaptiveAdjustmentService? = nil,
        coachingCommunicationService: CoachingCommunicationService? = nil,
        bodyWeightProvider: BodyWeightProvider? = nil
    ) {
        self.bodyWeightProvider = bodyWeightProvider
        self.progressionPlanRepository = progressionPlanRepository
        self.trainingStatusDetector = trainingStatusDetector
        self.programDesignService = programDesignService
        self.planAnalyticsService = planAnalyticsService
        self.exerciseRepository = exerciseRepository
        self.templateRepository = templateRepository
        self.userPreferencesService = userPreferencesService
        self.workoutRepository = workoutRepository
        self.sessionExecutionService = sessionExecutionService
        self.adaptiveAdjustmentService = adaptiveAdjustmentService
        self.coachingCommunicationService = coachingCommunicationService
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
        hasLoadedOnce = true
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
        // Advanced plans have no scheduled deload weeks (M1, all program types) —
        // stale custom deload days must not leak into the generated plan.
        if draftStatus == .advanced {
            draftUseCustomDeloadDays = false
            draftDeloadDays = []
        }
    }

    // MARK: - Weekday Selection

    /// Default day-of-week templates (Calendar.weekday encoding: Sun=1, Mon=2..Sat=7).
    public static let defaultDaySpread: [Int: [Int]] = [
        1: [4],                  // Wed (midweek)
        2: [2, 5],              // Mon / Thu
        3: [2, 4, 6],           // Mon / Wed / Fri
        4: [2, 3, 5, 6],       // Mon / Tue / Thu / Fri
        5: [2, 3, 4, 6, 7],    // Mon / Tue / Wed / Fri / Sat
        6: [2, 3, 4, 5, 6, 7], // Mon - Sat
        7: [1, 2, 3, 4, 5, 6, 7], // Every day
    ]

    public func toggleTrainingDay(_ day: Int) {
        if draftTrainingDays.contains(day) {
            guard draftTrainingDays.count > 1 else { return }
            draftTrainingDays.remove(day)
            // Remove from deload days if it was selected there
            draftDeloadDays.remove(day)
        } else {
            draftTrainingDays.insert(day)
        }
        draftFrequency = draftTrainingDays.count
        if !draftStartDateManuallySet {
            draftStartDate = defaultStartDate()
        }
    }

    public func toggleDeloadDay(_ day: Int) {
        guard draftTrainingDays.contains(day) else { return }
        if draftDeloadDays.contains(day) {
            guard draftDeloadDays.count > 1 else { return }
            draftDeloadDays.remove(day)
        } else {
            guard draftDeloadDays.count < draftTrainingDays.count else { return }
            draftDeloadDays.insert(day)
        }
    }

    /// Picks a sensible default subset of training days for deload (roughly 60%, min 2).
    public func applyDefaultDeloadDays() {
        let sorted = Self.dayDisplayOrder.filter { draftTrainingDays.contains($0) }
        let count = max(2, sorted.count - 2) // e.g. 5→3, 4→2, 3→2, 2→2
        draftDeloadDays = Set(sorted.prefix(count))
    }

    private static let dayDisplayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    // MARK: - Start Date

    /// Calendar.weekday number for a given date (Sun=1, Mon=2, ..., Sat=7).
    /// Note: this is NOT ISO 8601 (which is Mon=1..Sun=7) — persisted plan day
    /// numbers use Calendar.weekday encoding throughout.
    private func calendarWeekday(_ date: Date) -> Int {
        Calendar.current.component(.weekday, from: date) // Sun=1..Sat=7
    }

    /// Returns the next training day on or after today.
    public func defaultStartDate() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard !draftTrainingDays.isEmpty else { return today }
        let todayWeekday = calendarWeekday(today)
        if draftTrainingDays.contains(todayWeekday) { return today }
        for offset in 1...7 {
            let candidate = calendar.date(byAdding: .day, value: offset, to: today)!
            if draftTrainingDays.contains(calendarWeekday(candidate)) { return candidate }
        }
        return today
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

    // MARK: - Day Schedule Management

    public func setDraftTemplate(_ template: WorkoutTemplate?, forDay day: Int) {
        guard let template else {
            draftDaySchedule[day] = DraftDayEntry()
            return
        }
        autoSuggestExercises(forDay: day, template: template)
    }

    public func toggleDraftExercise(_ exerciseId: UUID, forDay day: Int) {
        var entry = draftDaySchedule[day] ?? DraftDayEntry()
        if entry.exerciseIds.contains(exerciseId) {
            entry.exerciseIds.remove(exerciseId)
        } else {
            entry.exerciseIds.insert(exerciseId)
        }
        draftDaySchedule[day] = entry
    }

    public func autoSuggestExercises(forDay day: Int, template: WorkoutTemplate) {
        let templateExerciseIds = Set(template.exercises.map(\.exercise.id))
        let matchingPlanExercises = draftSelectedExercises
            .filter { templateExerciseIds.contains($0.id) }
            .map(\.id)
        draftDaySchedule[day] = DraftDayEntry(
            templateId: template.id,
            templateName: template.name,
            exerciseIds: Set(matchingPlanExercises)
        )
    }

    // MARK: - Scheduled Dates

    public func rescheduleSession(sessionId: UUID, to newDate: Date) async {
        guard var plan = activePlan else { return }
        for blockIdx in plan.blocks.indices {
            for weekIdx in plan.blocks[blockIdx].weeks.indices {
                if let sIdx = plan.blocks[blockIdx].weeks[weekIdx].sessions.firstIndex(where: { $0.id == sessionId }) {
                    plan.blocks[blockIdx].weeks[weekIdx].sessions[sIdx].scheduledDate = newDate
                    // Moving a session across a calendar-week boundary changes its bucket.
                    plan.blocks = CalendarWeekBucketer.rebucket(plan.blocks)
                    plan.updatedAt = Date()
                    do {
                        try await progressionPlanRepository.save(plan)
                        activePlan = plan
                        planProgress = try await planAnalyticsService.generateProgress(for: plan)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    return
                }
            }
        }
    }

    // MARK: - Skip Session

    /// Toggles a session's skipped state. Completed sessions cannot be skipped.
    public func toggleSessionSkipped(sessionId: UUID) async {
        guard var plan = activePlan else { return }
        for blockIdx in plan.blocks.indices {
            for weekIdx in plan.blocks[blockIdx].weeks.indices {
                if let sIdx = plan.blocks[blockIdx].weeks[weekIdx].sessions.firstIndex(where: { $0.id == sessionId }) {
                    guard plan.blocks[blockIdx].weeks[weekIdx].sessions[sIdx].completedWorkoutId == nil else { return }
                    let nowSkipped = !plan.blocks[blockIdx].weeks[weekIdx].sessions[sIdx].isSkipped
                    plan.blocks[blockIdx].weeks[weekIdx].sessions[sIdx].isSkipped = nowSkipped
                    plan.blocks[blockIdx].weeks[weekIdx].sessions[sIdx].skippedAt = nowSkipped ? Date() : nil
                    plan.updatedAt = Date()
                    do {
                        try await progressionPlanRepository.save(plan)
                        await loadActivePlan()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    return
                }
            }
        }
    }

    // MARK: - Plan Generation

    /// Everything needed to create a plan, independent of the draft flow state.
    public struct PlanCreationRequest: Sendable {
        public var name: String
        public var trainingStatus: TrainingStatus
        public var programType: ProgramType
        public var primaryGoal: TrainingGoal
        public var weeklyFrequency: Int
        /// Calendar.weekday day numbers (Sun=1 … Sat=7); empty = defaults.
        public var trainingDays: Set<Int>
        /// Deload-week day numbers; nil = same as training days.
        public var deloadDays: [Int]?
        public var startDate: Date
        public var exercises: [PlanExercise]
        public var daySchedule: [DayScheduleEntry]
        public var creationSource: ProgressionPlan.PlanCreationSource

        public init(
            name: String,
            trainingStatus: TrainingStatus,
            programType: ProgramType,
            primaryGoal: TrainingGoal,
            weeklyFrequency: Int,
            trainingDays: Set<Int> = [],
            deloadDays: [Int]? = nil,
            startDate: Date = Date(),
            exercises: [PlanExercise],
            daySchedule: [DayScheduleEntry] = [],
            creationSource: ProgressionPlan.PlanCreationSource
        ) {
            self.name = name
            self.trainingStatus = trainingStatus
            self.programType = programType
            self.primaryGoal = primaryGoal
            self.weeklyFrequency = weeklyFrequency
            self.trainingDays = trainingDays
            self.deloadDays = deloadDays
            self.startDate = startDate
            self.exercises = exercises
            self.daySchedule = daySchedule
            self.creationSource = creationSource
        }
    }

    /// Creates, generates, and activates a plan — the single core shared by the
    /// structured draft flow and AI-proposed plans.
    @discardableResult
    public func createPlan(from request: PlanCreationRequest) async throws -> ProgressionPlan {
        let startWeekday = Calendar.current.component(.weekday, from: request.startDate)
        let startFirstOrder = (0..<7).map { (startWeekday - 1 + $0) % 7 + 1 }
        let sortedDays = request.trainingDays.isEmpty
            ? nil
            : startFirstOrder.filter { request.trainingDays.contains($0) }

        var plan = ProgressionPlan(
            name: request.name.isEmpty ? "Training Plan" : request.name,
            status: .active,
            trainingStatus: request.trainingStatus,
            programType: request.programType,
            primaryGoal: request.primaryGoal,
            weeklyFrequency: request.weeklyFrequency,
            trainingDays: sortedDays,
            deloadDays: request.deloadDays,
            startDate: request.startDate,
            exercises: request.exercises,
            daySchedule: request.daySchedule,
            creationSource: request.creationSource
        )

        let deloadIntensity = Double(userPreferencesService?.deloadWeightPercentage ?? 50) / 100.0
        // generateProgram dates all sessions sequentially and re-buckets them into
        // calendar weeks (sessions arrive sorted chronologically within each week).
        plan.blocks = programDesignService.generateProgram(for: plan, deloadIntensity: deloadIntensity)

        // Target end date = last scheduled session (fallback: startDate + totalWeeks)
        let lastScheduledDate = plan.blocks.flatMap(\.weeks).flatMap(\.sessions)
            .compactMap(\.scheduledDate).max()
        plan.targetEndDate = lastScheduledDate
            ?? Calendar.current.date(byAdding: .weekOfYear, value: plan.totalWeeks, to: plan.startDate)

        try await progressionPlanRepository.save(plan)
        activePlan = plan
        planProgress = try await planAnalyticsService.generateProgress(for: plan)
        return plan
    }

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

            // Convert draft day schedule to domain model
            let daySchedule: [DayScheduleEntry] = draftDaySchedule.compactMap { day, entry in
                guard entry.templateId != nil || !entry.exerciseIds.isEmpty else { return nil }
                return DayScheduleEntry(
                    dayOfWeek: day,
                    templateId: entry.templateId,
                    templateName: entry.templateName,
                    exerciseIds: Array(entry.exerciseIds)
                )
            }

            let sortedDeloadDays: [Int]? = draftUseCustomDeloadDays && !draftDeloadDays.isEmpty
                ? Self.dayDisplayOrder.filter { draftDeloadDays.contains($0) }
                : nil

            try await createPlan(from: PlanCreationRequest(
                name: draftPlanName,
                trainingStatus: draftStatus,
                programType: draftProgramType,
                primaryGoal: draftGoal,
                weeklyFrequency: draftFrequency,
                trainingDays: draftTrainingDays,
                deloadDays: sortedDeloadDays,
                startDate: draftStartDate,
                exercises: planExercises,
                daySchedule: daySchedule,
                creationSource: .structuredFlow
            ))
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
        draftUseCustomDeloadDays = false
        draftDeloadDays = []
        draftSelectedExercises = []
        draftDaySchedule = [:]
        draftPlanName = ""
        draftStartDate = Date()
        draftStartDateManuallySet = false
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
        activePlan?.nextPlannedSession?.sessionLabel
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
                    return mergeSessionIntoTemplate(session: session, template: linked, exercises: exercises)
                }
            }
            return session.toWorkoutTemplate(exercises: exercises)
        } catch {
            errorMessage = "Failed to prepare session: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Template Linking

    /// Plan-wide template change for the day-of-week of the targeted session.
    ///
    /// Updates `plan.daySchedule` for the session's day-of-week (template + auto-picked tracked
    /// exercises), then propagates the new template + rebuilt planned exercises to every
    /// uncompleted session on that day across all weeks. Sessions already completed keep their
    /// historical plannedExercises and templateId untouched.
    public func linkTemplate(templateId: UUID, toSession sessionId: UUID) async {
        guard var plan = activePlan else { return }

        // Resolve dayOfWeek from the targeted session.
        var resolvedDay: Int?
        outer: for block in plan.blocks {
            for week in block.weeks {
                if let s = week.sessions.first(where: { $0.id == sessionId }) {
                    resolvedDay = s.dayOfWeek
                    break outer
                }
            }
        }
        guard let dayOfWeek = resolvedDay else { return }

        // Fetch the target template.
        let template: WorkoutTemplate
        do {
            let allTemplates = try await templateRepository.fetchAll()
            guard let t = allTemplates.first(where: { $0.id == templateId }) else {
                errorMessage = "Template not found."
                return
            }
            template = t
        } catch {
            errorMessage = "Failed to load template: \(error.localizedDescription)"
            return
        }

        // Auto-pick: plan.exercises whose library exerciseId is in the new template.
        let templateExerciseIds = Set(template.exercises.map(\.exercise.id))
        let autoPickedIds = Set(
            plan.exercises
                .filter { templateExerciseIds.contains($0.exerciseId) }
                .map(\.exerciseId)
        )

        // Early-exit: same template + same auto-pick AND no session on this day still has
        // stale DUP-rotation metadata (`dupSessionType` set). The stale-metadata check
        // ensures users who hit this fix via a re-tap also get their old labels cleared.
        if let existing = plan.daySchedule.first(where: { $0.dayOfWeek == dayOfWeek }),
           existing.templateId == templateId,
           Set(existing.exerciseIds) == autoPickedIds {
            let anySessionStale = plan.blocks.contains { block in
                block.weeks.contains { week in
                    week.sessions.contains { s in
                        s.dayOfWeek == dayOfWeek
                            && s.completedWorkoutId == nil
                            && s.dupSessionType != nil
                    }
                }
            }
            if !anySessionStale {
                return
            }
        }

        // Upsert the daySchedule entry, preserving the existing entry's id when present.
        let newExerciseIdsArray = Array(autoPickedIds)
        if let idx = plan.daySchedule.firstIndex(where: { $0.dayOfWeek == dayOfWeek }) {
            plan.daySchedule[idx].templateId = templateId
            plan.daySchedule[idx].templateName = template.name
            plan.daySchedule[idx].exerciseIds = newExerciseIdsArray
        } else {
            plan.daySchedule.append(
                DayScheduleEntry(
                    dayOfWeek: dayOfWeek,
                    templateId: templateId,
                    templateName: template.name,
                    exerciseIds: newExerciseIdsArray
                )
            )
        }

        // Propagate to every uncompleted session on this day across all weeks.
        // Also clear the DUP rotation metadata — once the user manually overrides a day's
        // template, the auto-generated rotation type no longer applies, so the label and
        // badge would otherwise stick to the day even after the content has moved.
        let neutralLabel = Self.dayName(for: dayOfWeek)
        for bi in plan.blocks.indices {
            for wi in plan.blocks[bi].weeks.indices {
                let week = plan.blocks[bi].weeks[wi]
                for si in plan.blocks[bi].weeks[wi].sessions.indices {
                    guard plan.blocks[bi].weeks[wi].sessions[si].dayOfWeek == dayOfWeek else { continue }
                    guard plan.blocks[bi].weeks[wi].sessions[si].completedWorkoutId == nil else { continue }
                    plan.blocks[bi].weeks[wi].sessions[si].templateId = templateId
                    plan.blocks[bi].weeks[wi].sessions[si].plannedExercises =
                        Self.rebuildSessionExercises(
                            inWeek: week,
                            newTemplate: template,
                            planExercises: plan.exercises,
                            autoPickedIds: autoPickedIds,
                            targetDayOfWeek: dayOfWeek
                        )
                    plan.blocks[bi].weeks[wi].sessions[si].dupSessionType = nil
                    plan.blocks[bi].weeks[wi].sessions[si].sessionLabel = neutralLabel
                }
            }
        }

        plan.updatedAt = Date()
        do {
            try await progressionPlanRepository.save(plan)
            activePlan = plan
            await refreshLinkedTemplateNames(for: plan)
        } catch {
            errorMessage = "Failed to link template: \(error.localizedDescription)"
        }
    }

    /// Day-of-week label matching `ProgramDesignService`'s Sun=1..Sat=7 convention.
    static func dayName(for dayOfWeek: Int) -> String {
        let names: [Int: String] = [
            1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
            5: "Thursday", 6: "Friday", 7: "Saturday"
        ]
        return names[dayOfWeek] ?? "Day"
    }

    /// Rebuild a target-day session's planned exercises for a newly-linked template.
    ///
    /// For each exercise in the new template that is also a tracked PlanExercise
    /// (`autoPickedIds`), inherit intensity / sets / reps / rest from a donor
    /// `PlannedExerciseSet` in the same week — preferring a session on the target
    /// day-of-week, falling back to the first non-empty session on any day — and compute
    /// `targetWeight` per the PlanExercise's own 1RM. Non-tracked template exercises fall
    /// back to template defaults.
    static func rebuildSessionExercises(
        inWeek week: TrainingWeek,
        newTemplate: WorkoutTemplate,
        planExercises: [PlanExercise],
        autoPickedIds: Set<UUID>,
        targetDayOfWeek: Int? = nil
    ) -> [PlannedExerciseSet] {
        let planExerciseById = Dictionary(
            planExercises.map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Intensity donor: prefer a session sharing the target day-of-week (calendar
        // weeks can mix microcycle intensities), else first non-empty in this week.
        let sameDayDonor: PlannedExerciseSet? = targetDayOfWeek.flatMap { day in
            week.sessions
                .first { $0.dayOfWeek == day && !$0.plannedExercises.isEmpty }?
                .plannedExercises.first
        }
        let donor: PlannedExerciseSet? = sameDayDonor
            ?? week.sessions
                .lazy
                .flatMap(\.plannedExercises)
                .first

        return newTemplate.exercises
            .sorted(by: { $0.order < $1.order })
            .map { te -> PlannedExerciseSet in
                if autoPickedIds.contains(te.exercise.id),
                   let planExercise = planExerciseById[te.exercise.id] {
                    let percentage = donor?.percentageOf1RM ?? 0
                    let sets = donor?.sets ?? te.targetSets
                    let reps = donor?.targetReps ?? (te.targetReps ?? 0)
                    let rest = donor?.restSeconds ?? (te.restTimerSeconds ?? 120)
                    return PlannedExerciseSet(
                        planExerciseId: planExercise.id,
                        exerciseId: te.exercise.id,
                        exerciseName: te.exercise.name,
                        sets: sets,
                        targetReps: reps,
                        targetWeight: planExercise.targetWeight(atPercentage: percentage),
                        percentageOf1RM: percentage,
                        targetRPE: donor?.targetRPE,
                        restSeconds: rest,
                        isWarmup: te.isWarmUp,
                        notes: te.notes
                    )
                }
                return PlannedExerciseSet(
                    planExerciseId: te.id,
                    exerciseId: te.exercise.id,
                    exerciseName: te.exercise.name,
                    sets: te.targetSets,
                    targetReps: te.targetReps ?? 0,
                    targetWeight: te.targetWeight ?? 0,
                    percentageOf1RM: 0,
                    targetRPE: nil,
                    restSeconds: te.restTimerSeconds ?? 120,
                    isWarmup: te.isWarmUp,
                    notes: te.notes
                )
            }
    }

    // MARK: - Session Completion

    /// Full adaptive completion pipeline: links the workout to the planned session, runs the
    /// APRE/EWMA engine, propagates updated targets to future sessions, and asks the adviser
    /// for new proposals. Any failure degrades to a plain `markSessionCompleted` so the
    /// completion itself is never lost.
    public func handleSessionCompleted(sessionId: UUID, planId: UUID, workoutId: UUID) async {
        // Step 1: fetch the plan and locate the session — fall back if either is missing.
        let fetchedPlan = try? await progressionPlanRepository.fetch(id: planId)
        guard var plan = fetchedPlan,
              let (bi, wi, si) = Self.locateSession(sessionId, in: plan) else {
            await fallbackMarkSessionCompleted(sessionId: sessionId, planId: planId, workoutId: workoutId)
            return
        }

        // Step 2: idempotency — Watch transfers can retry the same completion.
        guard plan.blocks[bi].weeks[wi].sessions[si].completedWorkoutId == nil else {
            await loadActivePlan()
            return
        }

        do {
            // Step 3: resolve the completed workout.
            guard let workoutRepository else {
                await fallbackMarkSessionCompleted(sessionId: sessionId, planId: planId, workoutId: workoutId)
                return
            }
            let allWorkouts = try await workoutRepository.fetchAll()
            guard let workout = allWorkouts.first(where: { $0.id == workoutId }) else {
                await fallbackMarkSessionCompleted(sessionId: sessionId, planId: planId, workoutId: workoutId)
                return
            }

            // Step 4: run the APRE + EWMA 1RM engine.
            let result = sessionExecutionService.completeSession(
                plan.blocks[bi].weeks[wi].sessions[si],
                workout: workout,
                planExercises: plan.exercises,
                bodyWeightKg: bodyWeightKg
            )
            plan.blocks[bi].weeks[wi].sessions[si] = result.updatedSession
            // Completion wins over a prior skip.
            plan.blocks[bi].weeks[wi].sessions[si].isSkipped = false
            plan.blocks[bi].weeks[wi].sessions[si].skippedAt = nil
            plan.exercises = result.updatedExercises

            // Step 5: engine adjustments are auto-applied (recorded as accepted).
            for var adjustment in result.adjustments {
                adjustment.wasAccepted = true
                if let coaching = coachingCommunicationService {
                    let explanation = await coaching.provider.explain(
                        adjustment: adjustment, trainingStatus: plan.trainingStatus
                    )
                    adjustment.coachingExplanation = explanation.body
                }
                plan.adjustments.append(adjustment)
            }

            // Step 6: propagate updated targets to future sessions.
            applyExerciseUpdatesToFutureSessions(plan: &plan, adjustments: result.adjustments)

            // Step 7: adviser proposals over the last 8 weeks of completed workouts.
            if let adviser = adaptiveAdjustmentService {
                let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? .distantPast
                let recentWorkouts = allWorkouts.filter {
                    guard let completedAt = $0.completedAt else { return false }
                    return completedAt >= cutoff
                }
                let proposals = try await adviser.analyzeAndPropose(plan: plan, recentWorkouts: recentWorkouts)
                for proposal in proposals {
                    guard !Self.isDuplicateProposal(proposal.adjustment, existing: plan.adjustments) else { continue }
                    var adjustment = proposal.adjustment
                    adjustment.wasAccepted = nil
                    if let coaching = coachingCommunicationService {
                        let explanation = await coaching.provider.explain(
                            adjustment: adjustment, trainingStatus: plan.trainingStatus
                        )
                        adjustment.coachingExplanation = "\(explanation.body) \(proposal.reasoning)"
                    } else {
                        adjustment.coachingExplanation = proposal.reasoning
                    }
                    plan.adjustments.append(adjustment)
                }
            }

            // Step 8: persist everything atomically.
            plan.updatedAt = Date()
            try await progressionPlanRepository.save(plan)
            await loadActivePlan()
        } catch {
            // Completion marking must never be lost — degrade to the plain repo call.
            print("[ProgressionPlanVM] Adaptive completion pipeline failed, falling back: \(error)")
            await fallbackMarkSessionCompleted(sessionId: sessionId, planId: planId, workoutId: workoutId)
        }
    }

    /// Pre-pipeline behavior: just mark the session completed and reload.
    private func fallbackMarkSessionCompleted(sessionId: UUID, planId: UUID, workoutId: UUID) async {
        do {
            try await progressionPlanRepository.markSessionCompleted(sessionId, workoutId: workoutId, inPlan: planId)
            await loadActivePlan()
        } catch {
            errorMessage = "Failed to mark session completed: \(error.localizedDescription)"
        }
    }

    /// Returns the (block, week, session) indices for a session id, or nil if absent.
    private static func locateSession(_ sessionId: UUID, in plan: ProgressionPlan) -> (Int, Int, Int)? {
        for bi in plan.blocks.indices {
            for wi in plan.blocks[bi].weeks.indices {
                if let si = plan.blocks[bi].weeks[wi].sessions.firstIndex(where: { $0.id == sessionId }) {
                    return (bi, wi, si)
                }
            }
        }
        return nil
    }

    /// Propagates post-session exercise state to future sessions.
    ///
    /// Scope: every open (not completed, not skipped) session in the CURRENT block is
    /// updated regardless of its scheduled date — calendar-week buckets can place a
    /// later microcycle's session on an earlier date, and overdue current-block sessions
    /// should still train at the updated targets. Sessions in later blocks keep the
    /// "not scheduled in the past" gate.
    ///
    /// Precedence rule:
    /// - Percentage-based sets (`percentageOf1RM > 0`) are governed by the exercise's 1RM:
    ///   `targetWeight` is recomputed from the updated `PlanExercise.current1RM` at the set's
    ///   own percentage. APRE deltas are NOT layered on top — the 1RM update already absorbed
    ///   the session's performance.
    /// - Absolute sets (`percentageOf1RM == 0`) have no 1RM anchor, so they take the
    ///   APRE-adjusted target weight directly when an APRE adjustment affected their exercise.
    private func applyExerciseUpdatesToFutureSessions(
        plan: inout ProgressionPlan,
        adjustments: [PlanAdjustment]
    ) {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let planExercisesById = Dictionary(
            plan.exercises.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let planExercisesByLibraryId = Dictionary(
            plan.exercises.map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let apreAdjustments = adjustments.filter { $0.trigger == .apre }
        let currentBlockIndex = plan.blocks.firstIndex { !$0.allWeeksCompleted }

        for bi in plan.blocks.indices {
            for wi in plan.blocks[bi].weeks.indices {
                for si in plan.blocks[bi].weeks[wi].sessions.indices {
                    let session = plan.blocks[bi].weeks[wi].sessions[si]
                    guard !session.isClosed else { continue }
                    // Past-date gate only applies beyond the current block.
                    if bi != currentBlockIndex,
                       let scheduled = session.scheduledDate, scheduled < startOfToday { continue }

                    for ei in plan.blocks[bi].weeks[wi].sessions[si].plannedExercises.indices {
                        let set = plan.blocks[bi].weeks[wi].sessions[si].plannedExercises[ei]
                        // Untracked template exercises carry a template-exercise id in
                        // planExerciseId; fall back to the library exercise id.
                        guard let planExercise = planExercisesById[set.planExerciseId]
                            ?? planExercisesByLibraryId[set.exerciseId] else { continue }

                        if set.percentageOf1RM > 0 {
                            plan.blocks[bi].weeks[wi].sessions[si].plannedExercises[ei].targetWeight =
                                planExercise.targetWeight(atPercentage: set.percentageOf1RM)
                        } else if let apre = apreAdjustments.first(where: { $0.affectedExerciseIds.contains(planExercise.id) }),
                                  let newWeightString = apre.newValues["targetWeight"],
                                  let newWeight = Double(newWeightString) {
                            plan.blocks[bi].weeks[wi].sessions[si].plannedExercises[ei].targetWeight = newWeight
                        }
                    }
                }
            }
        }
    }

    /// A proposal is a duplicate when an adjustment with the same type + trigger + affected
    /// exercises was already recorded within the last 14 days — regardless of whether the
    /// user accepted or dismissed it.
    private static func isDuplicateProposal(
        _ proposal: PlanAdjustment,
        existing: [PlanAdjustment],
        now: Date = Date()
    ) -> Bool {
        // Normalize to day granularity so a proposal recorded earlier in the day
        // doesn't slip past the cutoff because of its time-of-day component.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -14, to: today) else { return false }
        return existing.contains { recorded in
            recorded.adjustmentType == proposal.adjustmentType
                && recorded.trigger == proposal.trigger
                && Set(recorded.affectedExerciseIds) == Set(proposal.affectedExerciseIds)
                && calendar.startOfDay(for: recorded.appliedAt) >= cutoff
        }
    }

    // MARK: - Pending Adjustments

    /// Adviser proposals awaiting a user decision (engine adjustments are recorded as accepted).
    public var pendingAdjustments: [PlanAdjustment] {
        activePlan?.adjustments.filter { $0.wasAccepted == nil } ?? []
    }

    /// Accepts a pending adjustment and applies its effect to future sessions.
    public func acceptAdjustment(id: UUID) async {
        guard var plan = activePlan,
              let index = plan.adjustments.firstIndex(where: { $0.id == id }) else { return }
        plan.adjustments[index].wasAccepted = true
        let adjustment = plan.adjustments[index]

        switch adjustment.adjustmentType {
        case .loadDecrease:
            // AdaptiveAdjustmentService encodes the percentage as "decreasePercent"
            // (beginner regression) or "reductionPercent" (detraining).
            let percentString = adjustment.newValues["decreasePercent"]
                ?? adjustment.newValues["reductionPercent"]
            if let percentString, let percent = Double(percentString) {
                applyLoadScale(
                    plan: &plan,
                    factor: 1.0 - percent / 100.0,
                    affectedExerciseIds: adjustment.affectedExerciseIds
                )
            }
        case .deload:
            // Prefer a percentage already stored on the adjustment over the live
            // preference, then persist whichever was used so the record stays faithful
            // even if the user later changes the preference.
            let percent = adjustment.newValues["deloadPercent"].flatMap(Double.init)
                ?? Double(userPreferencesService?.deloadWeightPercentage ?? 50)
            plan.adjustments[index].newValues["deloadPercent"] = String(percent)
            applyDeloadToCurrentWeek(plan: &plan, deloadPercent: percent)
        case .blockExtension:
            // TODO: Repeat-week / block-extension structural changes are deferred —
            // acceptance is recorded but the program structure is left unchanged.
            break
        default:
            break
        }

        plan.updatedAt = Date()
        do {
            try await progressionPlanRepository.save(plan)
            await loadActivePlan()
        } catch {
            errorMessage = "Failed to apply adjustment: \(error.localizedDescription)"
        }
    }

    /// Dismisses a pending adjustment without applying it.
    public func dismissAdjustment(id: UUID) async {
        guard var plan = activePlan,
              let index = plan.adjustments.firstIndex(where: { $0.id == id }) else { return }
        plan.adjustments[index].wasAccepted = false
        plan.updatedAt = Date()
        do {
            try await progressionPlanRepository.save(plan)
            await loadActivePlan()
        } catch {
            errorMessage = "Failed to dismiss adjustment: \(error.localizedDescription)"
        }
    }

    /// Scales target weights of future uncompleted sets by `factor`, rounded to nearest 2.5.
    /// `affectedExerciseIds` may carry library exercise ids (adviser proposals) or
    /// PlanExercise ids (engine adjustments); empty means all exercises.
    private func applyLoadScale(
        plan: inout ProgressionPlan,
        factor: Double,
        affectedExerciseIds: [UUID]
    ) {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let affected = Set(affectedExerciseIds)

        for bi in plan.blocks.indices {
            for wi in plan.blocks[bi].weeks.indices {
                for si in plan.blocks[bi].weeks[wi].sessions.indices {
                    let session = plan.blocks[bi].weeks[wi].sessions[si]
                    guard session.completedWorkoutId == nil else { continue }
                    if let scheduled = session.scheduledDate, scheduled < startOfToday { continue }

                    for ei in plan.blocks[bi].weeks[wi].sessions[si].plannedExercises.indices {
                        let set = plan.blocks[bi].weeks[wi].sessions[si].plannedExercises[ei]
                        guard affected.isEmpty
                            || affected.contains(set.exerciseId)
                            || affected.contains(set.planExerciseId) else { continue }
                        let scaled = (set.targetWeight * factor).rounded(toNearest: 2.5)
                        plan.blocks[bi].weeks[wi].sessions[si].plannedExercises[ei].targetWeight = scaled
                    }
                }
            }
        }
    }

    /// Marks the current week's open (not completed/skipped) sessions as deload and scales
    /// their set weights by the given deload percentage.
    private func applyDeloadToCurrentWeek(plan: inout ProgressionPlan, deloadPercent: Double) {
        guard let currentWeekId = plan.currentWeek?.id else { return }
        let factor = deloadPercent / 100.0

        for bi in plan.blocks.indices {
            for wi in plan.blocks[bi].weeks.indices where plan.blocks[bi].weeks[wi].id == currentWeekId {
                for si in plan.blocks[bi].weeks[wi].sessions.indices {
                    guard !plan.blocks[bi].weeks[wi].sessions[si].isClosed else { continue }
                    plan.blocks[bi].weeks[wi].sessions[si].isDeload = true
                    for ei in plan.blocks[bi].weeks[wi].sessions[si].plannedExercises.indices {
                        let weight = plan.blocks[bi].weeks[wi].sessions[si].plannedExercises[ei].targetWeight
                        plan.blocks[bi].weeks[wi].sessions[si].plannedExercises[ei].targetWeight =
                            (weight * factor).rounded(toNearest: 2.5)
                    }
                }
                // Week-level deload flag mirrors per-session truth (all-or-nothing).
                plan.blocks[bi].weeks[wi].isDeload =
                    plan.blocks[bi].weeks[wi].sessions.allSatisfy(\.isDeload)
            }
        }
    }

    // MARK: - Template Merge

    public func mergeSessionIntoTemplate(session: PlannedSession, template: WorkoutTemplate, exercises: [Exercise]) -> WorkoutTemplate {
        let plannedLookup = Dictionary(
            session.plannedExercises.map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Name fallback only for UNIQUELY named planned exercises — two variants
        // of the same movement (e.g. plate-loaded vs cable machine) share a name
        // but must never cross-apply each other's targets.
        var nameCounts: [String: Int] = [:]
        for planned in session.plannedExercises {
            nameCounts[planned.exerciseName.lowercased(), default: 0] += 1
        }
        let plannedByName = Dictionary(
            uniqueKeysWithValues: session.plannedExercises
                .filter { nameCounts[$0.exerciseName.lowercased()] == 1 }
                .map { ($0.exerciseName.lowercased(), $0) }
        )

        var mergedExercises = template.exercises.map { te -> TemplateExercise in
            let planned = plannedLookup[te.exercise.id]
                ?? plannedByName[te.exercise.name.lowercased()]
            guard let planned else {
                if session.isDeload {
                    return te.deloaded()
                }
                return te
            }
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

        // Append plan exercises not already covered by the template
        let coveredIds = Set(template.exercises.map { $0.exercise.id })
        let exerciseLookup = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var nextOrder = mergedExercises.count

        for planned in session.plannedExercises where !coveredIds.contains(planned.exerciseId) {
            let exercise = exerciseLookup[planned.exerciseId] ?? Exercise(
                id: planned.exerciseId,
                name: planned.exerciseName,
                primaryMuscleGroup: .other,
                secondaryMuscleGroups: [],
                category: .barbell,
                exerciseType: .weightedReps,
                instructions: nil,
                isCustom: false,
                isArchived: false
            )
            mergedExercises.append(TemplateExercise(
                id: planned.id,
                exercise: exercise,
                order: nextOrder,
                supersetGroup: nil,
                notes: planned.notes,
                restTimerSeconds: planned.restSeconds,
                targetSets: planned.sets,
                targetReps: planned.targetReps,
                targetWeight: planned.targetWeight,
                targetDurationSeconds: nil,
                targetDistanceMeters: nil,
                setTargets: planned.generateSetTargets(),
                isWarmUp: planned.isWarmup
            ))
            nextOrder += 1
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
