import Foundation

/// Detects the current training phase from workout vector patterns.
/// Uses weekly centroid analysis with prototype matching.
@MainActor
public final class PhaseDetectionService: Sendable {

    private let searchService: VectorSearchService

    public init(searchService: VectorSearchService) {
        self.searchService = searchService
    }

    /// Detect training phases from vector history. Requires 4+ weeks of data.
    public func detectPhases(vectors: [WorkoutVector]) -> TrainingPhaseDetection? {
        guard vectors.count >= 4 else { return nil }

        let calendar = Calendar.current
        let sorted = vectors.sorted { $0.createdAt < $1.createdAt }

        // Group by week
        var weeklyVectors: [(weekStart: Date, vectors: [WorkoutVector])] = []
        var currentWeekStart: Date?
        var currentBatch: [WorkoutVector] = []

        for v in sorted {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: v.createdAt)?.start ?? v.createdAt
            if let current = currentWeekStart, calendar.isDate(current, equalTo: weekStart, toGranularity: .weekOfYear) {
                currentBatch.append(v)
            } else {
                if let start = currentWeekStart, !currentBatch.isEmpty {
                    weeklyVectors.append((start, currentBatch))
                }
                currentWeekStart = weekStart
                currentBatch = [v]
            }
        }
        if let start = currentWeekStart, !currentBatch.isEmpty {
            weeklyVectors.append((start, currentBatch))
        }

        guard weeklyVectors.count >= 4 else { return nil }

        // Compute weekly centroids
        let weeklyCentroids = weeklyVectors.map { (weekStart: $0.weekStart, centroid: computeCentroid(vectors: $0.vectors)) }

        // Classify each week
        let phaseHistory = weeklyCentroids.map { entry in
            PhaseWindow(weekStart: entry.weekStart, phase: classifyPhase(centroid: entry.centroid))
        }

        // Apply 3-window moving mode for stability
        let smoothed = smoothPhases(phaseHistory)
        let currentPhase = smoothed.last?.phase ?? .mixed

        return TrainingPhaseDetection(
            currentPhase: currentPhase,
            phaseHistory: smoothed
        )
    }

    // MARK: - Private

    private func computeCentroid(vectors: [WorkoutVector]) -> [Double] {
        guard let first = vectors.first else { return [] }
        let dim = first.dimensions.count
        var sum = [Double](repeating: 0, count: dim)
        for v in vectors {
            for i in 0..<dim {
                sum[i] += v.dimensions[i]
            }
        }
        let n = Double(vectors.count)
        return sum.map { $0 / n }
    }

    /// Classify a centroid into a training phase using key dimensions:
    /// 0=volume, 1=weight, 2=reps, 3=sets, 12=compound_ratio
    private func classifyPhase(centroid: [Double]) -> DetectedPhase {
        guard centroid.count >= 13 else { return .mixed }

        let volume = centroid[0]
        let weight = centroid[1]
        let reps = centroid[2]
        let sets = centroid[3]
        let compound = centroid[12]

        // Phase prototypes (relative feature magnitudes)
        // Deload: low everything
        if volume < 0.15 && weight < 0.15 && sets < 0.15 {
            return .deload
        }

        // Peaking: low volume/reps, high weight, high compound ratio
        if weight > volume * 1.3 && reps < 0.2 && compound > 0.15 {
            return .peaking
        }

        // Intensification: moderate volume, high weight
        if weight > volume && weight > reps {
            return .intensification
        }

        // Accumulation: high volume/sets/reps, moderate weight
        if (volume > weight || sets > weight) && reps > 0.1 {
            return .accumulation
        }

        return .mixed
    }

    /// Apply 3-element moving mode filter for phase stability.
    private func smoothPhases(_ phases: [PhaseWindow]) -> [PhaseWindow] {
        guard phases.count >= 3 else { return phases }
        var result = phases
        for i in 1..<(phases.count - 1) {
            let window = [phases[i - 1].phase, phases[i].phase, phases[i + 1].phase]
            let mode = mostFrequent(window)
            result[i] = PhaseWindow(weekStart: phases[i].weekStart, phase: mode)
        }
        return result
    }

    private func mostFrequent(_ phases: [DetectedPhase]) -> DetectedPhase {
        var counts: [DetectedPhase: Int] = [:]
        for p in phases {
            counts[p, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .mixed
    }
}
