import Foundation

/// Training load metrics based on EWMA acute/chronic workload ratio.
public struct TrainingLoad: Identifiable, Hashable, Sendable, Codable {
    public struct Day: Hashable, Sendable, Codable, Identifiable {
        public var id: Date { date }
        public let date: Date
        public let recent: Double
        public let baseline: Double
    }
    public let history: [Day]?
    public let id: UUID
    public let acuteLoad: Double
    public let chronicLoad: Double
    public let acwr: Double
    public let loadZone: LoadZone
    public let perMuscleGroupACWR: [String: Double]

    public init(
        id: UUID = UUID(),
        acuteLoad: Double,
        chronicLoad: Double,
        acwr: Double,
        loadZone: LoadZone,
        perMuscleGroupACWR: [String: Double] = [:],
        history: [Day]? = nil
    ) {
        self.history = history
        self.id = id
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.acwr = acwr
        self.loadZone = loadZone
        self.perMuscleGroupACWR = perMuscleGroupACWR
    }
}

/// Training load zone derived from ACWR.
public enum LoadZone: String, Codable, Sendable {
    case underTraining  // ACWR < 0.6
    case optimal        // 0.6 - 1.3
    case caution        // 1.3 - 1.5
    case danger         // > 1.5

    public static func from(acwr: Double) -> LoadZone {
        switch acwr {
        case ..<0.6: return .underTraining
        case 0.6..<1.3: return .optimal
        case 1.3..<1.5: return .caution
        default: return .danger
        }
    }
}
