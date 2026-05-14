import Foundation

/// Per-muscle volume-response analysis.
/// Observation-only: every reported landmark is grounded in the user's logged history.
/// Nothing is extrapolated outside the user's tested volume range.
public struct VolumeResponseAnalysis: Sendable, Equatable {
    public let muscleGroup: String
    public let bins: [BinResponse]
    public let best: BestRangeStatus
    public let lower: LowerBoundStatus
    public let upper: UpperBoundStatus
    public let confidence: Confidence
    public let testedRange: ClosedRange<Int>?
    public let sentence: String

    public init(
        muscleGroup: String,
        bins: [BinResponse],
        best: BestRangeStatus,
        lower: LowerBoundStatus,
        upper: UpperBoundStatus,
        confidence: Confidence,
        testedRange: ClosedRange<Int>?,
        sentence: String
    ) {
        self.muscleGroup = muscleGroup
        self.bins = bins
        self.best = best
        self.lower = lower
        self.upper = upper
        self.confidence = confidence
        self.testedRange = testedRange
        self.sentence = sentence
    }
}

public struct BinResponse: Sendable, Equatable {
    public let bin: VolumeBin
    public let observationCount: Int
    public let median: Double?
    public let q1: Double?
    public let q3: Double?
    public let smoothed: Double?

    public init(
        bin: VolumeBin,
        observationCount: Int,
        median: Double?,
        q1: Double?,
        q3: Double?,
        smoothed: Double?
    ) {
        self.bin = bin
        self.observationCount = observationCount
        self.median = median
        self.q1 = q1
        self.q3 = q3
        self.smoothed = smoothed
    }

    public var isPopulated: Bool { observationCount >= 3 }
}

public enum VolumeBin: String, CaseIterable, Sendable, Equatable {
    case zeroToFour       = "0-4"
    case fiveToEight      = "5-8"
    case nineToTwelve     = "9-12"
    case thirteenToSixteen = "13-16"
    case seventeenToTwenty = "17-20"
    case twentyOnePlus    = "21+"

    public static func bin(for dose: Double) -> VolumeBin {
        switch dose {
        case ..<5: return .zeroToFour
        case ..<9: return .fiveToEight
        case ..<13: return .nineToTwelve
        case ..<17: return .thirteenToSixteen
        case ..<21: return .seventeenToTwenty
        default: return .twentyOnePlus
        }
    }

    public var label: String { rawValue }

    public var midpoint: Double {
        switch self {
        case .zeroToFour: return 2
        case .fiveToEight: return 6.5
        case .nineToTwelve: return 10.5
        case .thirteenToSixteen: return 14.5
        case .seventeenToTwenty: return 18.5
        case .twentyOnePlus: return 23
        }
    }
}

public enum BestRangeStatus: Sendable, Equatable {
    /// Populated bins exist both below and above the best bin.
    case observedPeak(VolumeBin)
    /// Best bin is the highest tested — true upper limit unknown.
    case bestObservedSoFar(VolumeBin)
    /// Top candidate bins overlap in uncertainty; no clear winner.
    case unclear([VolumeBin])
    case insufficient
}

public enum LowerBoundStatus: Sendable, Equatable {
    /// Lowest bin whose response IQR is strictly above 0.
    case likelyProductiveFrom(VolumeBin)
    case noMeaningfulFloorYet
}

public enum UpperBoundStatus: Sendable, Equatable {
    /// Higher bin's response drops ≥ 30% relative to best.
    case diminishingReturnsObserved(VolumeBin)
    /// Diminishing returns + recovery degradation signal. Not emitted in v1.
    case recoveryLimitObserved(VolumeBin)
    /// No higher bin has been trained.
    case notYetTestedAbove(maxObservedDose: Double)
}

public enum Confidence: String, Sendable, Equatable {
    case high, medium, low, insufficient
}
