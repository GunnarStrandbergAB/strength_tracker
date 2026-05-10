import Foundation

/// Generates structured training blocks for a ProgressionPlan based on its program type.
///
/// Supports four periodization models:
/// - **Linear**: Intensity rises weekly, volume inversely decreases, auto-deload every 4th week.
/// - **DUP**: Hypertrophy/strength/power sessions rotate within each week with %-based overload.
/// - **WUP**: Rep schemes alternate week-to-week (hypertrophy, strength, power cycle).
/// - **Block**: Accumulation -> Transmutation -> Realization -> Deload phases.
/// m9: v1 uses a fixed 12-week mesocycle for all program types. Configurable duration
/// is a planned v2 enhancement (consider adding `targetDurationWeeks` on ProgressionPlan).
public final class ProgramDesignService: Sendable {

    // MARK: - Constants

    private enum IntensityStep {
        static let beginner: Double = 0.025
        static let intermediate: Double = 0.02
        static let advanced: Double = 0.015
    }

    private enum Defaults {
        static let linearWeeks = 12
        static let deloadVolumeMultiplier = 0.5
        static let weeklyOverload = 0.02 // 2% per week for DUP/WUP
    }

    // MARK: - Day Spread

    /// Fixed day-of-week templates keyed by weekly frequency.
    /// dayOfWeek uses ISO 8601: Monday = 2, Tuesday = 3, ... Saturday = 7, Sunday = 1.
    private static let daySpread: [Int: [Int]] = [
        1: [4],              // Wed (midweek)
        2: [2, 5],          // Mon / Thu
        3: [2, 4, 6],       // Mon / Wed / Fri
        4: [2, 3, 5, 6],    // Mon / Tue / Thu / Fri
        5: [2, 3, 4, 6, 7], // Mon / Tue / Wed / Fri / Sat
        6: [2, 3, 4, 5, 6, 7], // Mon - Sat
        7: [1, 2, 3, 4, 5, 6, 7], // Every day
    ]

