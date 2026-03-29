import Foundation

public struct TrajectoryAnalysis: Sendable {
    public let velocityMagnitude: Double
    public let accelerationMagnitude: Double
    public let isSteadyState: Bool
    public let isDecelerating: Bool
    public let trajectoryEfficiency: Double
    public let predictedPlateauWeeks: Int?
    public let volumeSubspaceStagnating: Bool
    public let muscleSubspaceDrifting: Bool
    public let spinningWheels: Bool
    public let topAcceleratingDims: [(name: String, delta: Double)]
    public let topDeceleratingDims: [(name: String, delta: Double)]

    public init(
        velocityMagnitude: Double,
        accelerationMagnitude: Double,
        isSteadyState: Bool,
        isDecelerating: Bool,
        trajectoryEfficiency: Double,
        predictedPlateauWeeks: Int?,
        volumeSubspaceStagnating: Bool,
        muscleSubspaceDrifting: Bool,
        spinningWheels: Bool,
        topAcceleratingDims: [(name: String, delta: Double)],
        topDeceleratingDims: [(name: String, delta: Double)]
    ) {
        self.velocityMagnitude = velocityMagnitude
        self.accelerationMagnitude = accelerationMagnitude
        self.isSteadyState = isSteadyState
        self.isDecelerating = isDecelerating
        self.trajectoryEfficiency = trajectoryEfficiency
        self.predictedPlateauWeeks = predictedPlateauWeeks
        self.volumeSubspaceStagnating = volumeSubspaceStagnating
        self.muscleSubspaceDrifting = muscleSubspaceDrifting
        self.spinningWheels = spinningWheels
        self.topAcceleratingDims = topAcceleratingDims
        self.topDeceleratingDims = topDeceleratingDims
    }
}
