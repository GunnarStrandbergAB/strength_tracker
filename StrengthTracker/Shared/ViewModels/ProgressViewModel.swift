import Foundation
import Observation

@MainActor
@Observable
public final class ProgressViewModel {
    public var selectedExercise: Exercise? = nil
    public var exercises: [Exercise] = []
    public var progressionData: [(date: Date, weight: Double, reps: Int)] = []
    public var isLoading = false
    public private(set) var completedHistory: [Workout] = []
    public private(set) var errorMessage: String?
    public var resolvedBodyWeightKg: Double { bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg }

    public var bestWeight: Double? {
        progressionData.map(\.weight).max()
    }

    public var bestReps: Int? {
        progressionData.map(\.reps).max()
    }

    public var estimated1RM: Double? {
        progressionData
            .map { AnalyticsCalculations.calculateOneRM(weight: $0.weight, reps: min($0.reps, 15)) }
            .max()
    }

    /// Effective-load volume of every completed working set of the exercise, all time
    /// (same definition as Workout.totalVolume). Computed in loadProgression.
    public private(set) var totalVolume: Double = 0

    private let exerciseRepository: any ExerciseRepository
    private let workoutRepository: any WorkoutRepository
    public let userPreferencesService: UserPreferencesService?
    private let bodyWeightProvider: BodyWeightProvider?

    public var weightUnit: WeightUnit { userPreferencesService?.weightUnit ?? .kg }

    public init(
        exerciseRepository: any ExerciseRepository,
        workoutRepository: any WorkoutRepository,
        userPreferencesService: UserPreferencesService? = nil,
        bodyWeightProvider: BodyWeightProvider? = nil
    ) {
        self.exerciseRepository = exerciseRepository
        self.workoutRepository = workoutRepository
        self.userPreferencesService = userPreferencesService
        self.bodyWeightProvider = bodyWeightProvider
    }

    public func loadExercises() async {
        isLoading = true
        do {
            exercises = try await exerciseRepository.fetchAll()
        } catch {
            exercises = []
        }
        isLoading = false
    }

    public func loadProgression(for exerciseId: UUID) async {
        isLoading = true
        do {
            let allWorkouts = try await workoutRepository.fetchAll()
            let completed = allWorkouts.filter { $0.completedAt != nil }
            completedHistory = completed
            errorMessage = nil
            var results: [(date: Date, weight: Double, reps: Int)] = []
            var volume: Double = 0

            let bodyWeightKg = bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
            for workout in completed {
                for workoutExercise in workout.exercises {
                    if workoutExercise.exercise.id == exerciseId {
                        let baseLoad = workoutExercise.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)
                        // Working sets only: warm-ups are not performance data.
                        for set in workoutExercise.sets where set.isCompleted && set.setType != .warmup {
                            volume += set.setVolume(baseLoadPerRep: baseLoad)
                            // One point per performed segment so drop-set parts feed
                            // best-weight/best-reps/e1RM like any other effort.
                            for part in set.effectiveLoadParts(baseLoadPerRep: baseLoad) {
                                results.append((date: workout.trainingDate, weight: part.load, reps: part.reps))
                            }
                        }
                    }
                }
            }

            progressionData = results.sorted { $0.date < $1.date }
            totalVolume = volume
        } catch {
            progressionData = []
            completedHistory = []
            totalVolume = 0
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

}

// MARK: - Shared, presentation-only history calculations

public enum HistoryPeriod: String, CaseIterable, Sendable {
    case fourWeeks = "4W", threeMonths = "3M", sixMonths = "6M", year = "1Y", all = "All", yearToDate = "YTD", custom = "Custom"

    public func interval(now: Date, firstDate: Date?, customStart: Date, customEnd: Date, calendar: Calendar = .current) -> DateInterval {
        let start: Date
        var end = now
        switch self {
        case .fourWeeks: start = calendar.date(byAdding: .day, value: -28, to: now)!
        case .threeMonths: start = calendar.date(byAdding: .month, value: -3, to: now)!
        case .sixMonths: start = calendar.date(byAdding: .month, value: -6, to: now)!
        case .year: start = calendar.date(byAdding: .year, value: -1, to: now)!
        case .all: start = min(firstDate ?? now, now)
        case .yearToDate: start = calendar.dateInterval(of: .year, for: now)!.start
        case .custom:
            start = min(calendar.startOfDay(for: customStart), now)
            end = min(now, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customStart, customEnd)))!.addingTimeInterval(-0.001))
        }
        return DateInterval(start: start, end: max(start, end))
    }
}

