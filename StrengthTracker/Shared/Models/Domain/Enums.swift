import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest, back, shoulders, biceps, triceps, forearms
    case core, quadriceps, hamstrings, glutes, calves
    case adductors, abductors, traps, lats
    case fullBody, cardio, other
}

enum ExerciseCategory: String, Codable, CaseIterable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight
    case smithMachine, kettlebell, resistanceBand
    case plate, medicineBall, exerciseBall, trx
    case landmine, trapBar, ezBar, other
}

enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case weightedReps
    case bodyweightReps
    case duration
    case cardio
    case weightedCardio
}

enum SetType: String, Codable, CaseIterable, Sendable {
    case normal
    case warmup
    case dropset
    case failure
    case restPause
}

enum MeasurementType: String, Codable, CaseIterable, Sendable {
    case bodyWeight, bodyFat
    case chest, leftArm, rightArm, leftForearm, rightForearm
    case waist, hips, leftThigh, rightThigh, leftCalf, rightCalf
    case shoulders, neck
}

enum RecordType: String, Codable, CaseIterable, Sendable {
    case estimatedOneRepMax
    case maxWeight
    case maxReps
    case maxVolume
    case maxTotalVolume
    case bestPace
    case longestDuration
    case longestDistance
}

enum WeightUnit: String, Codable, Sendable {
    case kg, lbs
}

enum DistanceUnit: String, Codable, Sendable {
    case km, miles
}
