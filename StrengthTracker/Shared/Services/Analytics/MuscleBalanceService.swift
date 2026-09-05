import Foundation

/// Analyzes muscle group balance and identifies volume imbalances.
/// Stateless service -- all data passed as parameters.
@MainActor
public final class MuscleBalanceService: Sendable {

    // Antagonist pairs for balance analysis
    private let antagonistPairs: [(MuscleGroup, MuscleGroup)] = [
        (.chest, .back),
        (.quadriceps, .hamstrings),
        (.biceps, .triceps),
        (.shoulders, .lats),
        (.core, .lowerBack),
        (.glutes, .hipFlexors)
    ]

    private let mildImbalanceThreshold = 1.5
    private let moderateImbalanceThreshold = 2.0

    public init() {}

    /// Analyze muscle balance from workout history
    /// - Parameters:
    ///   - workouts: All user workouts
    ///   - windowWeeks: Number of weeks to analyze (default 4)
    /// - Returns: MuscleBalance analysis with volumes, percentages, imbalances, and overall score
    public func analyzeBalance(
        workouts: [Workout],
        windowWeeks: Int = 4,
        bodyWeightKg: Double = UserPreferencesService.defaultBodyWeightKg
    ) -> MuscleBalance {
        let calendar = Calendar.mondayStart
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -windowWeeks, to: Date())!

        let recentWorkouts = workouts.filter {
            guard let completedAt = $0.completedAt else { return false }
            return completedAt >= windowStart
        }

        // Calculate total volume per muscle group (bodyweight-aware)
        var muscleVolumes: [MuscleGroup: Double] = [:]

        for workout in recentWorkouts {
            for exercise in workout.exercises {
                let volume = exercise.exerciseVolume(bodyWeightKg: bodyWeightKg)

                let attributed = AnalyticsCalculations.attributeVolume(
                    volume: volume,
                    primaryMuscle: exercise.exercise.primaryMuscleGroup,
                    secondaryMuscles: exercise.exercise.secondaryMuscleGroups
                )
                for (muscle, vol) in attributed {
                    muscleVolumes[muscle, default: 0] += vol
                }
            }
        }

        // If total volume is zero, return a zero score rather than misleading perfect score
        let totalVol = muscleVolumes.values.reduce(0, +)
        guard totalVol > 0 else {
            return MuscleBalance(
                analyzedAt: Date(),
                muscleGroupVolumes: [],
                imbalances: [],
                overallBalanceScore: 0
            )
        }

        // Count sets per muscle group
        var muscleSets: [MuscleGroup: Int] = [:]
        for workout in recentWorkouts {
            for exercise in workout.exercises {
                let completedSets = exercise.sets.filter { $0.isCompleted && $0.setType != .warmup }.count
                muscleSets[exercise.exercise.primaryMuscleGroup, default: 0] += completedSets
            }
        }

        // Build MuscleGroupVolume array
        let groupVolumes: [MuscleGroupVolume] = muscleVolumes.map { group, volume in
            MuscleGroupVolume(
                muscleGroup: group.rawValue,
                weeklyVolume: volume,
                weeklySetCount: muscleSets[group] ?? 0,
                trend: .stable
            )
        }

        // Identify imbalances
        let imbalances = identifyImbalances(muscleVolumes: muscleVolumes)

        // Calculate overall balance score
        let overallScore = calculateBalanceScore(imbalances: imbalances)

        return MuscleBalance(
            analyzedAt: Date(),
            muscleGroupVolumes: groupVolumes,
            imbalances: imbalances,
            overallBalanceScore: overallScore
        )
    }

    /// Overload matching architecture doc's `analyze(workouts:timeWindow:)` signature
    public func analyze(workouts: [Workout], timeWindow: TimeInterval, bodyWeightKg: Double = UserPreferencesService.defaultBodyWeightKg) -> MuscleBalance {
        let windowWeeks = max(1, Int(timeWindow / (7 * 24 * 3600)))
        return analyzeBalance(workouts: workouts, windowWeeks: windowWeeks, bodyWeightKg: bodyWeightKg)
    }

    // MARK: - Private

    private func identifyImbalances(muscleVolumes: [MuscleGroup: Double]) -> [MuscleImbalance] {
        var imbalances: [MuscleImbalance] = []

        for (primary, comparison) in antagonistPairs {
            let primaryVol = muscleVolumes[primary] ?? 0
            let comparisonVol = muscleVolumes[comparison] ?? 0

            guard primaryVol > 0, comparisonVol > 0 else { continue }

            let ratio = primaryVol / comparisonVol
            if ratio >= mildImbalanceThreshold {
                let severity: ImbalanceSeverity = ratio >= moderateImbalanceThreshold ? .severe : .moderate
                imbalances.append(MuscleImbalance(
                    id: UUID(),
                    primaryGroup: primary.rawValue,
                    comparisonGroup: comparison.rawValue,
                    ratio: ratio,
                    severity: severity
                ))
            }

            // Check reverse
            let reverseRatio = comparisonVol / primaryVol
            if reverseRatio >= mildImbalanceThreshold {
                let severity: ImbalanceSeverity = reverseRatio >= moderateImbalanceThreshold ? .severe : .moderate
                imbalances.append(MuscleImbalance(
                    id: UUID(),
                    primaryGroup: comparison.rawValue,
                    comparisonGroup: primary.rawValue,
                    ratio: reverseRatio,
                    severity: severity
                ))
            }
        }

        return imbalances
    }

    private func calculateBalanceScore(imbalances: [MuscleImbalance]) -> Double {
        if imbalances.isEmpty {
            return 1.0
        }

        let severityPenalties: [ImbalanceSeverity: Double] = [
            .mild: 0.05,
            .moderate: 0.15,
            .severe: 0.30
        ]

        let totalPenalty = imbalances.reduce(0.0) { total, imbalance in
            total + (severityPenalties[imbalance.severity] ?? 0)
        }

        return max(0.0, 1.0 - totalPenalty)
    }
}