public enum ExerciseHistoryMetric: String, CaseIterable, Sendable {
    case strength = "Estimated strength", weightAtReps = "Weight at reps", repsAtWeight = "Reps at weight"
    case volume = "Session volume", sets = "Working sets", duration = "Duration", distance = "Distance"
    public var isPerformance: Bool { self == .strength || self == .weightAtReps || self == .repsAtWeight }
    public var usesWeight: Bool { self == .strength || self == .weightAtReps || self == .volume }
    public static func available(for type: ExerciseType) -> [Self] {
        switch type {
        case .weightedReps, .bodyweightReps: return [.strength, .weightAtReps, .repsAtWeight, .volume, .sets]
        case .duration: return [.duration, .sets]
        case .distance: return [.distance, .duration, .sets]
        case .cardio, .weightedCardio: return [.duration, .distance, .sets]
        }
    }
}

public struct ExerciseHistorySession: Identifiable, Sendable {
    public var id: UUID { workout.id }
    public var date: Date { workout.trainingDate }
    public let workout: Workout
    public let sets: [ExerciseSet]
    public let baseLoad: Double?
    public var loadParts: [(load: Double, reps: Int)] {
        sets.flatMap(\.effectiveParts).compactMap { part in
            guard let load = part.effectiveLoad(baseLoadPerRep: baseLoad), load.isFinite, load >= 0,
                  let reps = part.reps, reps > 0 else { return nil }
            return (load: load, reps: reps)
        }
    }
    public var recordedVolume: Double { loadParts.reduce(0) { $0 + $1.load * Double($1.reps) } }
    public var recordedReps: Int { loadParts.reduce(0) { $0 + $1.reps } }
    /// Only complete sets contribute to per-set averages; a partially recorded drop set is not a complete set.
    public var completeLoadSets: [ExerciseSet] {
        sets.filter { set in set.effectiveParts.allSatisfy { part in
            guard let reps = part.reps, reps > 0, let load = part.effectiveLoad(baseLoadPerRep: baseLoad) else { return false }
            return load.isFinite && load >= 0
        } }
    }
    public func value(for metric: ExerciseHistoryMetric, targetReps: Int = 5, targetWeightKg: Double = 0) -> Double? {
        switch metric {
        case .strength:
            return loadParts.filter { $0.load > 0 }.map { AnalyticsCalculations.calculateOneRM(weight: $0.load, reps: min($0.reps, 15)) }.max()
        case .weightAtReps: return loadParts.filter { $0.reps == targetReps }.map(\.load).max()
        case .repsAtWeight: return loadParts.filter { abs($0.load - targetWeightKg) < 0.000001 }.map { Double($0.reps) }.max()
        case .volume: return loadParts.isEmpty ? nil : recordedVolume
        case .sets: return Double(sets.count)
        case .duration:
            let values = sets.compactMap(\.durationSeconds).filter { $0 > 0 }
            return values.isEmpty ? nil : Double(values.reduce(0, +))
        case .distance:
            let values = sets.compactMap(\.distanceMeters).filter { $0.isFinite && $0 > 0 }
            return values.isEmpty ? nil : values.reduce(0, +)
        }
    }
}

public struct HistoryPoint: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let value: Double
    public let isDeload: Bool
    public let segment: Int
    public var median: Double?
}

