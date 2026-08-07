import Testing
import Foundation
@testable import StrengthTrackerShared

// MARK: - WeightUnit Conversion

@Suite("WeightUnit Conversion")
struct WeightUnitConversionTests {

    @Test("kg passes through unchanged")
    func kgIdentity() {
        #expect(WeightUnit.kg.fromKg(100) == 100)
        #expect(WeightUnit.kg.toKg(100) == 100)
        #expect(WeightUnit.kg.symbol == "kg")
    }

    @Test("lbs converts from kg for display")
    func lbsFromKg() {
        let lbs = WeightUnit.lbs.fromKg(100)
        #expect(abs(lbs - 220.462) < 0.001)
    }

    @Test("lbs input converts back to kg for storage")
    func lbsToKg() {
        let kg = WeightUnit.lbs.toKg(225)
        #expect(abs(kg - 102.058) < 0.01)
    }

    @Test("display-storage roundtrip is stable")
    func roundTrip() {
        let original = 102.5
        let roundTripped = WeightUnit.lbs.toKg(WeightUnit.lbs.fromKg(original))
        #expect(abs(roundTripped - original) < 0.0001)
    }

    @Test("format includes value and symbol")
    func formatting() {
        #expect(WeightUnit.kg.format(100) == "100 kg")
        #expect(WeightUnit.kg.format(102.5) == "102.5 kg")
        #expect(WeightUnit.lbs.format(100, decimals: 0) == "220 lbs")
        #expect(WeightUnit.kg.formatValue(80.0) == "80")
    }
}

// MARK: - Plateau Gap Weeks

@Suite("PlateauDetection Gap Weeks")
@MainActor
struct PlateauGapWeekTests {

    /// Build one workout per given week-offset (weeks before now), all using the
    /// same exercise, with the given top-set weight.
    private func makeWorkouts(weekOffsetsAndWeights: [(Int, Double)], exerciseId: UUID) -> [Workout] {
        let calendar = Calendar.mondayStart
        let now = Date()
        return weekOffsetsAndWeights.map { offset, weight in
            let date = calendar.date(byAdding: .weekOfYear, value: -offset, to: now)!
            let exercise = AnalyticsTestHelpers.makeExercise(id: exerciseId, name: "Squat", primaryMuscleGroup: .quadriceps, secondaryMuscleGroups: [])
            let sets = [AnalyticsTestHelpers.makeCompletedSet(order: 1, weight: weight, reps: 5)]
            let we = AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise, sets: sets)
            return AnalyticsTestHelpers.makeWorkout(exercises: [we], startedAt: date, completedAt: date.addingTimeInterval(3600))
        }
    }

    @Test("untrained gap weeks count toward the stall")
    func gapWeeksCounted() {
        let service = PlateauDetectionService()
        let exerciseId = UUID()
        // Declining weights with a 3-week gap between week-6 and week-2:
        // trained weeks: -7, -6, -2, -1, 0 — every comparison is a decline.
        let workouts = makeWorkouts(
            weekOffsetsAndWeights: [(7, 100), (6, 99), (2, 98), (1, 97), (0, 96)],
            exerciseId: exerciseId
        )
        let result = service.analyzePlateaus(bodyWeightKg: 70, workouts: workouts, windowWeeks: 10)

        let analysis = result.first { $0.exerciseId == exerciseId }
        #expect(analysis != nil, "Declining e1RM should be reported as a plateau")
        // Stall spans: (-7 -> -6) = 1, (-6 -> -2) = 4 (gap counted), (-2 -> -1) = 1, (-1 -> 0) = 1
        #expect((analysis?.consecutiveWeeksStalled ?? 0) >= 7,
                "Gap weeks must count toward stall duration, got \(analysis?.consecutiveWeeksStalled ?? 0)")
    }

    @Test("improvement resets the stall counter")
    func improvementResets() {
        let service = PlateauDetectionService()
        let exerciseId = UUID()
        // Decline for three comparisons, then a clear PR in the final week.
        let workouts = makeWorkouts(
            weekOffsetsAndWeights: [(4, 100), (3, 98), (2, 96), (1, 94), (0, 110)],
            exerciseId: exerciseId
        )
        let result = service.analyzePlateaus(bodyWeightKg: 70, workouts: workouts, windowWeeks: 10)
        let analysis = result.first { $0.exerciseId == exerciseId }
        #expect(analysis == nil || analysis?.consecutiveWeeksStalled == 0,
                "A clear improvement in the latest week should reset the stall")
    }
}

