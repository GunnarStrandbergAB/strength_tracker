import Testing
import Foundation
@testable import StrengthTrackerShared

// MARK: - MuscleGroup Enum Tests

@Suite("MuscleGroup Enum")
struct MuscleGroupTests {

    @Test("MuscleGroup has all expected cases")
    func allCases() {
        let expectedCases: [MuscleGroup] = [
            .chest, .back, .shoulders, .biceps, .triceps, .forearms,
            .core, .quadriceps, .hamstrings, .glutes, .calves,
            .adductors, .abductors, .traps, .lats,
            .hipFlexors, .lowerBack, .obliques,
            .fullBody, .cardio, .other
        ]
        #expect(MuscleGroup.allCases.count == expectedCases.count)
        for expected in expectedCases {
            #expect(MuscleGroup.allCases.contains(expected))
        }
    }

    @Test("MuscleGroup raw values are strings")
    func rawValues() {
        #expect(MuscleGroup.chest.rawValue == "chest")
        #expect(MuscleGroup.fullBody.rawValue == "fullBody")
        #expect(MuscleGroup.other.rawValue == "other")
    }

    @Test("MuscleGroup is Codable roundtrip")
    func codableRoundtrip() throws {
        let original = MuscleGroup.quadriceps
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MuscleGroup.self, from: data)
        #expect(decoded == original)
    }

    @Test("MuscleGroup conforms to Sendable")
    func sendable() {
        let value: any Sendable = MuscleGroup.chest
        #expect(value is MuscleGroup)
    }
}

// MARK: - ExerciseCategory Enum Tests

@Suite("ExerciseCategory Enum")
struct ExerciseCategoryTests {

    @Test("ExerciseCategory has all expected cases")
    func allCases() {
        let expectedCases: [ExerciseCategory] = [
            .barbell, .dumbbell, .machine, .cable, .bodyweight,
            .smithMachine, .kettlebell, .resistanceBand,
            .plate, .medicineBall, .exerciseBall, .trx,
            .landmine, .trapBar, .ezBar, .other
        ]
        #expect(ExerciseCategory.allCases.count == expectedCases.count)
        for expected in expectedCases {
            #expect(ExerciseCategory.allCases.contains(expected))
        }
    }

    @Test("ExerciseCategory raw values are strings")
    func rawValues() {
        #expect(ExerciseCategory.barbell.rawValue == "barbell")
        #expect(ExerciseCategory.smithMachine.rawValue == "smithMachine")
        #expect(ExerciseCategory.ezBar.rawValue == "ezBar")
    }