public enum ExerciseHistoryCalculator {
    public static func sessions(exerciseId: UUID, workouts: [Workout], bodyWeightKg: Double, now: Date = Date()) -> [ExerciseHistorySession] {
        workouts.filter { $0.completedAt != nil && $0.trainingDate <= now }.sorted {
            $0.trainingDate == $1.trainingDate ? $0.id.uuidString < $1.id.uuidString : $0.trainingDate < $1.trainingDate
        }.compactMap { workout in
            let entries = workout.exercises.filter { $0.exercise.id == exerciseId }
            let sets = entries.flatMap(\.sets).filter { $0.isCompleted && $0.setType != .warmup }
            guard let exercise = entries.first?.exercise, !sets.isEmpty else { return nil }
            return ExerciseHistorySession(workout: workout, sets: sets, baseLoad: exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg))
        }
    }

    public static func points(sessions: [ExerciseHistorySession], metric: ExerciseHistoryMetric, targetReps: Int = 5, targetWeightKg: Double = 0) -> [HistoryPoint] {
        var result: [HistoryPoint] = [], recent: [Double] = []
        var last: Date?, segment = 0
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            guard let value = session.value(for: metric, targetReps: targetReps, targetWeightKg: targetWeightKg), value.isFinite else { continue }
            if let last, session.date.timeIntervalSince(last) > 21 * 86400 { segment += 1; recent = [] }
            let excluded = metric.isPerformance && session.workout.isDeload
            if !excluded { recent.append(value); recent = Array(recent.suffix(3)); last = session.date }
            result.append(HistoryPoint(id: session.id, date: session.date, value: value, isDeload: session.workout.isDeload,
                segment: segment, median: !excluded && recent.count == 3 ? recent.sorted()[1] : nil))
        }
        return result
    }

    /// Descriptive endpoint change, deliberately independent of the coaching classification.
    public static func performanceChange(points: [HistoryPoint], interval: DateInterval) -> Double? {
        let eligible = points.filter { !$0.isDeload && $0.date >= interval.start && $0.date <= interval.end }.sorted { $0.date < $1.date }
        guard eligible.count >= 6 else { return nil }
        let first = Array(eligible.prefix(3)), last = Array(eligible.suffix(3))
        guard first.last!.date <= interval.start.addingTimeInterval(interval.duration / 4),
              last.first!.date >= interval.end.addingTimeInterval(-interval.duration / 4) else { return nil }
        let startValue = first.map(\.value).sorted()[1], endValue = last.map(\.value).sorted()[1]
        guard startValue > 0 else { return nil }
        return (endValue / startValue - 1) * 100
    }

    public static func activityChange(points: [HistoryPoint], interval: DateInterval, firstLoggedDate: Date?) -> Double? {
        guard interval.duration > 0, let firstLoggedDate,
              firstLoggedDate <= interval.start.addingTimeInterval(-interval.duration) else { return nil }
        let previous = points.filter { $0.date >= interval.start.addingTimeInterval(-interval.duration) && $0.date < interval.start }.reduce(0) { $0 + $1.value }
        let current = points.filter { $0.date >= interval.start && $0.date <= interval.end }.reduce(0) { $0 + $1.value }
        guard previous > 0 else { return nil }
        return (current / previous - 1) * 100
    }
}

/// Stable device-local presentation preferences. No analytics or workout data is modified.
public enum ExerciseHistoryPreferences {
    public static let pinsKey = "analytics.history.pinnedExercises"
    public static func pins(from value: String) -> [UUID] {
        var seen = Set<UUID>()
        return Array(value.split(separator: ",").compactMap { UUID(uuidString: String($0)) }.filter { seen.insert($0).inserted }.prefix(4))
    }
    public static func toggling(_ id: UUID, in value: String) -> String {
        var ids = pins(from: value)
        if ids.contains(id) { ids.removeAll { $0 == id } } else if ids.count < 4 { ids.append(id) }
        return ids.map(\.uuidString).joined(separator: ",")
    }
    public static func metricKey(_ id: UUID) -> String { "analytics.history.metric.\(id.uuidString)" }
}

public struct MuscleHistoryWeek: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public var direct: Double = 0
    public var indirect: Double = 0
}

public enum MuscleHistoryCalculator {
    public static func weeks(workouts: [Workout], muscle: MuscleGroup, interval: DateInterval) -> [MuscleHistoryWeek] {
        let calendar = Calendar.mondayStart
        var byWeek: [Date: MuscleHistoryWeek] = [:]
        var week = calendar.dateInterval(of: .weekOfYear, for: interval.start)!.start
        while week <= interval.end {
            byWeek[week] = MuscleHistoryWeek(date: week)
            week = calendar.date(byAdding: .weekOfYear, value: 1, to: week)!
        }
        for workout in workouts where workout.completedAt != nil && workout.trainingDate >= interval.start && workout.trainingDate <= interval.end {
            let date = calendar.dateInterval(of: .weekOfYear, for: workout.trainingDate)!.start
            for entry in workout.exercises {
                let count = entry.sets.filter { $0.isCompleted && $0.setType != .warmup }.count
                if entry.exercise.primaryMuscleGroup == muscle { byWeek[date]?.direct += Double(count) }
                if entry.exercise.secondaryMuscleGroups.contains(muscle) {
                    let credits = AnalyticsCalculations.attributeHardSetCredits(hardSets: count, primaryMuscle: entry.exercise.primaryMuscleGroup, secondaryMuscles: entry.exercise.secondaryMuscleGroups)
                    byWeek[date]?.indirect += credits[muscle] ?? 0
                }
            }
        }
        return byWeek.values.sorted { $0.date < $1.date }
    }
}
