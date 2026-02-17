import Foundation

/// Detects progress plateaus using statistical analysis.
/// - Sliding window volume analysis
/// - Coefficient of variation (CV) for stagnation detection
@MainActor
public final class PlateauDetectionService: Sendable {

    private let minWeeksForAnalysis = 4
    private let plateauThresholdCV = 0.10
    private let minImprovementThreshold = 1.05

    public init() {}

    /// Analyze plateaus across all exercises
    /// - Parameters:
    ///   - workouts: All user workouts
    ///   - windowWeeks: Number of weeks to analyze (default 4)
    ///   - stallThreshold: CV threshold below which a plateau is detected (default 0.05)
    /// - Returns: Array of plateau analyses sorted by weeks stalled descending
    public func analyzePlateaus(
        workouts: [Workout],
        windowWeeks: Int = 4,
        stallThreshold: Double = 0.05
    ) -> [PlateauAnalysis] {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -max(windowWeeks, minWeeksForAnalysis), to: Date())!

        let recentWorkouts = workouts.filter {
            guard let completedAt = $0.completedAt else { return false }
            return completedAt >= windowStart
        }

        guard recentWorkouts.count >= minWeeksForAnalysis else {
            return []
        }

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
                stallThreshold: stallThreshold
            )
            analyses.append(analysis)
        }

        return analyses.sorted { $0.consecutiveWeeksStalled > $1.consecutiveWeeksStalled }
    }

    // MARK: - Private

    private func analyzeExercisePlateau(
        exerciseId: UUID,
        exerciseName: String,
        workoutExercises: [(Workout, WorkoutExercise)],
        stallThreshold: Double
    ) -> PlateauAnalysis {
        let sorted = workoutExercises.sorted { $0.0.startedAt < $1.0.startedAt }

        // Calculate weekly volumes
        let weeklyVolumes = grouped(sorted, byWeeks: 1).map { group in
            group.reduce(0.0) { $0 + $1.1.exerciseVolume }
        }

        guard !weeklyVolumes.isEmpty else {
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

        let avgVolume = weeklyVolumes.reduce(0, +) / Double(weeklyVolumes.count)
        let stdDev = calculateStdDev(weeklyVolumes, mean: avgVolume)
        let cv = avgVolume > 0 ? stdDev / avgVolume : 0

        // Detect consecutive weeks without improvement
        var weeksStalled = 0
        var lastImprovement: Date?

        for i in 1..<weeklyVolumes.count {
            if weeklyVolumes[i] >= weeklyVolumes[i - 1] * minImprovementThreshold {
                lastImprovement = sorted[min(i * (sorted.count / weeklyVolumes.count), sorted.count - 1)].0.startedAt
                weeksStalled = 0
            } else {
                weeksStalled += 1
            }
        }

        let thresholdToUse = stallThreshold > 0 ? stallThreshold : plateauThresholdCV
        let plateauDetected = cv < thresholdToUse && weeksStalled >= 2

        return PlateauAnalysis(
            id: UUID(),
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            detectedAt: Date(),
            consecutiveWeeksStalled: weeksStalled,
            volumeCoefficient: avgVolume > 0 ? cv : 0,
            lastProgressDate: lastImprovement
        )
    }

    private func grouped(
        _ items: [(Workout, WorkoutExercise)],
        byWeeks weeks: Int
    ) -> [[(Workout, WorkoutExercise)]] {
        let calendar = Calendar.current
        var groups: [Date: [(Workout, WorkoutExercise)]] = [:]

        for item in items {
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: item.0.startedAt) else { continue }
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
