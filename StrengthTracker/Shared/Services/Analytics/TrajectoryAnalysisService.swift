import Foundation

@MainActor
public final class TrajectoryAnalysisService: Sendable {
    public init() {}

    public func analyze(vectors: [WorkoutVector], windowSize: Int = 10) -> TrajectoryAnalysis? {
        // Need at least 6 vectors for 3 time windows
        let sorted = vectors.sorted { $0.createdAt < $1.createdAt }
        let recent = Array(sorted.suffix(max(windowSize, 6)))
        guard recent.count >= 6 else { return nil }

        let dimCount = recent[0].dimensions.count

        // Divide into 3 windows
        let thirdSize = recent.count / 3
        let oldWindow = Array(recent[0..<thirdSize])
        let midWindow = Array(recent[thirdSize..<(thirdSize * 2)])
        let newWindow = Array(recent[(thirdSize * 2)...])

        let oldCentroid = centroid(oldWindow.map(\.dimensions))
        let midCentroid = centroid(midWindow.map(\.dimensions))
        let newCentroid = centroid(newWindow.map(\.dimensions))

        // Velocity = new - mid (per-dimension)
        let velocity = zip(newCentroid, midCentroid).map { $0.0 - $0.1 }
        let oldVelocity = zip(midCentroid, oldCentroid).map { $0.0 - $0.1 }

        // Acceleration = new_velocity - old_velocity
        let acceleration = zip(velocity, oldVelocity).map { $0.0 - $0.1 }

        let velMag = magnitude(velocity)
        let accMag = magnitude(acceleration)

        // Steady state: low velocity + low acceleration
        let isSteadyState = velMag < 0.05 && accMag < 0.02

        // Decelerating: negative acceleration in volume dims (0-2)
        let volumeAccel = Array(acceleration.prefix(3))
        let isDecelerating = volumeAccel.allSatisfy { $0 < 0 }

        // Volume subspace stagnating: dims 0-2
        let volumeVel = Array(velocity.prefix(3))
        let volumeSubspaceStagnating = magnitude(volumeVel) < 0.03

        // Muscle subspace drifting: dims 6-11
        let muscleUpperBound = min(12, dimCount)
        let muscleVel: [Double]
        if dimCount > 6 {
            muscleVel = Array(velocity[6..<muscleUpperBound])
        } else {
            muscleVel = []
        }
        let muscleSubspaceDrifting = magnitude(muscleVel) > 0.1

        // Spinning wheels: low magnitude + high angular change
        let cosSim = cosineSimilarity(velocity, oldVelocity)
        let angularChange = acos(max(-1, min(1, cosSim))) * 180 / .pi
        let spinningWheels = velMag < 0.05 && angularChange > 45

        // Trajectory efficiency
        let trajectoryEfficiency: Double
        if angularChange > 1 {
            trajectoryEfficiency = velMag / (angularChange / 180.0)
        } else {
            trajectoryEfficiency = velMag > 0 ? 1.0 : 0.0
        }

        // Predicted plateau: if velocity magnitude declining, extrapolate to zero
        let predictedPlateauWeeks: Int?
        if isDecelerating && velMag > 0.01 {
            let velChangeRate = magnitude(acceleration)
            if velChangeRate > 0.001 {
                let weeksToZero = Int(ceil(velMag / velChangeRate))
                predictedPlateauWeeks = min(weeksToZero, 52) // cap at 1 year
            } else {
                predictedPlateauWeeks = nil
            }
        } else {
            predictedPlateauWeeks = nil
        }

        // Top accelerating/decelerating dimensions
        let featureNames = WorkoutVector.featureNames
        let dimDeltas: [(name: String, delta: Double)] = velocity.enumerated().compactMap { idx, val in
            guard idx < featureNames.count else { return nil }
            return (featureNames[idx], val)
        }

        let topAccelerating = dimDeltas
            .filter { $0.delta > 0 }
            .sorted { $0.delta > $1.delta }
            .prefix(3)
            .map { ($0.name, $0.delta) }
        let topDecelerating = dimDeltas
            .filter { $0.delta < 0 }
            .sorted { $0.delta < $1.delta }
            .prefix(3)
            .map { ($0.name, $0.delta) }

        return TrajectoryAnalysis(
            velocityMagnitude: velMag,
            accelerationMagnitude: accMag,
            isSteadyState: isSteadyState,
            isDecelerating: isDecelerating,
            trajectoryEfficiency: trajectoryEfficiency,
            predictedPlateauWeeks: predictedPlateauWeeks,
            volumeSubspaceStagnating: volumeSubspaceStagnating,
            muscleSubspaceDrifting: muscleSubspaceDrifting,
            spinningWheels: spinningWheels,
            topAcceleratingDims: topAccelerating,
            topDeceleratingDims: topDecelerating
        )
    }

    private func centroid(_ vectors: [[Double]]) -> [Double] {
        guard !vectors.isEmpty else { return [] }
        let n = Double(vectors.count)
        let dimCount = vectors[0].count
        var result = [Double](repeating: 0, count: dimCount)
        for v in vectors {
            for i in 0..<min(dimCount, v.count) {
                result[i] += v[i]
            }
        }
        return result.map { $0 / n }
    }

    private func magnitude(_ v: [Double]) -> Double {
        sqrt(v.reduce(0) { $0 + $1 * $1 })
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let magA = magnitude(a)
        let magB = magnitude(b)
        guard magA > 0 && magB > 0 else { return 0 }
        return dot / (magA * magB)
    }
}
