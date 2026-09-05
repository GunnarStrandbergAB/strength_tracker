import Foundation

/// Summary data shown on the post-workout debrief screen.
public struct PostWorkoutDebrief: Sendable {
    public let workoutName: String
    public let duration: TimeInterval
    public let totalVolume: Double
    public let totalSets: Int
    public let exerciseCount: Int
    public let qualityScore: WorkoutQualityScore?
    public let prsHit: Int
    public let bullets: [CoachingInsight]       // 2-3 contextual coaching bullets
    public let similarSession: SessionComparison?
    /// The shared coach verdict at the time of the debrief (shown as "NEXT SESSION").
    public let verdict: TrainingVerdict?

    public init(
        workoutName: String,
        duration: TimeInterval,
        totalVolume: Double,
        totalSets: Int,
        exerciseCount: Int,
        qualityScore: WorkoutQualityScore?,
        prsHit: Int,
        bullets: [CoachingInsight],
        similarSession: SessionComparison?,
        verdict: TrainingVerdict? = nil
    ) {
        self.workoutName = workoutName
        self.duration = duration
        self.totalVolume = totalVolume
        self.totalSets = totalSets
        self.exerciseCount = exerciseCount
        self.qualityScore = qualityScore
        self.prsHit = prsHit
        self.bullets = bullets
        self.similarSession = similarSession
        self.verdict = verdict
    }
}

/// C6: Comparison of current workout against the most similar past session.
public struct SessionComparison: Sendable {
    public let matchDate: Date
    public let matchName: String
    public let similarity: Double
    public let volumeDelta: Double        // percentage change vs matched session
    public let intensityDelta: Double     // percentage change in avg weight

    public init(
        matchDate: Date,
        matchName: String,
        similarity: Double,
        volumeDelta: Double,
        intensityDelta: Double
    ) {
        self.matchDate = matchDate
        self.matchName = matchName
        self.similarity = similarity
        self.volumeDelta = volumeDelta
        self.intensityDelta = intensityDelta
    }
}