    private static let dayNames: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
        5: "Thursday", 6: "Friday", 7: "Saturday"
    ]

    // MARK: - Public

    public init() {}

    /// Resolve training days: prefer explicit `trainingDays`, fall back to `daySpread` by frequency.
    private func resolveDays(for plan: ProgressionPlan) -> [Int] {
        plan.trainingDays ?? Self.daySpread[plan.weeklyFrequency] ?? Self.daySpread[3]!
    }

    /// Resolve deload days: prefer explicit `deloadDays`, fall back to regular training days.
    private func resolveDeloadDays(for plan: ProgressionPlan) -> [Int] {
        plan.deloadDays ?? resolveDays(for: plan)
    }

    public func generateProgram(for plan: ProgressionPlan, deloadIntensity: Double = 0.50) -> [TrainingBlock] {
        switch plan.programType {
        case .linear:
            return generateLinearProgram(plan, deloadIntensity: deloadIntensity)
        case .dailyUndulating:
            return generateDUPProgram(plan, deloadIntensity: deloadIntensity)
        case .weeklyUndulating:
            return generateWUPProgram(plan, deloadIntensity: deloadIntensity)
        case .block:
            return generateBlockProgram(plan, deloadIntensity: deloadIntensity)
        }
    }

    // MARK: - Linear Periodization

    private func generateLinearProgram(_ plan: ProgressionPlan, deloadIntensity: Double) -> [TrainingBlock] {
        let totalWeeks = Defaults.linearWeeks
        let step = intensityStep(for: plan.trainingStatus)
        let goalRange = plan.primaryGoal.intensityRange
        let startIntensity = goalRange.lowerBound
        let maxIntensity = goalRange.upperBound
        let restSeconds = middleRest(for: plan.primaryGoal)
        let days = resolveDays(for: plan)
        let deloadDays = resolveDeloadDays(for: plan)

        // Determine if deloads apply (beginner/intermediate get auto-deload every 4th week)
        let needsScheduledDeload = plan.trainingStatus != .advanced

        var blocks: [TrainingBlock] = []
        var absoluteWeek = 1
        var blockOrder = 0
        var currentWeekInCycle = 0
        // m7: Separate counter for non-deload weeks so deload doesn't skip an intensity step
        var progressionWeekCount = 0

        // Build weeks, grouping into blocks of ~4 weeks
        var currentBlockWeeks: [TrainingWeek] = []

        for weekIndex in 0..<totalWeeks {
            currentWeekInCycle += 1

            let isDeloadWeek = needsScheduledDeload && currentWeekInCycle == 4
            let weekIntensity: Double

            if isDeloadWeek {
                // Deload: user-configurable intensity (% of 1RM) from Settings
                weekIntensity = deloadIntensity
            } else {
                // Progressive: step up based on actual training weeks only
                let rawIntensity = startIntensity + (Double(progressionWeekCount) * step)
                weekIntensity = min(rawIntensity, maxIntensity)
                progressionWeekCount += 1
            }

            // Sets decrease as intensity rises — same logic applies to deload weeks.
            let normalizedIntensity = (weekIntensity - goalRange.lowerBound)
                / max(0.001, goalRange.upperBound - goalRange.lowerBound)
            let sets: Int
            if normalizedIntensity > 0.7 {
                sets = 3
            } else {
                sets = 4
            }

            // Reps: upper end early, lower end late
            let repRange = plan.primaryGoal.repRange
            let targetReps: Int
            if isDeloadWeek {
                targetReps = repRange.upperBound
            } else {
                let repSpan = Double(repRange.upperBound - repRange.lowerBound)
                targetReps = repRange.upperBound - Int((normalizedIntensity * repSpan).rounded())
                // Clamp to rep range
            }
            let clampedReps = max(repRange.lowerBound, min(repRange.upperBound, targetReps))

            let weekDays = isDeloadWeek ? deloadDays : days
            let sessions = buildSessions(
                days: weekDays,
                plan: plan,
                sets: sets,
                targetReps: clampedReps,
                intensity: weekIntensity,
                restSeconds: restSeconds,
                dupSessionType: nil,
                label: isDeloadWeek ? "Deload" : "Week \(absoluteWeek)",
                isDeload: isDeloadWeek
            )

            let week = TrainingWeek(
                weekNumber: currentWeekInCycle,
                absoluteWeekNumber: absoluteWeek,
                sessions: sessions,
                isDeload: isDeloadWeek
            )
            currentBlockWeeks.append(week)
            absoluteWeek += 1

            // Emit a block every 4 weeks or at the end
            if currentWeekInCycle == 4 || weekIndex == totalWeeks - 1 {
                let blockIsDeload = currentBlockWeeks.allSatisfy { $0.isDeload }
                let block = TrainingBlock(
                    name: "Block \(blockOrder + 1)",
                    order: blockOrder,
                    durationWeeks: currentBlockWeeks.count,
                    weeks: currentBlockWeeks,
                    isDeload: blockIsDeload,
                    volumeMultiplier: blockIsDeload ? Defaults.deloadVolumeMultiplier : 1.0,
                    intensityFloor: startIntensity + (Double(blockOrder * 4) * step),
                    intensityCeiling: min(
                        startIntensity + (Double((blockOrder + 1) * 4 - 1) * step),
                        maxIntensity
                    )
                )
                blocks.append(block)
                blockOrder += 1
                currentWeekInCycle = 0
                currentBlockWeeks = []
            }
        }

        return blocks
    }

    // MARK: - DUP (Daily Undulating Periodization)

    private func generateDUPProgram(_ plan: ProgressionPlan, deloadIntensity: Double) -> [TrainingBlock] {
        let totalWeeks = Defaults.linearWeeks
        let restSeconds = middleRest(for: plan.primaryGoal)
        let days = resolveDays(for: plan)
        let deloadDays = resolveDeloadDays(for: plan)
        let sessionTypes: [DUPSessionType] = [.hypertrophy, .strength, .power]
        let needsScheduledDeload = plan.trainingStatus != .advanced // M1

        var blocks: [TrainingBlock] = []
        var absoluteWeek = 1
        var blockOrder = 0
        var currentBlockWeeks: [TrainingWeek] = []

        var exerciseRotationCounters: [UUID: Int] = [:] // Per-exercise DUP rotation counters
        var progressionWeekCount = 0 // Continuous overload counter — skips deload weeks
        for weekIndex in 0..<totalWeeks {
            let weekInBlock = (weekIndex % 4) + 1
            let isDeloadWeek = needsScheduledDeload && weekInBlock == 4

            let overloadMultiplier = isDeloadWeek ? 1.0 : 1.0 + (Double(progressionWeekCount) * Defaults.weeklyOverload)

            let weekDays = isDeloadWeek ? deloadDays : days
            var sessions: [PlannedSession] = []
            for day in weekDays {
                let sessionExercises = exercisesForDay(day, in: plan) ?? plan.exercises
                let dayName = Self.dayNames[day] ?? "Day"

                if sessionExercises.isEmpty {
                    // No progression exercises — create session with template link only
                    sessions.append(PlannedSession(
                        dayOfWeek: day,
                        dupSessionType: nil,
                        sessionLabel: isDeloadWeek ? "Deload - \(dayName)" : dayName,
                        plannedExercises: [],
                        estimatedDurationMinutes: 60,
                        templateId: templateIdForDay(day, in: plan),
                        isDeload: isDeloadWeek
                    ))
                } else {
                    // Per-exercise DUP rotation — first exercise's counter determines session type
                    let firstExerciseId = sessionExercises[0].exerciseId
                    let dupType = sessionTypes[(exerciseRotationCounters[firstExerciseId] ?? 0) % sessionTypes.count]

                    let baseIntensity = (dupType.intensityRange.lowerBound + dupType.intensityRange.upperBound) / 2.0
                    let intensity: Double
                    let sets: Int
                    let reps: Int

                    if isDeloadWeek {
                        intensity = deloadIntensity
                        sets = dupType.sets
                        reps = 8
                    } else {
                        intensity = min(
                            baseIntensity * overloadMultiplier,
                            dupType.intensityRange.upperBound
                        )
                        sets = dupType.sets
                        let midReps = (dupType.repRange.lowerBound + dupType.repRange.upperBound) / 2
                        reps = midReps
                    }

                    let label = isDeloadWeek
                        ? "Deload - \(dayName)"
                        : "\(dayName) - \(dupType.rawValue.capitalized)"

                    let exerciseSets = sessionExercises.map { exercise in
                        PlannedExerciseSet(
                            planExerciseId: exercise.id,
                            exerciseId: exercise.exerciseId,
                            exerciseName: exercise.exerciseName,
                            sets: sets,
                            targetReps: reps,
                            targetWeight: exercise.targetWeight(atPercentage: intensity),
                            percentageOf1RM: intensity,
                            restSeconds: restSeconds
                        )
                    }

                    sessions.append(PlannedSession(
                        dayOfWeek: day,
                        dupSessionType: isDeloadWeek ? nil : dupType,
                        sessionLabel: label,
                        plannedExercises: exerciseSets,
                        estimatedDurationMinutes: estimateDuration(exerciseCount: sessionExercises.count, sets: sets, restSeconds: restSeconds),
                        templateId: templateIdForDay(day, in: plan),
                        isDeload: isDeloadWeek
                    ))

                    // Increment each exercise's rotation counter
                    for exercise in sessionExercises {
                        exerciseRotationCounters[exercise.exerciseId, default: 0] += 1
                    }
                }
            }

            if !isDeloadWeek { progressionWeekCount += 1 }

            let week = TrainingWeek(
                weekNumber: weekInBlock,
                absoluteWeekNumber: absoluteWeek,
                sessions: sessions,
                isDeload: isDeloadWeek
            )
            currentBlockWeeks.append(week)
            absoluteWeek += 1

            if weekInBlock == 4 || weekIndex == totalWeeks - 1 {
                let block = TrainingBlock(
                    name: "Block \(blockOrder + 1)",
                    order: blockOrder,
                    durationWeeks: currentBlockWeeks.count,
                    weeks: currentBlockWeeks,
                    isDeload: false,
                    volumeMultiplier: 1.0,
                    intensityFloor: sessionTypes.map(\.intensityRange.lowerBound).min() ?? 0.65,
                    intensityCeiling: sessionTypes.map(\.intensityRange.upperBound).max() ?? 0.95
                )
                blocks.append(block)
                blockOrder += 1
                currentBlockWeeks = []
            }
        }

        return blocks
    }

    // MARK: - WUP (Weekly Undulating Periodization)

    private func generateWUPProgram(_ plan: ProgressionPlan, deloadIntensity: Double) -> [TrainingBlock] {
        let totalWeeks = Defaults.linearWeeks
        let restSeconds = middleRest(for: plan.primaryGoal)
        let days = resolveDays(for: plan)
        let deloadDays = resolveDeloadDays(for: plan)
        let schemeRotation: [DUPSessionType] = [.hypertrophy, .strength, .power]
        let needsScheduledDeload = plan.trainingStatus != .advanced // M1

        var blocks: [TrainingBlock] = []
        var absoluteWeek = 1
        var blockOrder = 0
        var currentBlockWeeks: [TrainingWeek] = []

        var progressionWeekCount = 0 // Continuous overload counter — skips deload weeks
        for weekIndex in 0..<totalWeeks {
            let weekInBlock = (weekIndex % 4) + 1
            let isDeloadWeek = needsScheduledDeload && weekInBlock == 4

            let scheme = schemeRotation[weekIndex % schemeRotation.count]
            let overloadMultiplier = isDeloadWeek ? 1.0 : 1.0 + (Double(progressionWeekCount) * Defaults.weeklyOverload)

            let baseIntensity = (scheme.intensityRange.lowerBound + scheme.intensityRange.upperBound) / 2.0
            let intensity: Double
            let sets: Int
            let reps: Int

            if isDeloadWeek {
                intensity = deloadIntensity
                sets = scheme.sets
                reps = 8
            } else {
                intensity = min(
                    baseIntensity * overloadMultiplier,
                    scheme.intensityRange.upperBound
                )
                sets = scheme.sets
                reps = (scheme.repRange.lowerBound + scheme.repRange.upperBound) / 2
            }

            let weekDays = isDeloadWeek ? deloadDays : days
            let sessions = buildSessions(
                days: weekDays,
                plan: plan,
                sets: sets,
                targetReps: reps,
                intensity: intensity,
                restSeconds: restSeconds,
                dupSessionType: nil,
                label: isDeloadWeek
                    ? "Deload"
                    : "Week \(absoluteWeek) - \(scheme.rawValue.capitalized)",
                isDeload: isDeloadWeek
            )

            if !isDeloadWeek { progressionWeekCount += 1 }

            let week = TrainingWeek(
                weekNumber: weekInBlock,
                absoluteWeekNumber: absoluteWeek,
                sessions: sessions,
                isDeload: isDeloadWeek
            )
            currentBlockWeeks.append(week)
            absoluteWeek += 1

            if weekInBlock == 4 || weekIndex == totalWeeks - 1 {
                let block = TrainingBlock(
                    name: "Block \(blockOrder + 1)",
                    order: blockOrder,
                    durationWeeks: currentBlockWeeks.count,
                    weeks: currentBlockWeeks,
                    isDeload: false,
                    volumeMultiplier: 1.0,
                    intensityFloor: schemeRotation.map(\.intensityRange.lowerBound).min() ?? 0.65,
                    intensityCeiling: schemeRotation.map(\.intensityRange.upperBound).max() ?? 0.95
                )
                blocks.append(block)
                blockOrder += 1
                currentBlockWeeks = []
            }
        }

        return blocks
    }

    // MARK: - Block Periodization

    private func generateBlockProgram(_ plan: ProgressionPlan, deloadIntensity: Double) -> [TrainingBlock] {
        let restSeconds = middleRest(for: plan.primaryGoal)
        let days = resolveDays(for: plan)
        let deloadDays = resolveDeloadDays(for: plan)
        let phases: [BlockPhase] = [.accumulation, .transmutation, .realization, .deload]

        var blocks: [TrainingBlock] = []
        var absoluteWeek = 1

        for (blockOrder, phase) in phases.enumerated() {
            let duration = phase.weekDuration
            var weeks: [TrainingWeek] = []

            for weekInPhase in 0..<duration {
                let phaseParams = blockPhaseParams(phase, weekInPhase: weekInPhase, totalPhaseWeeks: duration, deloadIntensity: deloadIntensity)

                let weekDays = phase == .deload ? deloadDays : days
                let sessions = buildSessions(
                    days: weekDays,
                    plan: plan,
                    sets: phaseParams.sets,
                    targetReps: phaseParams.reps,
                    intensity: phaseParams.intensity,
                    restSeconds: restSeconds,
                    dupSessionType: nil,
                    label: "\(phase.rawValue.capitalized) W\(weekInPhase + 1)",
                    isDeload: phase == .deload
                )

                let week = TrainingWeek(
                    weekNumber: weekInPhase + 1,
                    absoluteWeekNumber: absoluteWeek,
                    sessions: sessions,
                    isDeload: phase == .deload
                )
                weeks.append(week)
                absoluteWeek += 1
            }

            let block = TrainingBlock(
                name: phase.rawValue.capitalized,
                blockPhase: phase,
                order: blockOrder,
                durationWeeks: duration,
                weeks: weeks,
                isDeload: phase == .deload,
                volumeMultiplier: phase == .deload ? Defaults.deloadVolumeMultiplier : 1.0,
                intensityFloor: blockPhaseIntensityFloor(phase),
                intensityCeiling: blockPhaseIntensityCeiling(phase)
            )
            blocks.append(block)
        }

        return blocks
    }

    // MARK: - Day Schedule Helpers

    /// Returns the exercises assigned to a specific day via the plan's daySchedule.
    /// - Returns `nil` when no schedule is configured at all (legacy plans → caller uses all exercises).
    /// - Returns `[]` when a schedule exists but this day has no exercises (intentionally empty day).
    private func exercisesForDay(_ day: Int, in plan: ProgressionPlan) -> [PlanExercise]? {
        // No day schedule configured → nil (legacy: caller falls back to all exercises)
        guard !plan.daySchedule.isEmpty else { return nil }
        // Schedule configured but this day has no entry or empty exercises → empty list
        guard let entry = plan.daySchedule.first(where: { $0.dayOfWeek == day }),
              !entry.exerciseIds.isEmpty else { return [] }
        let filtered = plan.exercises.filter { entry.exerciseIds.contains($0.exerciseId) }
        return filtered.isEmpty ? [] : filtered
    }

    /// Returns the templateId assigned to a specific day via the plan's daySchedule.
    private func templateIdForDay(_ day: Int, in plan: ProgressionPlan) -> UUID? {
        plan.daySchedule.first(where: { $0.dayOfWeek == day })?.templateId
    }

    // MARK: - Helpers

    private func intensityStep(for status: TrainingStatus) -> Double {
        switch status {
        case .beginner: return IntensityStep.beginner
        case .intermediate: return IntensityStep.intermediate
        case .advanced: return IntensityStep.advanced
        }
    }

    private func middleRest(for goal: TrainingGoal) -> Int {
        let range = goal.restSeconds
        return (range.lowerBound + range.upperBound) / 2
    }

    private func estimateDuration(exerciseCount: Int, sets: Int, restSeconds: Int) -> Int {
        // Rough estimate: each set takes ~45s of work + rest
        let totalSets = exerciseCount * sets
        let workTime = totalSets * 45
        let restTime = totalSets * restSeconds
        return max(30, (workTime + restTime) / 60)
    }

    /// Build sessions for a given week, distributing exercises across day slots.
    /// Uses `plan.daySchedule` to filter exercises and assign templateId per day.
    /// Days with no scheduled exercises produce sessions with empty plannedExercises.
    private func buildSessions(
        days: [Int],
        plan: ProgressionPlan,
        sets: Int,
        targetReps: Int,
        intensity: Double,
        restSeconds: Int,
        dupSessionType: DUPSessionType?,
        label: String,
        isDeload: Bool = false
    ) -> [PlannedSession] {
        days.map { day in
            let dayName = Self.dayNames[day] ?? "Day"
            let sessionExercises = exercisesForDay(day, in: plan) ?? plan.exercises

            if sessionExercises.isEmpty {
                return PlannedSession(
                    dayOfWeek: day,
                    dupSessionType: nil,
                    sessionLabel: days.count > 1 ? "\(label) - \(dayName)" : label,
                    plannedExercises: [],
                    estimatedDurationMinutes: 60,
                    templateId: templateIdForDay(day, in: plan),
                    isDeload: isDeload
                )
            }

            let sessionLabel = days.count > 1 ? "\(label) - \(dayName)" : label
            let exerciseSets = sessionExercises.map { exercise in
                PlannedExerciseSet(
                    planExerciseId: exercise.id,
                    exerciseId: exercise.exerciseId,
                    exerciseName: exercise.exerciseName,
                    sets: sets,
                    targetReps: targetReps,
                    targetWeight: exercise.targetWeight(atPercentage: intensity),
                    percentageOf1RM: intensity,
                    restSeconds: restSeconds
                )
            }

            return PlannedSession(
                dayOfWeek: day,
                dupSessionType: dupSessionType,
                sessionLabel: sessionLabel,
                plannedExercises: exerciseSets,
                estimatedDurationMinutes: estimateDuration(
                    exerciseCount: sessionExercises.count,
                    sets: sets,
                    restSeconds: restSeconds
                ),
                templateId: templateIdForDay(day, in: plan),
                isDeload: isDeload
            )
        }
    }

    // MARK: - Block Phase Parameters

    private struct PhaseParams {
        let intensity: Double
        let sets: Int
        let reps: Int
    }

    /// m8: Block periodization uses fixed intra-phase templates — week-over-week progression
    /// within each phase is intentional (volume/intensity ramp within each mesocycle block).
    /// This differs from DUP/WUP where the entire scheme is fixed per session type.
    private func blockPhaseParams(_ phase: BlockPhase, weekInPhase: Int, totalPhaseWeeks: Int, deloadIntensity: Double) -> PhaseParams {
        switch phase {
        case .accumulation:
            // 65-75% 1RM, 3-4 sets, 8-12 reps. Progress within phase.
            let progress = totalPhaseWeeks > 1 ? Double(weekInPhase) / Double(totalPhaseWeeks - 1) : 0
            let intensity = 0.65 + (progress * 0.10) // 65% -> 75%
            let sets = progress > 0.5 ? 4 : 3
            let reps = 12 - Int(progress * 4) // 12 -> 8
            return PhaseParams(intensity: intensity, sets: sets, reps: max(8, reps))

        case .transmutation:
            // 78-88% 1RM, 4-5 sets, 4-6 reps
            let progress = totalPhaseWeeks > 1 ? Double(weekInPhase) / Double(totalPhaseWeeks - 1) : 0
            let intensity = 0.78 + (progress * 0.10) // 78% -> 88%
            let sets = progress > 0.5 ? 5 : 4
            let reps = 6 - Int(progress * 2) // 6 -> 4
            return PhaseParams(intensity: intensity, sets: sets, reps: max(4, reps))

        case .realization:
            // 88-100% 1RM, 3-5 sets, 1-3 reps
            let progress = totalPhaseWeeks > 1 ? Double(weekInPhase) / Double(totalPhaseWeeks - 1) : 0
            let intensity = 0.88 + (progress * 0.12) // 88% -> 100%
            let sets = 5 - Int(progress * 2) // 5 -> 3
            let reps = 3 - Int(progress * 2) // 3 -> 1
            return PhaseParams(intensity: intensity, sets: max(3, sets), reps: max(1, reps))

        case .deload:
            // User-configurable deload intensity; keep a real volume floor (no halving of sets).
            return PhaseParams(intensity: deloadIntensity, sets: 3, reps: 10)
        }
    }

    private func blockPhaseIntensityFloor(_ phase: BlockPhase) -> Double {
        switch phase {
        case .accumulation: return 0.65
        case .transmutation: return 0.78
        case .realization: return 0.88
        case .deload: return 0.40
        }
    }

    private func blockPhaseIntensityCeiling(_ phase: BlockPhase) -> Double {
        switch phase {
        case .accumulation: return 0.75
        case .transmutation: return 0.88
        case .realization: return 1.00
        case .deload: return 0.60
        }
    }
}
