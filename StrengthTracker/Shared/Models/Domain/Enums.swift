import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest, back, shoulders, biceps, triceps, forearms
    case core, quadriceps, hamstrings, glutes, calves
    case adductors, abductors, traps, lats
    case hipFlexors, lowerBack, obliques
    case fullBody, cardio, other
}

public enum ExerciseCategory: String, Codable, CaseIterable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight
    case smithMachine, kettlebell, resistanceBand
    case plate, medicineBall, exerciseBall, trx
    case landmine, trapBar, ezBar, other
}

public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case weightedReps
    case bodyweightReps
    case duration
    case distance
    case cardio
    case weightedCardio
}

public enum SetType: String, Codable, CaseIterable, Sendable {
    case normal
    case warmup
    case dropset
    case failure
    case restPause
}

public enum MeasurementType: String, Codable, CaseIterable, Sendable {
    case bodyWeight, bodyFat
    case chest, leftArm, rightArm, leftForearm, rightForearm
    case waist, hips, leftThigh, rightThigh, leftCalf, rightCalf
    case shoulders, neck
}

public enum RecordType: String, Codable, CaseIterable, Sendable {
    case estimatedOneRepMax
    case maxWeight
    case maxReps
    case maxVolume
    case maxTotalVolume
    case bestPace
    case longestDuration
    case longestDistance
}

public enum WeightUnit: String, Codable, Sendable {
    case kg, lbs
}

public enum DistanceUnit: String, Codable, Sendable {
    case km, miles
}

// MARK: - SetType cycling

extension SetType {
    public var nextType: SetType {
        let all = SetType.allCases
        guard let idx = all.firstIndex(of: self) else { return .normal }
        let next = all.index(after: idx)
        return next < all.endIndex ? all[next] : all[all.startIndex]
    }
}
