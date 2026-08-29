import Foundation

/// Generates progress snapshots for a progression plan by analyzing session completion,
/// exercise 1RM changes, and weekly volume from linked workouts.
@MainActor
public final class PlanAnalyticsService: Sendable {
    private let workoutRepository: any WorkoutRepository
    private let userPreferencesService: UserPreferencesService?

    public init(workoutRepository: any WorkoutRepository, userPreferencesService: UserPreferencesService? = nil) {
        self.workoutRepository = workoutRepository
        self.userPreferencesService = userPreferencesService
    }

    private var bodyWeightKg: Double {
        userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }

    // MARK: - Public API

    /// Generate a progress snapshot for the plan.
    ///
    /// Session-linkage attribution (Review Fix #1):
    /// 1. If session.completedWorkoutId is set, use that workout
    /// 2. Else try matching by templateId
    /// 3. Else try matching by date proximity (within 2 days of scheduledDate)
    public func generateProgress(for plan: ProgressionPlan) async throws -> PlanProgress {
        let allWorkouts = try await workoutRepository.fetchAll()
        let completedWorkouts = allWorkouts.filter { $0.completedAt != nil }

        let allSessions = plan.blocks.flatMap(\.weeks).flatMap(\.sessions)
        let completedSessions = allSessions.filter(\.isCompleted).count

        // Adherence: only count sessions in elapsed weeks (current week included),
        // and within the current week only sessions scheduled on or before today.
        let currentWeekNumber = plan.elapsedCalendarWeeks + 1
        let today = Calendar.current.startOfDay(for: Date())
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let elapsedSessions = plan.blocks.flatMap(\.weeks)
            .filter { $0.absoluteWeekNumber <= currentWeekNumber }
            .flatMap(\.sessions)
            .filter { session in
                guard let scheduledDate = session.scheduledDate else { return true }
                return scheduledDate < endOfToday
            }
        let totalElapsed = elapsedSessions.count

        let overallAdherence: Double
        if totalElapsed > 0 {
            overallAdherence = min(1.0, Double(completedSessions) / Double(totalElapsed))
        } else {
            overallAdherence = 0
        }

        // Build a lookup for resolved workouts per session
        let workoutById = Dictionary(completedWorkouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let resolvedWorkouts = resolveWorkouts(
            sessions: allSessions,
            workoutById: workoutById,
            allWorkouts: completedWorkouts
        )

        // Exercise progress
        let exerciseProgress = buildExerciseProgress(
            planExercises: plan.exercises,
            resolvedWorkouts: resolvedWorkouts
        )

        // Block progress
        let blockProgress = buildBlockProgress(blocks: plan.blocks, resolvedWorkouts: resolvedWorkouts)

        // Weekly volume history
        let weeklyVolumeHistory = buildWeeklyVolumeHistory(
            blocks: plan.blocks,
            resolvedWorkouts: resolvedWorkouts
        )

        // Deload and adjustment counts
        let deloadCount = plan.adjustments.filter { $0.adjustmentType == .deload }.count
        let adjustmentCount = plan.adjustments.count

        let isOnTrack = overallAdherence >= 0.75

        return PlanProgress(
            planId: plan.id,
            snapshotDate: Date(),
            overallAdherence: overallAdherence,
            exerciseProgress: exerciseProgress,
            blockProgress: blockProgress,
            estimatedCompletionDate: plan.projectedEndDate,
            isOnTrack: isOnTrack,
            weeklyVolumeHistory: weeklyVolumeHistory,
            deloadCount: deloadCount,
            adjustmentCount: adjustmentCount
        )
    }

    // MARK: - Session-Workout Resolution

    /// Resolves each session to its linked workout using the 3-tier attribution strategy.
    private func resolveWorkouts(
        sessions: [PlannedSession],
        workoutById: [UUID: Workout],
        allWorkouts: [Workout]
    ) -> [UUID: Workout] {
        var result: [UUID: Workout] = [:]

        for session in sessions {
            if let resolved = resolveWorkout(
                for: session,
                workoutById: workoutById,
                allWorkouts: allWorkouts
            ) {
                result[session.id] = resolved
            }
        }

        return result
    }

    private func resolveWorkout(
        for session: PlannedSession,
        workoutById: [UUID: Workout],
        allWorkouts: [Workout]
    ) -> Workout? {
        // 1. Direct link via completedWorkoutId
        if let workoutId = session.completedWorkoutId,
           let workout = workoutById[workoutId] {
            return workout
        }

        // 2. M6: Match by templateId — session.templateId matches workout.templateId
        if let sessionTemplateId = session.templateId {
            let templateMatch = allWorkouts.first { $0.templateId == sessionTemplateId }
            if let templateMatch = templateMatch {
                return templateMatch
            }
        }

        // 3. Date proximity: within 2 days of scheduledDate
        if let scheduledDate = session.scheduledDate {
            let twoDays: TimeInterval = 2 * 24 * 3600
            let match = allWorkouts
                .filter { workout in
                    guard let completedAt = workout.completedAt else { return false }
                    return abs(completedAt.timeIntervalSince(scheduledDate)) <= twoDays
                }
                .min { a, b in  // m3: Use closest match, not arbitrary first
                    let aDistance = abs((a.completedAt ?? a.startedAt).timeIntervalSince(scheduledDate))
                    let bDistance = abs((b.completedAt ?? b.startedAt).timeIntervalSince(scheduledDate))
                    return aDistance < bDistance
                }
            if let match = match {
                return match
            }
        }

        return nil
    }

    // MARK: - Exercise Progress

    private func buildExerciseProgress(
        planExercises: [PlanExercise],
        resolvedWorkouts: [UUID: Workout]
    ) -> [ExerciseProgress] {
        planExercises.map { planExercise in
            let allLinkedWorkouts = Array(resolvedWorkouts.values)

            var totalSets = 0
            var totalReps = 0
            var totalVolume: Double = 0
            var lastDate: Date?
            var prCount = 0  // m4

            for workout in allLinkedWorkouts {
                for workoutExercise in workout.exercises {
                    guard workoutExercise.exercise.id == planExercise.exerciseId else { continue }
                    for set in workoutExercise.sets where set.isCompleted && set.setType != .warmup {
                        // A drop set counts as ONE working set; its reps and volume
                        // include every segment.
                        totalSets += 1
                        totalReps += set.totalReps
                        totalVolume += set.setVolume(baseLoadPerRep: workoutExercise.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg))
                        if set.isPersonalRecord { prCount += 1 }  // m4
                    }
                    if let completedAt = workout.completedAt {
                        if lastDate == nil || completedAt > lastDate! {
                            lastDate = completedAt
                        }
                    }
                }
            }

            let starting1RM = planExercise.estimated1RM
            let current1RM = planExercise.current1RM
            let progressPercentage: Double
            if starting1RM > 0 {
                progressPercentage = (current1RM - starting1RM) / starting1RM * 100
            } else {
                progressPercentage = 0
            }

            return ExerciseProgress(
                planExerciseId: planExercise.id,
                exerciseName: planExercise.exerciseName,
                starting1RM: starting1RM,
                current1RM: current1RM,
                target1RM: planExercise.target1RM,
                progressPercentage: progressPercentage,
                lastPerformedDate: lastDate,
                totalSetsCompleted: totalSets,
                totalRepsCompleted: totalReps,
                totalVolumeLifted: totalVolume,
                personalRecordsHit: prCount  // m4
            )
        }
    }