    @Test("ExerciseCategory is Codable roundtrip")
    func codableRoundtrip() throws {
        let original = ExerciseCategory.kettlebell
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExerciseCategory.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - ExerciseType Enum Tests

@Suite("ExerciseType Enum")
struct ExerciseTypeTests {

    @Test("ExerciseType has all expected cases")
    func allCases() {
        let expectedCases: [ExerciseType] = [
            .weightedReps, .bodyweightReps, .duration, .distance, .cardio, .weightedCardio
        ]
        #expect(ExerciseType.allCases.count == expectedCases.count)
        for expected in expectedCases {
            #expect(ExerciseType.allCases.contains(expected))
        }
    }

    @Test("ExerciseType raw values are strings")
    func rawValues() {
        #expect(ExerciseType.weightedReps.rawValue == "weightedReps")
        #expect(ExerciseType.bodyweightReps.rawValue == "bodyweightReps")
        #expect(ExerciseType.cardio.rawValue == "cardio")
    }

    @Test("ExerciseType is Codable roundtrip")
    func codableRoundtrip() throws {
        let original = ExerciseType.duration
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExerciseType.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - SetType Enum Tests

@Suite("SetType Enum")
struct SetTypeTests {

    @Test("SetType has all expected cases")
    func allCases() {
        let expectedCases: [SetType] = [
            .normal, .warmup, .dropset, .failure, .restPause
        ]
        #expect(SetType.allCases.count == expectedCases.count)
        for expected in expectedCases {
            #expect(SetType.allCases.contains(expected))
        }
    }

    @Test("SetType raw values are strings")
    func rawValues() {
        #expect(SetType.normal.rawValue == "normal")
        #expect(SetType.warmup.rawValue == "warmup")
        #expect(SetType.restPause.rawValue == "restPause")
    }

    @Test("SetType is Codable roundtrip")
    func codableRoundtrip() throws {
        let original = SetType.dropset
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SetType.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - MeasurementType Enum Tests

@Suite("MeasurementType Enum")
struct MeasurementTypeTests {

    @Test("MeasurementType has all expected cases")
    func allCases() {
        let expectedCases: [MeasurementType] = [
            .bodyWeight, .bodyFat,
            .chest, .leftArm, .rightArm, .leftForearm, .rightForearm,
            .waist, .hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf,
            .shoulders, .neck
        ]
        #expect(MeasurementType.allCases.count == expectedCases.count)
        for expected in expectedCases {
            #expect(MeasurementType.allCases.contains(expected))
        }
    }

    @Test("MeasurementType is Codable roundtrip")
    func codableRoundtrip() throws {
        let original = MeasurementType.bodyWeight
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MeasurementType.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - RecordType Enum Tests

@Suite("RecordType Enum")
struct RecordTypeTests {

    @Test("RecordType has all expected cases")
    func allCases() {
        let expectedCases: [RecordType] = [
            .estimatedOneRepMax, .maxWeight, .maxReps, .maxVolume,
            .maxTotalVolume, .bestPace, .longestDuration, .longestDistance
        ]
        #expect(RecordType.allCases.count == expectedCases.count)
        for expected in expectedCases {
            #expect(RecordType.allCases.contains(expected))
        }
    }

    @Test("RecordType is Codable roundtrip")
    func codableRoundtrip() throws {
        let original = RecordType.estimatedOneRepMax
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecordType.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - WeightUnit Enum Tests

@Suite("WeightUnit Enum")
struct WeightUnitTests {

    @Test("WeightUnit has kg and lbs")
    func allCases() {
        #expect(WeightUnit.kg.rawValue == "kg")
        #expect(WeightUnit.lbs.rawValue == "lbs")
    }

    @Test("WeightUnit is Codable roundtrip")
    func codableRoundtrip() throws {
        let original = WeightUnit.lbs
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WeightUnit.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - DistanceUnit Enum Tests

@Suite("DistanceUnit Enum")
struct DistanceUnitTests {

    @Test("DistanceUnit has km and miles")
    func allCases() {
        #expect(DistanceUnit.km.rawValue == "km")
        #expect(DistanceUnit.miles.rawValue == "miles")
    }

    @Test("DistanceUnit is Codable roundtrip")
    func codableRoundtrip() throws {
        let original = DistanceUnit.miles
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DistanceUnit.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - Exercise Struct Tests

@Suite("Exercise Model")
struct ExerciseTests {

    static let sampleExercise = Exercise(
        id: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
        name: "Bench Press",
        primaryMuscleGroup: .chest,
        secondaryMuscleGroups: [.triceps, .shoulders],
        category: .barbell,
        exerciseType: .weightedReps,
        instructions: "Lie on a flat bench and press the bar upward.",
        isCustom: false,
        isArchived: false
    )

    @Test("Exercise can be created with all fields")
    func creation() {
        let exercise = ExerciseTests.sampleExercise
        #expect(exercise.id == UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!)
        #expect(exercise.name == "Bench Press")
        #expect(exercise.primaryMuscleGroup == .chest)
        #expect(exercise.secondaryMuscleGroups == [.triceps, .shoulders])
        #expect(exercise.category == .barbell)
        #expect(exercise.exerciseType == .weightedReps)
        #expect(exercise.instructions == "Lie on a flat bench and press the bar upward.")
        #expect(exercise.isCustom == false)
        #expect(exercise.isArchived == false)
    }

    @Test("Exercise can be created with nil instructions")
    func nilInstructions() {
        let exercise = Exercise(
            id: UUID(),
            name: "Pull Up",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.biceps],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
        #expect(exercise.instructions == nil)
    }

    @Test("Exercise conforms to Identifiable")
    func identifiable() {
        let exercise = ExerciseTests.sampleExercise
        let id: UUID = exercise.id
        #expect(id == UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!)
    }

    @Test("Exercise conforms to Hashable")
    func hashable() {
        let exercise1 = ExerciseTests.sampleExercise
        let exercise2 = ExerciseTests.sampleExercise
        #expect(exercise1.hashValue == exercise2.hashValue)

        var set = Set<Exercise>()
        set.insert(exercise1)
        set.insert(exercise2)
        #expect(set.count == 1)
    }

    @Test("Exercise conforms to Sendable")
    func sendable() {
        let exercise: any Sendable = ExerciseTests.sampleExercise
        #expect(exercise is Exercise)
    }

    @Test("Exercise conforms to Equatable")
    func equatable() {
        let exercise1 = ExerciseTests.sampleExercise
        let exercise2 = ExerciseTests.sampleExercise
        #expect(exercise1 == exercise2)
    }

    @Test("Exercise Codable roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let original = ExerciseTests.sampleExercise
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Exercise.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.primaryMuscleGroup == original.primaryMuscleGroup)
        #expect(decoded.secondaryMuscleGroups == original.secondaryMuscleGroups)
        #expect(decoded.category == original.category)
        #expect(decoded.exerciseType == original.exerciseType)
        #expect(decoded.instructions == original.instructions)
        #expect(decoded.isCustom == original.isCustom)
        #expect(decoded.isArchived == original.isArchived)
    }

    @Test("Exercise Codable roundtrip with nil instructions")
    func codableRoundtripNilInstructions() throws {
        let original = Exercise(
            id: UUID(),
            name: "Plank",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [],
            category: .bodyweight,
            exerciseType: .duration,
            instructions: nil,
            isCustom: true,
            isArchived: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Exercise.self, from: data)

        #expect(decoded.instructions == nil)
        #expect(decoded.secondaryMuscleGroups.isEmpty)
        #expect(decoded.isCustom == true)
    }

    @Test("Two exercises with different IDs are not equal")
    func differentExercises() {
        let exercise1 = Exercise(
            id: UUID(),
            name: "Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
        let exercise2 = Exercise(
            id: UUID(),
            name: "Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
        #expect(exercise1 != exercise2)
    }
}
