import Foundation

/// Detects progress plateaus using e1RM progression analysis.
/// - Max e1RM per exercise per week as progression signal (not raw volume)
/// - Dynamic thresholds based on training status
@MainActor
public final class PlateauDetectionService: Sendable {

    private let minWeeksForAnalysis = 4

    public init() {}

    /// Dynamic improvement threshold based on training status.
    /// Beginners can improve faster; advanced lifters maintain.
    /// The stall counter resets only on STRICT improvement above the threshold —
    /// a flat week is by definition a plateau week, not progress.
    private func thresholdForStatus(_ status: TrainingStatus) -> Double {
        switch status {
        case .beginner:     return 1.02  // needs >2% week-over-week
        case .intermediate: return 1.00  // needs any improvement; flat = stalled
        case .advanced:     return 0.98  // tolerates 2% fluctuation as non-stall
        }
    }

    /// Analyze plateaus across all exercises
    /// - Parameters:
    ///   - workouts: All user workouts
    ///   - trainingStatus: Current training status for dynamic thresholds
    ///   - windowWeeks: Number of weeks to analyze (default 4)
    /// - Returns: Array of plateau analyses sorted by weeks stalled descending
    public func analyzePlateaus(
        bodyWeightKg: Double,
        workouts: [Workout],
        trainingStatus: TrainingStatus = .intermediate,
        windowWeeks: Int = 4
    ) -> [PlateauAnalysis] {
        let calendar = Calendar.mondayStart
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -max(windowWeeks, minWeeksForAnalysis), to: Date())!

        let recentWorkouts = workouts.filter {
            guard let completedAt = $0.completedAt else { return false }
            return completedAt >= windowStart
        }

        guard recentWorkouts.count >= minWeeksForAnalysis else {
            return []
        }

        let improvementThreshold = thresholdForStatus(trainingStatus)
        var analyses: [PlateauAnalysis] = []

        // Group by exercise across all workouts
        let exerciseGroups = Dictionary(grouping: recentWorkouts.flatMap { workout in
            workout.exercises.map { (workout, $0) }
        }) { $0.1.exercise.id }

        for (exerciseId, workoutExercises) in exerciseGroups {
            guard workoutExercises.count >= minWeeksForAnalysis else { continue }

            let analysis = analyzeExercisePlateau(
                bodyWeightKg: bodyWeightKg,
                exerciseId: exerciseId,
                exerciseName: workoutExercises[0].1.exercise.name,
                workoutExercises: workoutExercises,
                improvementThreshold: improvementThreshold
            )
            if analysis.consecutiveWeeksStalled >= 3 {
                analyses.append(analysis)
            }
        }

        return analyses.sorted { $0.consecutiveWeeksStalled > $1.consecutiveWeeksStalled }
    }

    // MARK: - Private

    private func analyzeExercisePlateau(
        bodyWeightKg: Double,
        exerciseId: UUID,
        exerciseName: String,
        workoutExercises: [(Workout, WorkoutExercise)],
        improvementThreshold: Double
    ) -> PlateauAnalysis {
        let sorted = workoutExercises.sorted { $0.0.startedAt < $1.0.startedAt }

        // Use max e1RM per week as progression signal (not raw volume).
        // Keep the week start so calendar gaps between trained weeks count as stalled time.
        let weeklySeries: [(weekStart: Date, bestE1RM: Double)] = grouped(sorted, byWeeks: 1)
            .map { weekStart, group in
                let best = group.compactMap { (_, workoutExercise) -> Double? in
                    let baseLoad = workoutExercise.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                    return AnalyticsCalculations.bestE1RM(in: workoutExercise.sets, baseLoadPerRep: baseLoad)
                }.max() ?? 0.0
                return (weekStart, best)
            }
        let weeklyBestE1RM = weeklySeries.map(\.bestE1RM)

        guard !weeklyBestE1RM.isEmpty, weeklyBestE1RM.contains(where: { $0 > 0 }) else {
            return PlateauAnalysis(
                id: UUID(),
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                detectedAt: Date(),
                consecutiveWeeksStalled: 0,
                volumeCoefficient: 0,
                lastProgressDate: nil
            )
        }

        let nonZero = weeklyBestE1RM.filter { $0 > 0 }
        let avgE1RM = nonZero.reduce(0, +) / Double(nonZero.count)
        let stdDev = calculateStdDev(nonZero, mean: avgE1RM)
        let cv = avgE1RM > 0 ? stdDev / avgE1RM : 0

        // Detect consecutive weeks without improvement.
        // Compare only trained weeks (bestE1RM > 0) pairwise, but count untrained
        // calendar weeks between them toward the stall — three skipped weeks
        // followed by a flat week is four weeks without progress, not one.
        // Note: OverloadTrackingService classifies trend by regression slope;
        // this counter measures stall *duration* on the same weekly-best-e1RM signal.
        let trainedWeeks = weeklySeries.filter { $0.bestE1RM > 0 }
        var weeksStalled = 0
        var lastImprovement: Date?
        let calendar = Calendar.mondayStart

        for i in 1..<trainedWeeks.count {
            let gapWeeks = calendar.dateComponents(
                [.weekOfYear],
                from: trainedWeeks[i - 1].weekStart,
                to: trainedWeeks[i].weekStart
            ).weekOfYear ?? 1
            if trainedWeeks[i].bestE1RM > trainedWeeks[i - 1].bestE1RM * improvementThreshold {
                lastImprovement = trainedWeeks[i].weekStart
                weeksStalled = 0
            } else {
                weeksStalled += max(gapWeeks, 1)
            }
        }

        return PlateauAnalysis(
            id: UUID(),
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            detectedAt: Date(),
            consecutiveWeeksStalled: weeksStalled,
            volumeCoefficient: avgE1RM > 0 ? cv : 0,
            lastProgressDate: lastImprovement
        )
    }

    private func grouped(
        _ items: [(Workout, WorkoutExercise)],
        byWeeks weeks: Int
    ) -> [(weekStart: Date, items: [(Workout, WorkoutExercise)])] {
        let calendar = Calendar.mondayStart
        var groups: [Date: [(Workout, WorkoutExercise)]] = [:]

        for item in items {
            let date = item.0.trainingDate
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else { continue }
            groups[weekInterval.start, default: []].append(item)
        }

        return groups
            .map { (weekStart: $0.key, items: $0.value) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    func calculateStdDev(_ values: [Double], mean: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}
