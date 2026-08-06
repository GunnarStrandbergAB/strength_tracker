import Foundation

/// Central "knowledgeable training partner brain" that produces contextual coaching
/// insights for post-workout, pre-workout, and inline contexts.
/// Stateless. Prioritizes, deduplicates, and routes insights.
@MainActor
public final class CoachingInsightService: Sendable {

    private let searchService: VectorSearchService
    private let qualityScoreService: WorkoutQualityScoreService?
    private let insightGenerator: (any InsightTextGenerating)?

    public init(
        searchService: VectorSearchService,
        qualityScoreService: WorkoutQualityScoreService? = nil,
        insightGenerator: (any InsightTextGenerating)? = nil
    ) {
        self.searchService = searchService
        self.qualityScoreService = qualityScoreService
        self.insightGenerator = insightGenerator
    }

    // MARK: - Post-Workout Debrief (C1 + C6)

    public func generatePostWorkoutDebrief(
        workout: Workout,
        allWorkouts: [Workout],
        overloadTrends: [OverloadTrend],
        qualityScore: WorkoutQualityScore?,
        recoveryPatterns: [RecoveryPattern],
        trainingLoad: TrainingLoad?,
        optimalVolumes: [OptimalVolumeRange],
        currentVector: WorkoutVector?,
        allVectors: [WorkoutVector],
        bodyWeightKg: Double
    ) async -> PostWorkoutDebrief {
        let completedWorkouts = allWorkouts.filter { $0.completedAt != nil && $0.id != workout.id }
        let workoutCount = completedWorkouts.count + 1

        // Basic stats
        let duration = workout.duration ?? Date().timeIntervalSince(workout.startedAt)
        let totalVolume = workout.totalVolume(bodyWeightKg: bodyWeightKg)
        let completedSets = workout.exercises.flatMap(\.sets).filter(\.isCompleted)
        let totalSets = completedSets.count
        let exerciseCount = workout.exercises.count
        let prsHit = completedSets.filter(\.isPersonalRecord).count

        // Session comparison (C6)
        let similarSession = findSimilarSession(
            workout: workout,
            allWorkouts: completedWorkouts,
            currentVector: currentVector,
            allVectors: allVectors,
            bodyWeightKg: bodyWeightKg
        )

        // Generate coaching bullets (priority-sorted, max 3)
        var candidates: [CoachingInsight] = []

        // PR bullet (always highest priority)
        if prsHit > 0 {
            let noun = prsHit == 1 ? "personal record" : "personal records"
            candidates.append(CoachingInsight(
                priority: 1,
                title: "\(prsHit) New PR\(prsHit > 1 ? "s" : "")",
                detail: "Hit \(prsHit) \(noun) this session",
                icon: "trophy.fill",
                color: .primary,
                source: .personalRecord
            ))
        }

        // Quality score delta vs EWMA (needs 5+ workouts)
        if workoutCount >= 5, let score = qualityScore, let qService = qualityScoreService {
            let aggregate = qService.computeAggregateScore(workouts: allWorkouts)
            let delta = score.overallScore - aggregate.ewmaOverall
            if abs(delta) > 5 {
                let direction = delta > 0 ? "above" : "below"
                candidates.append(CoachingInsight(
                    priority: 3,
                    title: "Quality \(delta > 0 ? "Up" : "Down")",
                    detail: String(format: "%.0f/100 — %.0f pts %@ your average", score.overallScore, abs(delta), direction),
                    icon: delta > 0 ? "arrow.up.right" : "arrow.down.right",
                    color: delta > 0 ? .success : .warning,
                    source: .qualityScore
                ))
            }
        }

        // Overload trends for exercises in this workout (needs 10+ workouts)
        if workoutCount >= 10 {
            let workoutExerciseIds = Set(workout.exercises.map(\.exercise.id))
            let relevantTrends = overloadTrends.filter { workoutExerciseIds.contains($0.exerciseId) }
            if let best = relevantTrends.filter({ $0.trendStatus == .progressing }).max(by: { $0.slopePerWeek < $1.slopePerWeek }) {
                candidates.append(CoachingInsight(
                    priority: 5,
                    title: "\(best.exerciseName) Trending Up",
                    detail: String(format: "+%.1f kg/week over recent weeks", best.slopePerWeek),
                    icon: "arrow.up.right",
                    color: .success,
                    source: .overloadTrend
                ))
            }
        }

        // Deload-specific bullet (replaces volume delta during deload)
        if workout.isDeload {
            candidates.append(CoachingInsight(
                priority: 4,
                title: "Deload Session",
                detail: "Intentional recovery — reduced volume as planned",
                icon: "heart.circle.fill",
                color: .success,
                source: .recovery
            ))
        }

        // Volume delta vs 30-day average (needs 5+ workouts, skip during deload)
        if !workout.isDeload && workoutCount >= 5 {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let recentWorkouts = completedWorkouts.filter {
                ($0.completedAt ?? .distantPast) >= thirtyDaysAgo && !$0.isDeload
            }
            if !recentWorkouts.isEmpty {
                let avgVolume = recentWorkouts.map { $0.totalVolume(bodyWeightKg: bodyWeightKg) }.reduce(0, +) / Double(recentWorkouts.count)
                if avgVolume > 0 {
                    let deltaPercent = ((totalVolume - avgVolume) / avgVolume) * 100
                    if abs(deltaPercent) > 10 {
                        let direction = deltaPercent > 0 ? "above" : "below"
                        candidates.append(CoachingInsight(
                            priority: 6,
                            title: "Volume \(deltaPercent > 0 ? "Up" : "Down")",
                            detail: String(format: "%.0f%% %@ your 30-day average", abs(deltaPercent), direction),
                            icon: deltaPercent > 0 ? "flame.fill" : "arrow.down",
                            color: deltaPercent > 0 ? .primary : .info,
                            source: .volumeDelta
                        ))
                    }
                }
            }
        }

        // ACWR warning (needs 19+ workouts)
        if workoutCount >= 19, let load = trainingLoad {
            if load.loadZone == .danger || load.loadZone == .caution {
                candidates.append(CoachingInsight(
                    priority: 2,
                    title: "High Training Load",
                    detail: String(format: "ACWR at %.2f — consider reducing volume next session", load.acwr),
                    icon: "exclamationmark.triangle.fill",
                    color: load.loadZone == .danger ? .danger : .warning,
                    source: .acwr
                ))
            } else if load.loadZone == .underTraining {
                candidates.append(CoachingInsight(
                    priority: 7,
                    title: "Low Training Load",
                    detail: String(format: "ACWR at %.2f — room to push harder", load.acwr),
                    icon: "arrow.up.circle",
                    color: .info,
                    source: .acwr
                ))
            }
        }

        // Recovery hint (needs 19+ workouts)
        if workoutCount >= 19 {
            let fatigued = recoveryPatterns.filter { $0.recoveryStatus == .fatigued }
            let workoutMuscles = Set(workout.exercises.map { $0.exercise.primaryMuscleGroup.rawValue.lowercased() })
            let relevantFatigued = fatigued.filter { workoutMuscles.contains($0.muscleGroup.lowercased()) }
            if let first = relevantFatigued.first, let ready = first.readyToTrainDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                let dayName = formatter.string(from: ready)
                candidates.append(CoachingInsight(
                    priority: 8,
                    title: "Recovery Note",
                    detail: "\(first.muscleGroup.capitalized) will be ready again \(dayName)",
                    icon: "clock.arrow.circlepath",
                    color: .info,
                    source: .recovery
                ))
            }
        }