    // MARK: - Block Progress

    private func buildBlockProgress(
        blocks: [TrainingBlock],
        resolvedWorkouts: [UUID: Workout]
    ) -> [BlockProgress] {
        blocks.map { block in
            let weeklyAdherence = block.weeks.map { $0.adherenceRate }

            // Volume trend: compare last week's volume to first week's volume
            let weekVolumes = block.weeks.map { week -> Double in
                week.sessions.compactMap { session -> Double? in
                    guard let workout = resolvedWorkouts[session.id] else { return nil }
                    return workout.totalVolume(bodyWeightKg: bodyWeightKg)
                }.reduce(0, +)
            }

            let volumeTrend: Double
            if let first = weekVolumes.first, let last = weekVolumes.last, first > 0 {
                volumeTrend = (last - first) / first
            } else {
                volumeTrend = 0
            }

            // m5: Calculate averageRPE from resolved workout sets
            var totalRPE: Double = 0
            var rpeCount = 0
            for week in block.weeks {
                for session in week.sessions {
                    guard let workout = resolvedWorkouts[session.id] else { continue }
                    for workoutExercise in workout.exercises {
                        for set in workoutExercise.sets where set.isCompleted {
                            if let rpe = set.rpe {
                                totalRPE += rpe
                                rpeCount += 1
                            }
                        }
                    }
                }
            }
            let averageRPE: Double? = rpeCount > 0 ? totalRPE / Double(rpeCount) : nil

            return BlockProgress(
                blockId: block.id,
                blockName: block.name,
                weeklyAdherence: weeklyAdherence,
                averageRPE: averageRPE,
                volumeTrend: volumeTrend
            )
        }
    }

    // MARK: - Weekly Volume History

    private func buildWeeklyVolumeHistory(
        blocks: [TrainingBlock],
        resolvedWorkouts: [UUID: Workout]
    ) -> [WeeklyVolume] {
        let allWeeks = blocks.flatMap(\.weeks)
        return allWeeks.compactMap { week -> WeeklyVolume? in
            guard week.allSessionsCompleted else { return nil }

            var totalVolume: Double = 0
            var totalIntensity: Double = 0
            var intensityCount = 0
            var sessionCount = 0

            for session in week.sessions {
                guard let workout = resolvedWorkouts[session.id] else { continue }
                sessionCount += 1
                totalVolume += workout.totalVolume(bodyWeightKg: bodyWeightKg)

                // Average intensity from RPE values across sets
                for workoutExercise in workout.exercises {
                    for set in workoutExercise.sets where set.isCompleted {
                        if let rpe = set.rpe {
                            totalIntensity += rpe
                            intensityCount += 1
                        }
                    }
                }
            }

            let avgIntensity = intensityCount > 0 ? totalIntensity / Double(intensityCount) : 0

            return WeeklyVolume(
                weekNumber: week.absoluteWeekNumber,
                totalVolume: totalVolume,
                averageIntensity: avgIntensity,
                sessionCount: sessionCount
            )
        }
    }
}
