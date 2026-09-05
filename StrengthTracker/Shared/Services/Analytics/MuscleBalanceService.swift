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

    /// Antagonist ratio tiers: mild ≥1.25, moderate ≥1.5, severe ≥2.0.
    private let mildImbalanceThreshold = 1.25
    private let moderateImbalanceThreshold = 1.5
    private let severeImbalanceThreshold = 2.0
    /// A group's volume must move ≥10% window-over-window to count as a trend.
    private let trendTolerance = 0.10

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
        let now = Date()
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -windowWeeks, to: now)!
        let previousWindowStart = calendar.date(byAdding: .weekOfYear, value: -windowWeeks, to: windowStart)!

        let completed = workouts.filter { $0.completedAt != nil }
        let recentWorkouts = completed.filter { $0.trainingDate >= windowStart }
        let previousWorkouts = completed.filter { $0.trainingDate >= previousWindowStart && $0.trainingDate < windowStart }

        // Total volume per muscle group (bodyweight-aware), this window and the one before
        let muscleVolumes = attributedVolumes(for: recentWorkouts, bodyWeightKg: bodyWeightKg)
        let previousVolumes = attributedVolumes(for: previousWorkouts, bodyWeightKg: bodyWeightKg)

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
                trend: trend(current: volume, previous: previousVolumes[group])
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

    private func attributedVolumes(for workouts: [Workout], bodyWeightKg: Double) -> [MuscleGroup: Double] {
        var volumes: [MuscleGroup: Double] = [:]
        for workout in workouts {
            for exercise in workout.exercises {
                let volume = exercise.exerciseVolume(bodyWeightKg: bodyWeightKg)
                let attributed = AnalyticsCalculations.attributeVolume(
                    volume: volume,
                    primaryMuscle: exercise.exercise.primaryMuscleGroup,
                    secondaryMuscles: exercise.exercise.secondaryMuscleGroups
                )
                for (muscle, vol) in attributed {
                    volumes[muscle, default: 0] += vol
                }
            }
        }
        return volumes
    }

    /// Window-over-window direction; no previous data means no trend claim.
    private func trend(current: Double, previous: Double?) -> VolumeTrend {
        guard let previous, previous > 0 else { return .stable }
        let change = (current - previous) / previous
        if change >= trendTolerance { return .increasing }
        if change <= -trendTolerance { return .decreasing }
        return .stable
    }

    private func severity(for ratio: Double) -> ImbalanceSeverity {
        if ratio >= severeImbalanceThreshold { return .severe }
        if ratio >= moderateImbalanceThreshold { return .moderate }
        return .mild
    }

    private func identifyImbalances(muscleVolumes: [MuscleGroup: Double]) -> [MuscleImbalance] {
        var imbalances: [MuscleImbalance] = []

        for (primary, comparison) in antagonistPairs {
            let primaryVol = muscleVolumes[primary] ?? 0
            let comparisonVol = muscleVolumes[comparison] ?? 0

            guard primaryVol > 0, comparisonVol > 0 else { continue }

            let ratio = primaryVol / comparisonVol
            if ratio >= mildImbalanceThreshold {
                imbalances.append(MuscleImbalance(
                    id: UUID(),
                    primaryGroup: primary.rawValue,
                    comparisonGroup: comparison.rawValue,
                    ratio: ratio,
                    severity: severity(for: ratio)
                ))
            }

            // Check reverse
            let reverseRatio = comparisonVol / primaryVol
            if reverseRatio >= mildImbalanceThreshold {
                imbalances.append(MuscleImbalance(
                    id: UUID(),
                    primaryGroup: comparison.rawValue,
                    comparisonGroup: primary.rawValue,
                    ratio: reverseRatio,
                    severity: severity(for: reverseRatio)
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
