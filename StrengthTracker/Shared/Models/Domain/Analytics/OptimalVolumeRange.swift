import Foundation

/// Optimal weekly set volume range for a muscle group based on performance data.
public struct OptimalVolumeRange: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let muscleGroup: String
    public let minimumWeeklySets: Int
    public let maximumWeeklySets: Int
    public let currentWeeklySets: Int
    public let volumeStatus: VolumeStatus

    public init(
        id: UUID = UUID(),
        muscleGroup: String,
        minimumWeeklySets: Int,
        maximumWeeklySets: Int,
        currentWeeklySets: Int,
        volumeStatus: VolumeStatus
    ) {
        self.id = id
        self.muscleGroup = muscleGroup
        self.minimumWeeklySets = minimumWeeklySets
        self.maximumWeeklySets = maximumWeeklySets
        self.currentWeeklySets = currentWeeklySets
        self.volumeStatus = volumeStatus
    }
}

/// Whether current volume is under, at, or over the optimal range.
public enum VolumeStatus: String, Codable, Sendable {
    case underVolume
    case optimal
    case overVolume
}
