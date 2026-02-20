import Foundation

/// Generates structured training blocks for a ProgressionPlan based on its program type.
///
/// Supports four periodization models:
/// - **Linear**: Intensity rises weekly, volume inversely decreases, auto-deload every 4th week.
/// - **DUP**: Hypertrophy/strength/power sessions rotate within each week with %-based overload.
/// - **WUP**: Rep schemes alternate week-to-week (hypertrophy, strength, power cycle).
/// - **Block**: Accumulation -> Transmutation -> Realization -> Deload phases.
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
        3: [2, 4, 6],       // Mon / Wed / Fri
        4: [2, 3, 5, 6],    // Mon / Tue / Thu / Fri
        5: [2, 3, 4, 6, 7], // Mon / Tue / Wed / Fri / Sat
        6: [2, 3, 4, 5, 6, 7], // Mon - Sat
    ]

    private static let dayNames: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
        5: "Thursday", 6: "Friday", 7: "Saturday"
    ]

    // MARK: - Public

    public init() {}

    public func generateProgram(for plan: ProgressionPlan) -> [TrainingBlock] {
        switch plan.programType {
        case .linear:
            return generateLinearProgram(plan)
        case .dailyUndulating:
            return generateDUPProgram(plan)
        case .weeklyUndulating:
            return generateWUPProgram(plan)
        case .block:
            return generateBlockProgram(plan)
        }
    }

    // MARK: - Linear Periodization

    private func generateLinearProgram(_ plan: ProgressionPlan) -> [TrainingBlock] {
        let totalWeeks = Defaults.linearWeeks
        let step = intensityStep(for: plan.trainingStatus)
        let goalRange = plan.primaryGoal.intensityRange
        let startIntensity = goalRange.lowerBound
        let maxIntensity = goalRange.upperBound
        let restSeconds = middleRest(for: plan.primaryGoal)
        let days = Self.daySpread[plan.weeklyFrequency] ?? Self.daySpread[3]!

        // Determine if deloads apply (beginner/intermediate get auto-deload every 4th week)
        let needsScheduledDeload = plan.trainingStatus != .advanced

        var blocks: [TrainingBlock] = []
        var absoluteWeek = 1
        var blockOrder = 0
        var currentWeekInCycle = 0

        // Build weeks, grouping into blocks of ~4 weeks
        var currentBlockWeeks: [TrainingWeek] = []
        var blockStartIntensity = startIntensity

        for weekIndex in 0..<totalWeeks {
            currentWeekInCycle += 1

            let isDeloadWeek = needsScheduledDeload && currentWeekInCycle == 4
            let weekIntensity: Double

            if isDeloadWeek {
                // Deload: use start intensity of current block
                weekIntensity = blockStartIntensity
            } else {
                // Progressive: step up from start
                let rawIntensity = startIntensity + (Double(weekIndex) * step)
                weekIntensity = min(rawIntensity, maxIntensity)
            }

            // Sets decrease as intensity rises
            let normalizedIntensity = (weekIntensity - goalRange.lowerBound)
                / max(0.001, goalRange.upperBound - goalRange.lowerBound)
            let sets: Int
            if isDeloadWeek {
                sets = 2
            } else if normalizedIntensity > 0.7 {
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

            let sessions = buildSessions(
                days: days,
                exercises: plan.exercises,
                sets: sets,
                targetReps: clampedReps,
                intensity: weekIntensity,
                restSeconds: restSeconds,
                dupSessionType: nil,
                label: isDeloadWeek ? "Deload" : "Week \(absoluteWeek)"
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
                blockStartIntensity = weekIntensity
                currentBlockWeeks = []
            }
        }

        return blocks
    }

    // MARK: - DUP (Daily Undulating Periodization)

    private func generateDUPProgram(_ plan: ProgressionPlan) -> [TrainingBlock] {
        let totalWeeks = Defaults.linearWeeks
        let restSeconds = middleRest(for: plan.primaryGoal)
        let days = Self.daySpread[plan.weeklyFrequency] ?? Self.daySpread[3]!
        let sessionTypes: [DUPSessionType] = [.hypertrophy, .strength, .power]

        var blocks: [TrainingBlock] = []
        var absoluteWeek = 1
        var blockOrder = 0
        var currentBlockWeeks: [TrainingWeek] = []

        for weekIndex in 0..<totalWeeks {
            let weekInBlock = (weekIndex % 4) + 1
            let isDeloadWeek = weekInBlock == 4

            let overloadMultiplier = 1.0 + (Double(weekIndex) * Defaults.weeklyOverload)

            var sessions: [PlannedSession] = []
            for (dayIndex, day) in days.enumerated() {
                let dupType = sessionTypes[dayIndex % sessionTypes.count]
                let baseIntensity = (dupType.intensityRange.lowerBound + dupType.intensityRange.upperBound) / 2.0
                let intensity: Double
                let sets: Int
                let reps: Int

                if isDeloadWeek {
                    intensity = baseIntensity
                    sets = max(2, dupType.sets - 1)
                    reps = dupType.repRange.upperBound
                } else {
                    // Apply overload: scale intensity up from midpoint, clamped to range upper bound
                    intensity = min(
                        baseIntensity * overloadMultiplier,
                        dupType.intensityRange.upperBound
                    )
                    sets = dupType.sets
                    let midReps = (dupType.repRange.lowerBound + dupType.repRange.upperBound) / 2
                    reps = midReps
                }

                let dayName = Self.dayNames[day] ?? "Day \(dayIndex + 1)"
                let label = isDeloadWeek
                    ? "Deload - \(dupType.rawValue.capitalized)"
                    : "\(dayName) - \(dupType.rawValue.capitalized)"

                let exerciseSets = plan.exercises.map { exercise in
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

                let session = PlannedSession(
                    dayOfWeek: day,
                    dupSessionType: dupType,
                    sessionLabel: label,
                    plannedExercises: exerciseSets,
                    estimatedDurationMinutes: estimateDuration(exerciseCount: plan.exercises.count, sets: sets, restSeconds: restSeconds)
                )
                sessions.append(session)
            }

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

    private func generateWUPProgram(_ plan: ProgressionPlan) -> [TrainingBlock] {
        let totalWeeks = Defaults.linearWeeks
        let restSeconds = middleRest(for: plan.primaryGoal)
        let days = Self.daySpread[plan.weeklyFrequency] ?? Self.daySpread[3]!
        let schemeRotation: [DUPSessionType] = [.hypertrophy, .strength, .power]

        var blocks: [TrainingBlock] = []
        var absoluteWeek = 1
        var blockOrder = 0
        var currentBlockWeeks: [TrainingWeek] = []

        for weekIndex in 0..<totalWeeks {
            let weekInBlock = (weekIndex % 4) + 1
            let isDeloadWeek = weekInBlock == 4

            let scheme = schemeRotation[weekIndex % schemeRotation.count]
            let overloadMultiplier = 1.0 + (Double(weekIndex) * Defaults.weeklyOverload)

            let baseIntensity = (scheme.intensityRange.lowerBound + scheme.intensityRange.upperBound) / 2.0
            let intensity: Double
            let sets: Int
            let reps: Int

            if isDeloadWeek {
                intensity = baseIntensity
                sets = max(2, scheme.sets - 1)
                reps = scheme.repRange.upperBound
            } else {
                intensity = min(
                    baseIntensity * overloadMultiplier,
                    scheme.intensityRange.upperBound
                )
                sets = scheme.sets
                reps = (scheme.repRange.lowerBound + scheme.repRange.upperBound) / 2
            }

            let sessions = buildSessions(
                days: days,
                exercises: plan.exercises,
                sets: sets,
                targetReps: reps,
                intensity: intensity,
                restSeconds: restSeconds,
                dupSessionType: nil,
                label: isDeloadWeek
                    ? "Deload - \(scheme.rawValue.capitalized)"
                    : "Week \(absoluteWeek) - \(scheme.rawValue.capitalized)"
            )

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

    private func generateBlockProgram(_ plan: ProgressionPlan) -> [TrainingBlock] {
        let restSeconds = middleRest(for: plan.primaryGoal)
        let days = Self.daySpread[plan.weeklyFrequency] ?? Self.daySpread[3]!
        let phases: [BlockPhase] = [.accumulation, .transmutation, .realization, .deload]

        var blocks: [TrainingBlock] = []
        var absoluteWeek = 1

        for (blockOrder, phase) in phases.enumerated() {
            let duration = phase.weekDuration
            var weeks: [TrainingWeek] = []

            for weekInPhase in 0..<duration {
                let phaseParams = blockPhaseParams(phase, weekInPhase: weekInPhase, totalPhaseWeeks: duration)

                let sessions = buildSessions(
                    days: days,
                    exercises: plan.exercises,
                    sets: phaseParams.sets,
                    targetReps: phaseParams.reps,
                    intensity: phaseParams.intensity,
                    restSeconds: restSeconds,
                    dupSessionType: nil,
                    label: "\(phase.rawValue.capitalized) W\(weekInPhase + 1)"
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
    private func buildSessions(
        days: [Int],
        exercises: [PlanExercise],
        sets: Int,
        targetReps: Int,
        intensity: Double,
        restSeconds: Int,
        dupSessionType: DUPSessionType?,
        label: String
    ) -> [PlannedSession] {
        days.enumerated().map { dayIndex, day in
            let dayName = Self.dayNames[day] ?? "Day \(dayIndex + 1)"
            let sessionLabel = days.count > 1 ? "\(label) - \(dayName)" : label

            let exerciseSets = exercises.map { exercise in
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
                    exerciseCount: exercises.count,
                    sets: sets,
                    restSeconds: restSeconds
                )
            )
        }
    }

    // MARK: - Block Phase Parameters

    private struct PhaseParams {
        let intensity: Double
        let sets: Int
        let reps: Int
    }

    private func blockPhaseParams(_ phase: BlockPhase, weekInPhase: Int, totalPhaseWeeks: Int) -> PhaseParams {
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
            // 50% intensity, low volume
            return PhaseParams(intensity: 0.50, sets: 2, reps: 10)
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
