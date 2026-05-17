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

        let calendar = Calendar.mondayStart
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
        let weeklyCentroids = weeklyVectors.map { (weekStart: $0.weekStart, centroid: searchService.computeCentroid(vectors: $0.vectors)) }

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

    /// Active dim indices for phase classification:
    /// 0=total_volume_norm, 1=avg_weight_norm, 2=avg_reps_norm, 3=set_count_norm,
    /// 4=exercise_diversity, 5=duration_norm, 12=compound_ratio, 13=avg_rpe, 16=pr_count_norm.
    /// Skipped: muscle ratios (workout-type, not phase), time-of-day (life logistics),
    /// volume_vs_prev_7d/30d (week-to-week noise at this aggregation).
    private static let activeDims: [Int] = [0, 1, 2, 3, 4, 5, 12, 13, 16]

    /// Hand-tuned prototype centroids per phase. Values are in pre-normalisation space
    /// and reflect "what this phase typically looks like" on the same scale as the
    /// vectorizer output. Both prototype and observed centroid are L2-normalised over
    /// `activeDims` before cosine similarity comparison, so absolute scale doesn't matter
    /// — only the *shape* of the activation profile.
    private static let phasePrototypes: [DetectedPhase: [Double]] = [
        // [vol, wt, reps, sets, div, dur, cmp, rpe, pr]
        .deload:          [0.20, 0.20, 0.30, 0.20, 0.30, 0.40, 0.30, 0.45, 0.05],
        .accumulation:    [0.65, 0.40, 0.55, 0.65, 0.55, 0.65, 0.50, 0.65, 0.15],
        .intensification: [0.45, 0.65, 0.30, 0.45, 0.40, 0.55, 0.65, 0.75, 0.25],
        .peaking:         [0.25, 0.80, 0.15, 0.30, 0.25, 0.45, 0.80, 0.85, 0.45],
    ]

    /// Minimum cosine similarity to confidently assign a phase. Below this, return .mixed.
    private static let confidenceFloor = 0.85
    /// Minimum margin between the top and second-place phase score for an unambiguous pick.
    private static let unambiguousMargin = 0.02

    /// Classify a centroid by cosine distance to per-phase prototypes.
    /// Returns the phase whose prototype best matches the centroid's activation profile
    /// over the active dims; falls back to `.mixed` when no prototype dominates.
    private func classifyPhase(centroid: [Double]) -> DetectedPhase {
        guard centroid.count >= 17 else { return .mixed }

        // Project the observed centroid onto the active dims, then L2-normalise.
        let projected = Self.activeDims.map { centroid[$0] }
        let observed = AnalyticsCalculations.l2Normalize(projected)

        // Score each prototype.
        var scored: [(phase: DetectedPhase, score: Double)] = []
        for (phase, prototype) in Self.phasePrototypes {
            let normProto = AnalyticsCalculations.l2Normalize(prototype)
            let score = searchService.cosineSimilarity(observed, normProto)
            scored.append((phase, score))
        }
        scored.sort { $0.score > $1.score }

        guard let top = scored.first else { return .mixed }
        guard top.score >= Self.confidenceFloor else { return .mixed }
        if scored.count >= 2, (top.score - scored[1].score) < Self.unambiguousMargin {
            return .mixed
        }
        return top.phase
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
