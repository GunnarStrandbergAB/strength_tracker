import Foundation

// MARK: - OneRMEstimate

/// Estimated one-rep max for an exercise, derived from workout history
public struct OneRMEstimate: Sendable, Equatable {
    public let value: Double
    public let source: OneRMWindow
    public let isStale: Bool

    public enum OneRMWindow: String, Sendable {
        case recent     // Last 6 months
        case extended   // 6-12 months (10% detraining penalty)
        case none       // No usable data
    }

    public init(value: Double, source: OneRMWindow, isStale: Bool) {
        self.value = value
        self.source = source
        self.isStale = isStale
    }
}

// MARK: - TrainingStatusDetector

/// Detects training status (beginner/intermediate/advanced) from workout history
/// and estimates one-rep max for individual exercises.
@MainActor
public final class TrainingStatusDetector: Sendable {
    private let workoutRepository: any WorkoutRepository

    public init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    // MARK: - Training Status Detection

    /// Classifies the user's training level based on their workout history.
    ///
    /// Classification logic:
    /// - **Advanced**: > 18 months training AND > 200 workouts AND >= 3.0 weekly frequency
    /// - **Intermediate**: (>= 3 months OR >= 50 workouts) AND >= 2.0 weekly frequency
    /// - **Beginner**: Everything else
    public func detect() async throws -> TrainingStatus {
        let allWorkouts = try await workoutRepository.fetchAll()
        let completed = allWorkouts.filter { $0.completedAt != nil }

        guard !completed.isEmpty else {
            return .beginner
        }

        let count = completed.count

        // m15: Sort by completedAt (per spec) to find the earliest completed workout
        let sorted = completed.sorted {
            ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt)
        }
        let firstWorkoutDate = sorted.first!.completedAt ?? sorted.first!.startedAt
        let now = Date()

        let monthsTraining = Calendar.current.dateComponents(
            [.month], from: firstWorkoutDate, to: now
        ).month ?? 0

        // Weekly frequency over the last 3 months
        let weeklyFrequency = calculateWeeklyFrequency(
            workouts: completed, referenceDate: now
        )

        // Advanced: > 18 months AND > 200 workouts AND >= 3.0 weekly frequency
        if monthsTraining > 18 && count > 200 && weeklyFrequency >= 3.0 {
            return .advanced
        }

        // Intermediate: (>= 3 months OR >= 50 workouts) AND >= 2.0 weekly frequency
        if (monthsTraining >= 3 || count >= 50) && weeklyFrequency >= 2.0 {
            return .intermediate
        }

        return .beginner
    }

    // MARK: - 1RM Estimation

    /// Estimates the one-rep max for a specific exercise based on workout history.
    ///
    /// - Parameter exerciseId: The UUID of the exercise to estimate.
    /// - Returns: An `OneRMEstimate` if usable data exists within 12 months, or `nil`.
    ///
    /// Data windows:
    /// - **Recent** (0-6 months): No penalty applied
    /// - **Extended** (6-12 months): 10% detraining penalty applied
    /// - **Beyond 12 months**: Data is ignored
    ///
    /// Only sets with reps <= 15 are considered. The Epley/Brzycki formulas are used.
    public func estimateOneRM(exerciseId: UUID) async throws -> OneRMEstimate? {
        let allWorkouts = try await workoutRepository.fetchAll()
        let completed = allWorkouts.filter { $0.completedAt != nil }
        let now = Date()

        let sixMonthsAgo = Calendar.current.date(
            byAdding: .month, value: -6, to: now
        )!
        let twelveMonthsAgo = Calendar.current.date(
            byAdding: .month, value: -12, to: now
        )!

        var bestRecentEstimate: Double?
        var bestExtendedEstimate: Double?

        for workout in completed {
            let workoutDate = workout.completedAt ?? workout.startedAt

            // Skip data older than 12 months
            guard workoutDate >= twelveMonthsAgo else { continue }

            let isRecent = workoutDate >= sixMonthsAgo

            for workoutExercise in workout.exercises {
                guard workoutExercise.exercise.id == exerciseId else { continue }

                for set in workoutExercise.sets {
                    guard set.isCompleted,
                          let weight = set.weight,
                          let reps = set.reps,
                          weight > 0,
                          reps > 0,
                          reps <= 15 else { continue }

                    let estimate = calculateOneRM(weight: weight, reps: reps)

                    if isRecent {
                        if let current = bestRecentEstimate {
                            bestRecentEstimate = max(current, estimate)
                        } else {
                            bestRecentEstimate = estimate
                        }
                    } else {
                        if let current = bestExtendedEstimate {
                            bestExtendedEstimate = max(current, estimate)
                        } else {
                            bestExtendedEstimate = estimate
                        }
                    }
                }
            }
        }

        // Prefer recent data over extended
        if let recent = bestRecentEstimate {
            let rounded = recent.rounded(toNearest: 2.5)
            return OneRMEstimate(value: rounded, source: .recent, isStale: false)
        }

        if let extended = bestExtendedEstimate {
            let penalized = extended * 0.90
            let rounded = penalized.rounded(toNearest: 2.5)
            return OneRMEstimate(value: rounded, source: .extended, isStale: true)
        }

        return nil
    }

    // MARK: - Private Helpers

    /// Calculates weekly workout frequency over the last 3 months.
    private func calculateWeeklyFrequency(
        workouts: [Workout], referenceDate: Date
    ) -> Double {
        let threeMonthsAgo = Calendar.current.date(
            byAdding: .month, value: -3, to: referenceDate
        )!

        let recentWorkouts = workouts.filter { workout in
            let date = workout.completedAt ?? workout.startedAt
            return date >= threeMonthsAgo
        }

        guard !recentWorkouts.isEmpty else { return 0.0 }

        // m16: Use Calendar for precise week count instead of hardcoded 13.0
        let weeksBetween = Calendar.current.dateComponents(
            [.weekOfYear], from: threeMonthsAgo, to: referenceDate
        ).weekOfYear ?? 13
        let weeks = max(1.0, Double(weeksBetween))
        return Double(recentWorkouts.count) / weeks
    }

    /// Estimates 1RM from a given weight and rep count.
    ///
    /// - reps == 1: weight itself
    /// - reps <= 5: Epley-style: weight * (1 + reps/30)
    /// - reps <= 15: Brzycki: weight * 36 / (37 - reps)
    private func calculateOneRM(weight: Double, reps: Int) -> Double {
        if reps == 1 {
            return weight
        } else if reps <= 5 {
            return weight * (1.0 + Double(reps) / 30.0)
        } else {
            // reps <= 15 (caller already filters out > 15)
            return weight * 36.0 / (37.0 - Double(reps))
        }
    }
}
