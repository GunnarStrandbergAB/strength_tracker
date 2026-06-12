import Testing
import Foundation
@testable import StrengthTrackerShared

// MARK: - WorkoutTemplate Tests

@Suite("WorkoutTemplate Tests")
struct WorkoutTemplateTests {

    @Test("WorkoutTemplate creation with name and exercises")
    func testCreation() {
        let exercise = Exercise(
            id: UUID(),
            name: "Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )

        let templateExercise = TemplateExercise(
            id: UUID(),
            exercise: exercise,
            order: 0,
            supersetGroup: nil,
            notes: "Go heavy",
            restTimerSeconds: 120,
            targetSets: 4,
            targetReps: 8,
            targetWeight: 100.0,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil
        )

        let template = WorkoutTemplate(
            id: UUID(),
            name: "Push Day A",
            notes: "Focus on chest",
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [templateExercise]
        )

        #expect(template.name == "Push Day A")
        #expect(template.notes == "Focus on chest")
        #expect(template.sortOrder == 0)
        #expect(template.lastUsedAt == nil)
        #expect(template.timesUsed == 0)
        #expect(template.exercises.count == 1)
        #expect(template.exercises[0].exercise.name == "Bench Press")
    }

    @Test("WorkoutTemplate is Identifiable")
    func testIdentifiable() {
        let id = UUID()
        let template = WorkoutTemplate(
            id: id,
            name: "Test",
            notes: nil,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: []
        )
        #expect(template.id == id)
    }

    @Test("WorkoutTemplate Codable roundtrip")
    func testCodable() throws {
        let exercise = Exercise(
            id: UUID(),
            name: "Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .hamstrings],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )

        let templateExercise = TemplateExercise(
            id: UUID(),
            exercise: exercise,
            order: 0,
            supersetGroup: 1,
            notes: nil,
            restTimerSeconds: 90,
            targetSets: 5,
            targetReps: 5,
            targetWeight: 140.0,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil
        )

        let original = WorkoutTemplate(
            id: UUID(),
            name: "Leg Day",
            notes: "Heavy squats",
            sortOrder: 1,
            lastUsedAt: Date(timeIntervalSince1970: 1000000),
            timesUsed: 5,
            exercises: [templateExercise]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkoutTemplate.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.notes == original.notes)
        #expect(decoded.sortOrder == original.sortOrder)
        #expect(decoded.timesUsed == original.timesUsed)
        #expect(decoded.exercises.count == 1)
        #expect(decoded.exercises[0].targetSets == 5)
        #expect(decoded.exercises[0].targetWeight == 140.0)
    }
}

// MARK: - TemplateExercise Tests

@Suite("TemplateExercise Tests")
struct TemplateExerciseTests {

    @Test("TemplateExercise has correct target fields")
    func testTargetFields() {
        let exercise = Exercise(
            id: UUID(),
            name: "Running",
            primaryMuscleGroup: .cardio,
            secondaryMuscleGroups: [],
            category: .bodyweight,
            exerciseType: .cardio,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )

        let templateExercise = TemplateExercise(
            id: UUID(),
            exercise: exercise,
            order: 2,
            supersetGroup: nil,
            notes: "Easy pace",
            restTimerSeconds: nil,
            targetSets: 1,
            targetReps: nil,
            targetWeight: nil,
            targetDurationSeconds: 1800,
            targetDistanceMeters: 5000.0
        )

        #expect(templateExercise.targetSets == 1)
        #expect(templateExercise.targetReps == nil)
        #expect(templateExercise.targetWeight == nil)
        #expect(templateExercise.targetDurationSeconds == 1800)
        #expect(templateExercise.targetDistanceMeters == 5000.0)
        #expect(templateExercise.order == 2)
        #expect(templateExercise.supersetGroup == nil)
        #expect(templateExercise.notes == "Easy pace")
        #expect(templateExercise.restTimerSeconds == nil)
    }

    @Test("TemplateExercise Codable roundtrip")
    func testCodable() throws {
        let exercise = Exercise(
            id: UUID(),
            name: "Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )

        let original = TemplateExercise(
            id: UUID(),
            exercise: exercise,
            order: 1,
            supersetGroup: 2,
            notes: "Slow negatives",
            restTimerSeconds: 60,
            targetSets: 3,
            targetReps: 12,
            targetWeight: 15.0,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TemplateExercise.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.exercise.name == "Curl")
        #expect(decoded.supersetGroup == 2)
        #expect(decoded.targetSets == 3)
        #expect(decoded.targetReps == 12)
        #expect(decoded.targetWeight == 15.0)
    }
}

// MARK: - BodyMeasurement Tests

@Suite("BodyMeasurement Tests")
struct BodyMeasurementTests {

    @Test("BodyMeasurement creation with date, type, value, unit")
    func testCreation() {
        let date = Date()
        let measurement = BodyMeasurement(
            id: UUID(),
            date: date,
            measurementType: .bodyWeight,
            value: 180.5,
            unit: "lbs",
            notes: "Morning weight"
        )

        #expect(measurement.date == date)
        #expect(measurement.measurementType == .bodyWeight)
        #expect(measurement.value == 180.5)
        #expect(measurement.unit == "lbs")
        #expect(measurement.notes == "Morning weight")
    }

    @Test("BodyMeasurement types cover all MeasurementType cases")
    func testAllMeasurementTypes() {
        let allCases: [MeasurementType] = MeasurementType.allCases
        let expectedCases: [MeasurementType] = [
            .bodyWeight, .bodyFat,
            .chest, .leftArm, .rightArm, .leftForearm, .rightForearm,
            .waist, .hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf,
            .shoulders, .neck
        ]

        #expect(allCases.count == expectedCases.count)
        for expected in expectedCases {
            #expect(allCases.contains(expected))
        }
    }

    @Test("BodyMeasurement with nil notes")
    func testNilNotes() {
        let measurement = BodyMeasurement(
            id: UUID(),
            date: Date(),
            measurementType: .waist,
            value: 32.0,
            unit: "inches",
            notes: nil
        )

        #expect(measurement.notes == nil)
    }

    @Test("BodyMeasurement Codable roundtrip")
    func testCodable() throws {
        let original = BodyMeasurement(
            id: UUID(),
            date: Date(timeIntervalSince1970: 2000000),
            measurementType: .bodyFat,
            value: 15.2,
            unit: "%",
            notes: "DEXA scan"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BodyMeasurement.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.measurementType == .bodyFat)
        #expect(decoded.value == 15.2)
        #expect(decoded.unit == "%")
        #expect(decoded.notes == "DEXA scan")
    }

    @Test("BodyMeasurement for each measurement type")
    func testEachType() {
        for measurementType in MeasurementType.allCases {
            let m = BodyMeasurement(
                id: UUID(),
                date: Date(),
                measurementType: measurementType,
                value: 100.0,
                unit: "cm",
                notes: nil
            )
            #expect(m.measurementType == measurementType)
        }
    }
}

// MARK: - PersonalRecord Tests

@Suite("PersonalRecord Tests")
struct PersonalRecordTests {

    @Test("PersonalRecord creation with exerciseId, recordType, value, achievedAt")
    func testCreation() {
        let exerciseId = UUID()
        let setId = UUID()
        let achievedAt = Date()

        let record = PersonalRecord(
            id: UUID(),
            exerciseId: exerciseId,
            recordType: .maxWeight,
            value: 315.0,
            setId: setId,
            achievedAt: achievedAt
        )

        #expect(record.exerciseId == exerciseId)
        #expect(record.recordType == .maxWeight)
        #expect(record.value == 315.0)
        #expect(record.setId == setId)
        #expect(record.achievedAt == achievedAt)
    }

    @Test("PersonalRecord types cover all RecordType cases")
    func testAllRecordTypes() {
        let allCases: [RecordType] = RecordType.allCases
        let expectedCases: [RecordType] = [
            .estimatedOneRepMax, .maxWeight, .maxReps,
            .maxVolume, .maxTotalVolume,
            .bestPace, .longestDuration, .longestDistance
        ]

        #expect(allCases.count == expectedCases.count)
        for expected in expectedCases {
            #expect(allCases.contains(expected))
        }
    }

    @Test("PersonalRecord with nil setId")
    func testNilSetId() {
        let record = PersonalRecord(
            id: UUID(),
            exerciseId: UUID(),
            recordType: .maxTotalVolume,
            value: 10000.0,
            setId: nil,
            achievedAt: Date()
        )

        #expect(record.setId == nil)
    }

    @Test("PersonalRecord Codable roundtrip")
    func testCodable() throws {
        let original = PersonalRecord(
            id: UUID(),
            exerciseId: UUID(),
            recordType: .estimatedOneRepMax,
            value: 225.5,
            setId: UUID(),
            achievedAt: Date(timeIntervalSince1970: 3000000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersonalRecord.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.exerciseId == original.exerciseId)
        #expect(decoded.recordType == .estimatedOneRepMax)
        #expect(decoded.value == 225.5)
        #expect(decoded.setId == original.setId)
    }

    @Test("PersonalRecord for each record type")
    func testEachRecordType() {
        for recordType in RecordType.allCases {
            let pr = PersonalRecord(
                id: UUID(),
                exerciseId: UUID(),
                recordType: recordType,
                value: 42.0,
                setId: nil,
                achievedAt: Date()
            )
            #expect(pr.recordType == recordType)
        }
    }
}
