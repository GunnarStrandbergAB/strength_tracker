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

    // MARK: - Init

    public init(
        progressionPlanRepository: any ProgressionPlanRepository,
        trainingStatusDetector: TrainingStatusDetector,
        programDesignService: ProgramDesignService,
        planAnalyticsService: PlanAnalyticsService,
        exerciseRepository: any ExerciseRepository,
        templateRepository: any TemplateRepository,
        userPreferencesService: UserPreferencesService? = nil
    ) {
        self.progressionPlanRepository = progressionPlanRepository
        self.trainingStatusDetector = trainingStatusDetector
        self.programDesignService = programDesignService
        self.planAnalyticsService = planAnalyticsService
        self.exerciseRepository = exerciseRepository
        self.templateRepository = templateRepository
        self.userPreferencesService = userPreferencesService
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
    }

    // MARK: - Weekday Selection

    /// Default day-of-week templates (ISO 8601: Mon=2..Sat=7, Sun=1).
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

    /// ISO weekday number for a given date (Sun=1, Mon=2, ..., Sat=7)
    private func isoDayOfWeek(_ date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date) // Sun=1..Sat=7
        return weekday
    }

    /// Returns the next training day on or after today.
    public func defaultStartDate() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard !draftTrainingDays.isEmpty else { return today }
        let todayISO = isoDayOfWeek(today)
        if draftTrainingDays.contains(todayISO) { return today }
        for offset in 1...7 {
            let candidate = calendar.date(byAdding: .day, value: offset, to: today)!
            if draftTrainingDays.contains(isoDayOfWeek(candidate)) { return candidate }
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

    private func assignScheduledDates(to plan: inout ProgressionPlan) {
        let calendar = Calendar.current
        let planStartDay = calendar.startOfDay(for: plan.startDate)
        let startISO = calendar.component(.weekday, from: planStartDay) // Sun=1..Sat=7

        for blockIdx in plan.blocks.indices {
            for weekIdx in plan.blocks[blockIdx].weeks.indices {
                let weekNum = plan.blocks[blockIdx].weeks[weekIdx].absoluteWeekNumber
                let weekAnchor = calendar.date(byAdding: .day, value: (weekNum - 1) * 7, to: planStartDay)!

                for sessionIdx in plan.blocks[blockIdx].weeks[weekIdx].sessions.indices {
                    guard let dow = plan.blocks[blockIdx].weeks[weekIdx].sessions[sessionIdx].dayOfWeek else { continue }
                    let dayOffset = (dow - startISO + 7) % 7
                    let sessionDate = calendar.date(byAdding: .day, value: dayOffset, to: weekAnchor)!
                    plan.blocks[blockIdx].weeks[weekIdx].sessions[sessionIdx].scheduledDate = sessionDate
                }
            }
        }
    }

    public func rescheduleSession(sessionId: UUID, to newDate: Date) async {
        guard var plan = activePlan else { return }
        for blockIdx in plan.blocks.indices {
            for weekIdx in plan.blocks[blockIdx].weeks.indices {
                if let sIdx = plan.blocks[blockIdx].weeks[weekIdx].sessions.firstIndex(where: { $0.id == sessionId }) {
                    plan.blocks[blockIdx].weeks[weekIdx].sessions[sIdx].scheduledDate = newDate
                    plan.updatedAt = Date()
                    do {
                        try await progressionPlanRepository.save(plan)
                        activePlan = plan
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    return
                }
            }
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

            let startWeekday = Calendar.current.component(.weekday, from: draftStartDate)
            let startFirstOrder = (0..<7).map { (startWeekday - 1 + $0) % 7 + 1 }
            let sortedDays = draftTrainingDays.isEmpty
                ? nil
                : startFirstOrder.filter { draftTrainingDays.contains($0) }

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

            var plan = ProgressionPlan(
                name: draftPlanName.isEmpty ? "Training Plan" : draftPlanName,
                status: .active,
                trainingStatus: draftStatus,
                programType: draftProgramType,
                primaryGoal: draftGoal,
                weeklyFrequency: draftFrequency,
                trainingDays: sortedDays,
                deloadDays: sortedDeloadDays,
                startDate: draftStartDate,
                exercises: planExercises,
                daySchedule: daySchedule,
                creationSource: .structuredFlow
            )

            let deloadIntensity = Double(userPreferencesService?.deloadWeightPercentage ?? 50) / 100.0
            let blocks = programDesignService.generateProgram(for: plan, deloadIntensity: deloadIntensity)
            plan.blocks = blocks

            // Assign concrete scheduled dates to all sessions
            assignScheduledDates(to: &plan)

            // Sort sessions chronologically within each week
            for blockIdx in plan.blocks.indices {
                for weekIdx in plan.blocks[blockIdx].weeks.indices {
                    plan.blocks[blockIdx].weeks[weekIdx].sessions.sort {
                        ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture)
                    }
                }
            }

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

        // Early-exit: same template + same auto-pick = nothing to do.
        if let existing = plan.daySchedule.first(where: { $0.dayOfWeek == dayOfWeek }),
           existing.templateId == templateId,
           Set(existing.exerciseIds) == autoPickedIds {
            return
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
                            autoPickedIds: autoPickedIds
                        )
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

    /// Rebuild a target-day session's planned exercises for a newly-linked template.
    ///
    /// For each exercise in the new template that is also a tracked PlanExercise
    /// (`autoPickedIds`), inherit intensity / sets / reps / rest from the first non-empty
    /// `PlannedExerciseSet` in the same week (any day) and compute `targetWeight` per the
    /// PlanExercise's own 1RM. Non-tracked template exercises fall back to template defaults.
    static func rebuildSessionExercises(
        inWeek week: TrainingWeek,
        newTemplate: WorkoutTemplate,
        planExercises: [PlanExercise],
        autoPickedIds: Set<UUID>
    ) -> [PlannedExerciseSet] {
        let planExerciseById = Dictionary(
            planExercises.map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Intensity donor: first non-empty plannedExercises in this week's sessions.
        let donor: PlannedExerciseSet? = week.sessions
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

    public func handleSessionCompleted(sessionId: UUID, planId: UUID, workoutId: UUID) async {
        do {
            try await progressionPlanRepository.markSessionCompleted(sessionId, workoutId: workoutId, inPlan: planId)
            await loadActivePlan()
        } catch {
            errorMessage = "Failed to mark session completed: \(error.localizedDescription)"
        }
    }

    // MARK: - Template Merge

    public func mergeSessionIntoTemplate(session: PlannedSession, template: WorkoutTemplate, exercises: [Exercise]) -> WorkoutTemplate {
        let plannedLookup = Dictionary(
            session.plannedExercises.map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let plannedByName = Dictionary(
            session.plannedExercises.map { ($0.exerciseName.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
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