// MARK: - PersonalRecord Best-Value Comparison

@Suite("PersonalRecordService Comparison")
@MainActor
struct PersonalRecordComparisonTests {

    @Test("a set below the best historical record is not a PR even with multiple records present")
    func noFalsePRWithMultipleRecords() async throws {
        let prRepo = InMemoryPersonalRecordRepository()
        let workoutRepo = InMemoryWorkoutRepository()
        let service = PersonalRecordService(
            personalRecordRepository: prRepo,
            workoutRepository: workoutRepo
        )
        let exercise = AnalyticsTestHelpers.makeExercise(name: "Deadlift", primaryMuscleGroup: .back)

        // Two historical maxWeight records — an old low one and a newer high one.
        _ = try await prRepo.save(PersonalRecord(
            id: UUID(), exerciseId: exercise.id, recordType: .maxWeight,
            value: 80, setId: UUID(), achievedAt: Date(timeIntervalSinceNow: -86_400 * 60)
        ))
        _ = try await prRepo.save(PersonalRecord(
            id: UUID(), exerciseId: exercise.id, recordType: .maxWeight,
            value: 100, setId: UUID(), achievedAt: Date(timeIntervalSinceNow: -86_400 * 7)
        ))

        // 90 kg beats the old record but not the best — must NOT create a maxWeight PR.
        let set = AnalyticsTestHelpers.makeCompletedSet(weight: 90, reps: 1)
        _ = try await service.checkForPR(exercise: exercise, set: set)

        let records = try await prRepo.fetchForExercise(exercise.id)
        let maxWeightValues = records.filter { $0.recordType == .maxWeight }.map(\.value).sorted()
        #expect(!maxWeightValues.contains(90), "90 kg must not be recorded as a maxWeight PR when 100 kg exists")
    }

    @Test("a set above the best historical record is a PR")
    func realPRDetected() async throws {
        let prRepo = InMemoryPersonalRecordRepository()
        let workoutRepo = InMemoryWorkoutRepository()
        let service = PersonalRecordService(
            personalRecordRepository: prRepo,
            workoutRepository: workoutRepo
        )
        let exercise = AnalyticsTestHelpers.makeExercise(name: "Deadlift", primaryMuscleGroup: .back)
        _ = try await prRepo.save(PersonalRecord(
            id: UUID(), exerciseId: exercise.id, recordType: .maxWeight,
            value: 100, setId: UUID(), achievedAt: Date(timeIntervalSinceNow: -86_400 * 7)
        ))

        let set = AnalyticsTestHelpers.makeCompletedSet(weight: 105, reps: 1)
        let pr = try await service.checkForPR(exercise: exercise, set: set)
        #expect(pr != nil, "105 kg above the 100 kg best must be a PR")
    }
}

// MARK: - Hard-Set Credit Attribution

@Suite("Hard-Set Credit Attribution")
struct HardSetCreditTests {

    @Test("primary gets full credit, secondaries split half")
    func creditPolicy() {
        let credits = AnalyticsCalculations.attributeHardSetCredits(
            hardSets: 4,
            primaryMuscle: .quadriceps,
            secondaryMuscles: [.glutes, .hamstrings]
        )
        #expect(credits[.quadriceps] == 4.0)
        #expect(credits[.glutes] == 1.0)      // 4 * 0.5 / 2
        #expect(credits[.hamstrings] == 1.0)
    }

    @Test("no secondaries means primary-only credit")
    func primaryOnly() {
        let credits = AnalyticsCalculations.attributeHardSetCredits(
            hardSets: 3,
            primaryMuscle: .biceps,
            secondaryMuscles: []
        )
        #expect(credits == [.biceps: 3.0])
    }
}

// NOTE: SwiftData integration tests for SwiftDataTemplateRepository (exercise-ID
// stability across saves) cannot run in this hosted test target: any #Predicate
// fetch on a second ModelContainer traps inside SwiftData while the host app's
// container is live (verified with minimal probes — even a bare predicate fetch
// on an empty in-memory store crashes). This is why no test in this repo uses a
// real ModelContainer; repository behavior is covered by manual verification.
