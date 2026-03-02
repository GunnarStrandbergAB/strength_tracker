import Foundation

/// Automatic detection of the current training phase from workout patterns.
public struct TrainingPhaseDetection: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let currentPhase: DetectedPhase
    public let phaseHistory: [PhaseWindow]

    public init(
        id: UUID = UUID(),
        currentPhase: DetectedPhase,
        phaseHistory: [PhaseWindow]
    ) {
        self.id = id
        self.currentPhase = currentPhase
        self.phaseHistory = phaseHistory
    }
}

/// Training phase classification based on vector feature analysis.
public enum DetectedPhase: String, Codable, Sendable {
    case accumulation    // high volume, moderate weight
    case intensification // moderate volume, high weight
    case peaking         // low volume, very high weight
    case deload          // low volume, low weight
    case mixed           // no clear pattern
}

/// A time window with an assigned phase.
public struct PhaseWindow: Hashable, Sendable, Codable {
    public let weekStart: Date
    public let phase: DetectedPhase

    public init(weekStart: Date, phase: DetectedPhase) {
        self.weekStart = weekStart
        self.phase = phase
    }
}