        // Similar session comparison bullet (C6, needs 10+ workouts)
        if workoutCount >= 10, let comparison = similarSession {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let dateStr = dateFormatter.string(from: comparison.matchDate)
            let volumeStr: String
            if abs(comparison.volumeDelta) > 1 {
                volumeStr = String(format: "%.0f%% %@ volume", abs(comparison.volumeDelta), comparison.volumeDelta > 0 ? "more" : "less")
            } else {
                volumeStr = "similar volume"
            }
            candidates.append(CoachingInsight(
                priority: 9,
                title: "Similar to \(dateStr)",
                detail: String(format: "%.0f%% match — %@", comparison.similarity * 100, volumeStr),
                icon: "arrow.triangle.2.circlepath",
                color: .info,
                source: .sessionComparison
            ))
        }

        // Sort by priority, take top 3
        let bullets = Array(candidates.sorted { $0.priority < $1.priority }.prefix(3))

        // Optionally enhance with Apple Intelligence
        let enhancedBullets: [CoachingInsight]
        if let generator = insightGenerator {
            enhancedBullets = await generator.enhancePostWorkoutBullets(bullets)
        } else {
            enhancedBullets = bullets
        }

        return PostWorkoutDebrief(
            workoutName: workout.name,
            duration: duration,
            totalVolume: totalVolume,
            totalSets: totalSets,
            exerciseCount: exerciseCount,
            qualityScore: qualityScore,
            prsHit: prsHit,
            bullets: enhancedBullets,
            similarSession: similarSession
        )
    }

    // MARK: - Session Comparison (C6)

    private func findSimilarSession(
        workout: Workout,
        allWorkouts: [Workout],
        currentVector: WorkoutVector?,
        allVectors: [WorkoutVector],
        bodyWeightKg: Double
    ) -> SessionComparison? {
        guard let queryVec = currentVector else { return nil }
        let otherVectors = allVectors.filter { $0.workoutId != workout.id }
        guard !otherVectors.isEmpty else { return nil }

        let results = searchService.findSimilar(
            query: queryVec.dimensions,
            vectors: otherVectors.map(\.dimensions),
            topK: 1
        )

        guard let best = results.first, best.similarity >= 0.7 else { return nil }
        let matchedVector = otherVectors[best.index]
        guard let matchedWorkout = allWorkouts.first(where: { $0.id == matchedVector.workoutId }) else { return nil }

        let currentVolume = workout.totalVolume(bodyWeightKg: bodyWeightKg)
        let matchVolume = matchedWorkout.totalVolume(bodyWeightKg: bodyWeightKg)
        let volumeDelta = matchVolume > 0 ? ((currentVolume - matchVolume) / matchVolume) * 100 : 0

        let currentAvgWeight = averageWeight(workout)
        let matchAvgWeight = averageWeight(matchedWorkout)
        let intensityDelta = matchAvgWeight > 0 ? ((currentAvgWeight - matchAvgWeight) / matchAvgWeight) * 100 : 0

        return SessionComparison(
            matchDate: matchedWorkout.startedAt,
            matchName: matchedWorkout.name,
            similarity: best.similarity,
            volumeDelta: volumeDelta,
            intensityDelta: intensityDelta
        )
    }

    private func averageWeight(_ workout: Workout) -> Double {
        let weights = workout.exercises.flatMap(\.sets).filter(\.isCompleted).compactMap(\.weight)
        guard !weights.isEmpty else { return 0 }
        return weights.reduce(0, +) / Double(weights.count)
    }

    // MARK: - Weekly Digest (C2)

    public func generateWeeklyDigest(
        workouts: [Workout],
        overloadTrends: [OverloadTrend],
        bodyWeightKg: Double
    ) -> WeeklyDigest? {
        let completed = workouts.filter { $0.completedAt != nil }
        guard completed.count >= 5 else { return nil }

        let calendar = Calendar.current
        let now = Date()
        guard let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart),
              let priorWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: lastWeekStart) else {
            return nil
        }

        let thisWeek = completed.filter { ($0.completedAt ?? .distantPast) >= thisWeekStart }
        let lastWeek = completed.filter {
            let d = $0.completedAt ?? .distantPast
            return d >= lastWeekStart && d < thisWeekStart
        }
        let priorWeek = completed.filter {
            let d = $0.completedAt ?? .distantPast
            return d >= priorWeekStart && d < lastWeekStart
        }

        guard !lastWeek.isEmpty else { return nil }

        // Compare two complete weeks (last vs prior) — avoids partial-week distortion
        let lastVolume = lastWeek.reduce(0.0) { $0 + $1.totalVolume(bodyWeightKg: bodyWeightKg) }
        let priorVolume = priorWeek.reduce(0.0) { $0 + $1.totalVolume(bodyWeightKg: bodyWeightKg) }
        let volumeDelta = priorVolume > 0 ? ((lastVolume - priorVolume) / priorVolume) * 100 : 0

        let thisWeekPRs = thisWeek.flatMap(\.exercises).flatMap(\.sets).filter(\.isPersonalRecord).count

        // Pick top insight
        let topInsight: CoachingInsight
        let progressingTrends = overloadTrends.filter { $0.trendStatus == .progressing }
        if let best = progressingTrends.max(by: { $0.slopePerWeek < $1.slopePerWeek }) {
            topInsight = CoachingInsight(
                priority: 1,
                title: "\(best.exerciseName) Gaining",
                detail: String(format: "+%.1f kg/week over recent weeks", best.slopePerWeek),
                icon: "arrow.up.right",
                color: .success,
                source: .overloadTrend
            )
        } else if abs(volumeDelta) > 20 {
            topInsight = CoachingInsight(
                priority: 2,
                title: "Volume \(volumeDelta > 0 ? "Up" : "Down")",
                detail: String(format: "%.0f%% vs last week", abs(volumeDelta)),
                icon: volumeDelta > 0 ? "flame.fill" : "arrow.down",
                color: volumeDelta > 0 ? .primary : .info,
                source: .volumeDelta
            )
        } else {
            topInsight = CoachingInsight(
                priority: 3,
                title: "Consistent Training",
                detail: "\(thisWeek.count) workouts this week",
                icon: "checkmark.circle",
                color: .success,
                source: .adherence
            )
        }

        return WeeklyDigest(
            weekStart: thisWeekStart,
            topInsight: topInsight,
            workoutsThisWeek: thisWeek.count,
            workoutsLastWeek: lastWeek.count,
            volumeDeltaPercent: volumeDelta,
            qualityTrend: 0, // Quality score comparison deferred
            prsThisWeek: thisWeekPRs
        )
    }
}
