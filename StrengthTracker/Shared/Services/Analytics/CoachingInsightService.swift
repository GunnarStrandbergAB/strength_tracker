import Foundation

/// Central "knowledgeable training partner brain" that produces contextual coaching
/// insights for post-workout, pre-workout, and inline contexts.
/// Stateless. Prioritizes, deduplicates, and routes insights.
@MainActor
public final class CoachingInsightService: Sendable {

    private let searchService: VectorSearchService
    private let qualityScoreService: WorkoutQualityScoreService?
    private let insightGenerator: (any InsightTextGenerating)?
    /// Display unit for slope strings (defaults to kg for tests).
    private let weightUnit: @MainActor () -> WeightUnit

    public init(
        searchService: VectorSearchService,
        qualityScoreService: WorkoutQualityScoreService? = nil,
        insightGenerator: (any InsightTextGenerating)? = nil,
        weightUnit: @escaping @MainActor () -> WeightUnit = { .kg }
    ) {
        self.searchService = searchService
        self.qualityScoreService = qualityScoreService
        self.insightGenerator = insightGenerator
        self.weightUnit = weightUnit
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
        bodyWeightKg: Double,
        verdict: TrainingVerdict? = nil
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
                    detail: "\(AnalyticsFormatting.slope(kgPerWeek: best.slopePerWeek, unit: weightUnit())) over recent weeks",
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

        // Load direction (needs 19+ workouts): one bullet, derived from the shared
        // verdict so it can never contradict the analytics screens.
        if workoutCount >= AnalyticsFeatureGate.threshold(for: .advancedInsights) {
            if let verdict {
                switch verdict.kind {
                case .deload where !verdict.isActiveDeload:
                    candidates.append(CoachingInsight(
                        priority: 2,
                        title: "Deload Recommended",
                        detail: verdict.action,
                        icon: "exclamationmark.triangle.fill",
                        color: .warning,
                        source: .acwr
                    ))
                case .hold where !verdict.isActiveDeload:
                    candidates.append(CoachingInsight(
                        priority: 4,
                        title: "Hold Steady",
                        detail: verdict.action,
                        icon: "pause.circle",
                        color: .info,
                        source: .acwr
                    ))
                case .progress:
                    if let load = trainingLoad, load.loadZone == .underTraining {
                        candidates.append(CoachingInsight(
                            priority: 7,
                            title: "Room to Push",
                            detail: "Training load is below your baseline; add a set or a little weight next session",
                            icon: "arrow.up.circle",
                            color: .info,
                            source: .acwr
                        ))
                    }
                default:
                    break
                }
            } else if let load = trainingLoad {
                // No verdict available: descriptive load note only.
                switch load.loadZone {
                case .danger, .caution:
                    candidates.append(CoachingInsight(
                        priority: 2,
                        title: "Training Load \(AnalyticsFormatting.loadZoneLabel(load.loadZone))",
                        detail: AnalyticsFormatting.loadZoneDescription(load.loadZone, acwr: load.acwr, activeDeload: workout.isDeload),
                        icon: "exclamationmark.triangle.fill",
                        color: load.loadZone == .danger ? .danger : .warning,
                        source: .acwr
                    ))
                case .underTraining:
                    candidates.append(CoachingInsight(
                        priority: 7,
                        title: "Training Load Low",
                        detail: AnalyticsFormatting.loadZoneDescription(load.loadZone, acwr: load.acwr, activeDeload: workout.isDeload),
                        icon: "arrow.up.circle",
                        color: .info,
                        source: .acwr
                    ))
                case .optimal:
                    break
                }
            }
        }

        // Recovery hint (needs 19+ workouts)
        if workoutCount >= 19 {
            let fatigued = recoveryPatterns.filter { $0.recoveryStatus == .fatigued && !$0.isJustTrained }
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

    /// Compares the last complete Monday-start week with the one before it.
    /// The verdict, when present, owns the top insight so the digest never says
    /// "gaining" while the analytics screens say "deload".
    public func generateWeeklyDigest(
        workouts: [Workout],
        overloadTrends: [OverloadTrend],
        bodyWeightKg: Double,
        verdict: TrainingVerdict? = nil,
        now: Date = Date(),
        calendar: Calendar = .mondayStart
    ) -> WeeklyDigest? {
        let completed = workouts.filter { $0.completedAt != nil }
        guard completed.count >= AnalyticsFeatureGate.threshold(for: .weeklyDigest) else { return nil }

        let window = WorkoutWeekWindow.split(completed, now: now, calendar: calendar)
        let thisWeek = window.current
        let lastWeek = window.previous
        let priorWeek = window.prior
        guard !lastWeek.isEmpty else { return nil }

        // Compare two complete weeks (last vs prior) — avoids partial-week distortion
        let lastVolume = lastWeek.reduce(0.0) { $0 + $1.totalVolume(bodyWeightKg: bodyWeightKg) }
        let priorVolume = priorWeek.reduce(0.0) { $0 + $1.totalVolume(bodyWeightKg: bodyWeightKg) }
        let volumeDelta = priorVolume > 0 ? ((lastVolume - priorVolume) / priorVolume) * 100 : 0

        let prsThisWeek = thisWeek.flatMap(\.exercises).flatMap(\.sets).filter(\.isPersonalRecord).count
        let prsLastWeek = lastWeek.flatMap(\.exercises).flatMap(\.sets).filter(\.isPersonalRecord).count

        // Pick top insight
        let topInsight: CoachingInsight
        let progressingTrends = overloadTrends.filter { $0.trendStatus == .progressing }
        if let verdict, verdict.kind == .deload, !verdict.isActiveDeload {
            topInsight = CoachingInsight(
                priority: 1,
                title: "Deload Recommended",
                detail: verdict.action,
                icon: "exclamationmark.triangle.fill",
                color: .warning,
                source: .acwr
            )
        } else if let verdict, verdict.isActiveDeload {
            topInsight = CoachingInsight(
                priority: 1,
                title: "Deload In Progress",
                detail: "Intentional recovery week: reduced volume and intensity as planned",
                icon: "heart.circle.fill",
                color: .success,
                source: .recovery
            )
        } else if let best = progressingTrends.max(by: { $0.slopePerWeek < $1.slopePerWeek }) {
            topInsight = CoachingInsight(
                priority: 1,
                title: "\(best.exerciseName) Gaining",
                detail: "\(AnalyticsFormatting.slope(kgPerWeek: best.slopePerWeek, unit: weightUnit())) over recent weeks",
                icon: "arrow.up.right",
                color: .success,
                source: .overloadTrend
            )
        } else if abs(volumeDelta) > 20 {
            topInsight = CoachingInsight(
                priority: 2,
                title: "Volume \(volumeDelta > 0 ? "Up" : "Down")",
                detail: "\(AnalyticsFormatting.percentDelta(volumeDelta)) vs prior week",
                icon: volumeDelta > 0 ? "flame.fill" : "arrow.down",
                color: volumeDelta > 0 ? .primary : .info,
                source: .volumeDelta
            )
        } else {
            topInsight = CoachingInsight(
                priority: 3,
                title: "Consistent Training",
                detail: "\(lastWeek.count) workout\(lastWeek.count == 1 ? "" : "s") last week",
                icon: "checkmark.circle",
                color: .success,
                source: .adherence
            )
        }

        return WeeklyDigest(
            weekStart: window.previousWeekStart,
            topInsight: topInsight,
            workoutsThisWeek: thisWeek.count,
            workoutsLastWeek: lastWeek.count,
            volumeDeltaPercent: volumeDelta,
            qualityTrend: 0, // Quality score comparison deferred
            prsThisWeek: prsThisWeek,
            prsLastWeek: prsLastWeek
        )
    }
}
