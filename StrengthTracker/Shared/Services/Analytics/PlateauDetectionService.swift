import Foundation

/// Detects progress plateaus using e1RM progression analysis.
/// - Max e1RM per exercise per week as progression signal (not raw volume)
/// - Dynamic thresholds based on training status
/// - CV for stagnation detection
@MainActor
public final class PlateauDetectionService: Sendable {

    private let minWeeksForAnalysis = 4
    private let plateauThresholdCV = 0.10

    public init() {}

    /// Dynamic improvement threshold based on training status.
    /// Beginners can improve faster; advanced lifters maintain.
    private func thresholdForStatus(_ status: TrainingStatus) -> Double {
        switch status {
        case .beginner:     return 1.05  // 5% week-over-week
        case .intermediate: return 1.02  // 2%
        case .advanced:     return 1.00  // Just maintain
        }
    }

    /// Analyze plateaus across all exercises
    /// - Parameters:
    ///   - workouts: All user workouts
    ///   - trainingStatus: Current training status for dynamic thresholds
    ///   - windowWeeks: Number of weeks to analyze (default 4)
    ///   - stallThreshold: CV threshold below which a plateau is detected (default 0.05)
    /// - Returns: Array of plateau analyses sorted by weeks stalled descending
    public func analyzePlateaus(
        workouts: [Workout],
        trainingStatus: TrainingStatus = .intermediate,
        windowWeeks: Int = 4,
        stallThreshold: Double = 0.05
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
                exerciseId: exerciseId,
                exerciseName: workoutExercises[0].1.exercise.name,
                workoutExercises: workoutExercises,
                stallThreshold: stallThreshold,
                improvementThreshold: improvementThreshold
            )
            if analysis.consecutiveWeeksStalled >= 2 {
                analyses.append(analysis)
            }
        }

        return analyses.sorted { $0.consecutiveWeeksStalled > $1.consecutiveWeeksStalled }
    }

    // MARK: - Private

    private func analyzeExercisePlateau(
        exerciseId: UUID,
        exerciseName: String,
        workoutExercises: [(Workout, WorkoutExercise)],
        stallThreshold: Double,
        improvementThreshold: Double
    ) -> PlateauAnalysis {
        let sorted = workoutExercises.sorted { $0.0.startedAt < $1.0.startedAt }

        // Use max e1RM per week as progression signal (not raw volume)
        let weeklyBestE1RM = grouped(sorted, byWeeks: 1).map { group -> Double in
            group.compactMap { (_, workoutExercise) -> Double? in
                workoutExercise.sets
                    .filter { $0.isCompleted && $0.setType != .warmup }
                    .compactMap { set -> Double? in
                        guard let weight = set.weight, weight > 0,
                              let reps = set.reps, reps > 0, reps <= 15 else { return nil }
                        return AnalyticsCalculations.calculateOneRM(weight: weight, reps: reps)
                    }
                    .max()
            }.compactMap { $0 }.max() ?? 0.0
        }

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

        // Detect consecutive weeks without improvement
        var weeksStalled = 0
        var lastImprovement: Date?

        for i in 1..<weeklyBestE1RM.count {
            guard weeklyBestE1RM[i] > 0, weeklyBestE1RM[i - 1] > 0 else { continue }
            if weeklyBestE1RM[i] >= weeklyBestE1RM[i - 1] * improvementThreshold {
                lastImprovement = sorted[min(i * (sorted.count / weeklyBestE1RM.count), sorted.count - 1)].0.startedAt
                weeksStalled = 0
            } else {
                weeksStalled += 1
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
    ) -> [[(Workout, WorkoutExercise)]] {
        let calendar = Calendar.mondayStart
        var groups: [Date: [(Workout, WorkoutExercise)]] = [:]

        for item in items {
            let date = item.0.completedAt ?? item.0.startedAt
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else { continue }
            groups[weekInterval.start, default: []].append(item)
        }

        return groups.values.sorted { group1, group2 in
            guard let first1 = group1.first, let first2 = group2.first else { return false }
            return first1.0.startedAt < first2.0.startedAt
        }
    }

    func calculateStdDev(_ values: [Double], mean: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}
