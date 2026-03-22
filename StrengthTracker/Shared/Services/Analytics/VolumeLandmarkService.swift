import Foundation

/// Computes optimal weekly set volume ranges per muscle group.
/// Uses population defaults adjusted by training status.
@MainActor
public final class VolumeLandmarkService: Sendable {

    private let workoutRepository: any WorkoutRepository
    private let trainingStatusDetector: TrainingStatusDetector

    public init(
        workoutRepository: any WorkoutRepository,
        trainingStatusDetector: TrainingStatusDetector
    ) {
        self.workoutRepository = workoutRepository
        self.trainingStatusDetector = trainingStatusDetector
    }

    /// Compute volume landmarks for all trained muscle groups in the last 4 weeks.
    public func computeVolumeLandmarks() async throws -> [OptimalVolumeRange] {
        let allWorkouts = try await workoutRepository.fetchAll()
        let fourWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date())!
        let recentWorkouts = allWorkouts.filter {
            $0.completedAt != nil && ($0.completedAt ?? $0.startedAt) >= fourWeeksAgo
        }

        guard !recentWorkouts.isEmpty else { return [] }

        let trainingStatus = try await trainingStatusDetector.detect()
        let weeklySetCounts = countWeeklyHardSets(workouts: recentWorkouts)

        return weeklySetCounts.map { muscleGroup, avgWeeklySets in
            let (mev, mrv) = adjustedRange(for: muscleGroup, trainingStatus: trainingStatus)
            let status: VolumeStatus
            if avgWeeklySets < mev {
                status = .underVolume
            } else if avgWeeklySets > mrv {
                status = .overVolume
            } else {
                status = .optimal
            }
            return OptimalVolumeRange(
                muscleGroup: muscleGroup,
                minimumWeeklySets: mev,
                maximumWeeklySets: mrv,
                currentWeeklySets: avgWeeklySets,
                volumeStatus: status
            )
        }
        .sorted { $0.muscleGroup < $1.muscleGroup }
    }

    // MARK: - Private

    /// Count hard sets per muscle group per week, averaging over the 4-week window.
    /// Primary muscles get 1.0 credit, secondary get 0.5.
    private func countWeeklyHardSets(workouts: [Workout]) -> [String: Int] {
        var totalCredits: [String: Double] = [:]
        for workout in workouts {
            for we in workout.exercises {
                let hardSets = we.sets.filter { $0.isCompleted && $0.setType != .warmup }.count
                guard hardSets > 0 else { continue }

                let primary = we.exercise.primaryMuscleGroup.rawValue
                totalCredits[primary, default: 0] += Double(hardSets)

                let secondaryCount = max(we.exercise.secondaryMuscleGroups.count, 1)
                let secondaryCreditPerMuscle = Double(hardSets) * 0.5 / Double(secondaryCount)
                for secondary in we.exercise.secondaryMuscleGroups {
                    totalCredits[secondary.rawValue, default: 0] += secondaryCreditPerMuscle
                }
            }
        }

        // Average over 4 weeks
        return totalCredits.mapValues { Int(($0 / 4.0).rounded()) }
    }

    // MARK: - Population Defaults (MEV/MRV)

    private static let defaults: [String: (mev: Int, mrv: Int)] = [
        "chest": (8, 22),
        "back": (8, 25),
        "shoulders": (6, 20),
        "quadriceps": (6, 22),
        "hamstrings": (4, 16),
        "glutes": (4, 16),
        "biceps": (4, 18),
        "triceps": (4, 18),
        "calves": (6, 16),
        "core": (4, 16),
        "lats": (6, 22),
        "traps": (4, 16),
        "forearms": (2, 12),
        "lowerBack": (2, 10),
    ]

    private func adjustedRange(for muscleGroup: String, trainingStatus: TrainingStatus) -> (mev: Int, mrv: Int) {
        let base = Self.defaults[muscleGroup] ?? (6, 18)
        switch trainingStatus {
        case .beginner:
            return (max(base.mev - 2, 2), max(base.mrv - 4, base.mev))
        case .intermediate:
            return base
        case .advanced:
            return (base.mev + 2, base.mrv + 4)
        }
    }
}
