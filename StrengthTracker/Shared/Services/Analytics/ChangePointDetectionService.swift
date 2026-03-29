import Foundation

@MainActor
public final class ChangePointDetectionService: Sendable {
    private let searchService: VectorSearchService

    public init(searchService: VectorSearchService) {
        self.searchService = searchService
    }

    public func detectChangePoints(vectors: [WorkoutVector], threshold: Double = 2.0) -> [TrainingChangePoint] {
        let sorted = vectors.sorted { $0.createdAt < $1.createdAt }
        guard sorted.count >= 10 else { return [] }

        // Compute EWMA centroid and dissimilarity series
        let alpha = 0.3
        var ewmaCentroid = sorted[0].dimensions
        var dissimilarities: [Double] = []

        for i in 1..<sorted.count {
            let current = sorted[i].dimensions
            let sim = searchService.cosineSimilarity(current, ewmaCentroid)
            dissimilarities.append(1.0 - sim)

            // Update EWMA
            ewmaCentroid = zip(ewmaCentroid, current).map { alpha * $1 + (1 - alpha) * $0 }
        }

        // CUSUM on dissimilarity series
        guard dissimilarities.count >= 5 else { return [] }
        let mean = dissimilarities.reduce(0, +) / Double(dissimilarities.count)
        let stdDev = sqrt(dissimilarities.map { pow($0 - mean, 2) }.reduce(0, +) / Double(dissimilarities.count))
        guard stdDev > 0 else { return [] }

        var cusumHigh = 0.0
        var changePoints: [TrainingChangePoint] = []
        let featureNames = WorkoutVector.featureNames

        for i in 0..<dissimilarities.count {
            let z = (dissimilarities[i] - mean) / stdDev
            cusumHigh = max(0, cusumHigh + z - 0.5)

            if cusumHigh > threshold {
                cusumHigh = 0 // Reset after detection

                let vectorIdx = i + 1 // offset by 1 since dissimilarity starts at index 1
                guard vectorIdx < sorted.count else { continue }

                // Compute key dimension shifts (before vs after)
                let windowSize = min(5, i + 1)
                let beforeStart = max(0, vectorIdx - windowSize)
                let afterEnd = min(sorted.count, vectorIdx + windowSize)

                let beforeDims = centroid(sorted[beforeStart..<vectorIdx].map(\.dimensions))
                let afterDims = centroid(sorted[vectorIdx..<afterEnd].map(\.dimensions))

                let shifts = zip(beforeDims, afterDims).enumerated().compactMap { idx, pair -> DimensionDrift? in
                    let delta = pair.1 - pair.0
                    guard abs(delta) > 0.05, idx < featureNames.count else { return nil }
                    return DimensionDrift(featureName: featureNames[idx], delta: delta)
                }.sorted { abs($0.delta) > abs($1.delta) }

                let topShifts = Array(shifts.prefix(3))

                let topShift = topShifts.first
                let desc: String
                if let shift = topShift {
                    let dir = shift.delta > 0 ? "increased" : "decreased"
                    desc = "\(shift.featureName.replacingOccurrences(of: "_", with: " ")) \(dir)"
                } else {
                    desc = "Training pattern shifted"
                }

                changePoints.append(TrainingChangePoint(
                    date: sorted[vectorIdx].createdAt,
                    workoutIndex: vectorIdx,
                    description: desc,
                    keyDimensionShifts: topShifts
                ))
            }
        }

        return changePoints
    }

    // MARK: - Time-of-Day Analysis (B5)

    public func analyzeTimeOfDay(
        workouts: [Workout],
        qualityScores: [UUID: WorkoutQualityScore]
    ) -> TimeOfDayAnalysis? {
        let scored = workouts.compactMap { workout -> (hour: Int, quality: Double)? in
            guard let score = qualityScores[workout.id] else { return nil }
            let hour = Calendar.current.component(.hour, from: workout.startedAt)
            return (hour, score.overallScore)
        }
        guard scored.count >= 10 else { return nil }

        // Group into windows
        let windows: [(name: String, range: ClosedRange<Int>)] = [
            ("Morning (6-11 AM)", 5...10),
            ("Afternoon (11 AM-5 PM)", 11...16),
            ("Evening (5-10 PM)", 17...21),
            ("Night (10 PM-6 AM)", 22...28) // 22-4 wraps
        ]

        var windowScores: [(name: String, avg: Double, count: Int)] = []
        for window in windows {
            let matching = scored.filter { entry in
                let h = entry.hour
                if window.range.upperBound > 23 {
                    return h >= window.range.lowerBound || h <= (window.range.upperBound - 24)
                }
                return window.range.contains(h)
            }
            if matching.count >= 3 {
                let avg = matching.map(\.quality).reduce(0, +) / Double(matching.count)
                windowScores.append((window.name, avg, matching.count))
            }
        }

        guard windowScores.count >= 2,
              let best = windowScores.max(by: { $0.avg < $1.avg }),
              let worst = windowScores.min(by: { $0.avg < $1.avg }),
              best.name != worst.name else { return nil }

        let delta = best.avg - worst.avg
        guard delta > 5 else { return nil } // Only report if >5% difference

        return TimeOfDayAnalysis(
            bestWindow: best.name,
            bestAvgQuality: best.avg,
            worstWindow: worst.name,
            worstAvgQuality: worst.avg,
            message: String(format: "Your %@ workouts average %.0f%% higher quality than %@",
                          best.name.lowercased(), delta, worst.name.lowercased())
        )
    }

    private func centroid<S: Sequence>(_ vectors: S) -> [Double] where S.Element == [Double] {
        let arr = Array(vectors)
        guard !arr.isEmpty else { return [] }
        let d = arr[0].count
        var result = [Double](repeating: 0, count: d)
        for v in arr {
            for i in 0..<min(d, v.count) { result[i] += v[i] }
        }
        return result.map { $0 / Double(arr.count) }
    }
}
