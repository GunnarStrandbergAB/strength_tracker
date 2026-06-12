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

    /// Conversion factor between kilograms and pounds.
    public static let lbsPerKg = 2.20462

    public var symbol: String {
        switch self {
        case .kg: return "kg"
        case .lbs: return "lbs"
        }
    }

    /// Converts a stored kg value into this unit for display.
    /// Weights are always persisted in kg; convert only at the display/input boundary.
    public func fromKg(_ kg: Double) -> Double {
        self == .kg ? kg : kg * Self.lbsPerKg
    }

    /// Converts a user-entered value in this unit back to kg for storage.
    public func toKg(_ value: Double) -> Double {
        self == .kg ? value : value / Self.lbsPerKg
    }

    /// Formats a stored kg value in this unit including the unit symbol,
    /// e.g. format(100) -> "100 kg" or "220.46 lbs".
    /// Pass `decimals` for fixed precision; default trims trailing zeros.
    public func format(_ kg: Double, decimals: Int? = nil) -> String {
        "\(formatValue(kg, decimals: decimals)) \(symbol)"
    }

    /// Formats a stored kg value in this unit without the symbol, for input fields.
    public func formatValue(_ kg: Double, decimals: Int? = nil) -> String {
        let value = fromKg(kg)
        if let decimals {
            return String(format: "%.\(decimals)f", value)
        }
        // Round to 2 decimals, then trim trailing zeros via %g
        return String(format: "%g", (value * 100).rounded() / 100)
    }
}

public enum DistanceUnit: String, Codable, Sendable {
    case km, miles
}

// MARK: - SetType cycling & display

extension SetType {
    public var nextType: SetType {
        let all = SetType.allCases
        guard let idx = all.firstIndex(of: self) else { return .normal }
        let next = all.index(after: idx)
        return next < all.endIndex ? all[next] : all[all.startIndex]
    }

    public var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .warmup: return "Warm-up"
        case .dropset: return "Drop Set"
        case .failure: return "Failure"
        case .restPause: return "Rest-Pause"
        }
    }
}
