import Foundation
import Testing
@testable import StrengthTrackerShared

@Suite("Analytics makeover regression coverage")
@MainActor
struct AnalyticsMakeoverTests {
    private let now = Calendar.mondayStart.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!
    private func session(_ exercise: Exercise, date: Date, weight: Double = 50, sets: Int = 4, interval: Double = 120, rpe: Double? = nil) -> Workout {
        AnalyticsTestHelpers.makeWorkout(exercises: [AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise,
            sets: (0..<sets).map { AnalyticsTestHelpers.makeCompletedSet(order: $0 + 1, weight: weight, reps: 5, rpe: rpe, completedAt: date.addingTimeInterval(Double($0) * interval)) })],
            startedAt: date, completedAt: date.addingTimeInterval(3600))
    }
    private func qualityService() -> WorkoutQualityScoreService {
        WorkoutQualityScoreService(workoutRepository: MockWorkoutRepository(), muscleBalanceService: MuscleBalanceService(), healthKitService: MockHealthKitService(), userPreferencesService: UserPreferencesService())
    }

    @Test("An extra rep never reduces e1RM within its supported range")
    func monotonicEstimator() {
        for reps in 1..<15 {
            #expect(AnalyticsCalculations.calculateOneRM(weight: 100, reps: reps + 1) > AnalyticsCalculations.calculateOneRM(weight: 100, reps: reps))
        }
    }

    @Test("Regression uses elapsed calendar weeks and recognizes small-lift gains")
    func sparseProgress() throws {
        let ex = AnalyticsTestHelpers.makeExercise(name: "Small lift")
        let history = (0..<5).map { i in session(ex, date: now.addingTimeInterval(Double(i - 4) * 14 * 86400), weight: 10 + Double(i) * 0.2) }
        let trend = try #require(OverloadTrackingService.computeOverloadTrends(workouts: history, bodyWeightKg: 70, now: now).first)
        #expect(abs(trend.slopePerWeek - 0.1 * (1 + 5.0 / 30)) < 0.0001)
        #expect(trend.trendStatus == .progressing)
        #expect(trend.weeklyE1RMs.count == 5)
        let stale = try #require(OverloadTrackingService.computeOverloadTrends(workouts: history, bodyWeightKg: 70, now: now.addingTimeInterval(60 * 86400)).first)
        #expect(stale.trendStatus == .inactive)
    }

    @Test("Later workouts do not change a historical score")
    func causalQuality() {
        let ex = AnalyticsTestHelpers.makeExercise()
        let history = (0..<6).map { session(ex, date: now.addingTimeInterval(Double($0 - 6) * 7 * 86400)) }
        let target = history.last!
        let before = qualityService().computeScore(for: target, history: history)
        let future = session(ex, date: now, weight: 200, sets: 12)
        let after = qualityService().computeScore(for: target, history: history + [future])
        #expect(before.overallScore == after.overallScore)
        #expect(before.volumeScore == after.volumeScore)
        #expect(before.intensityScore == after.intensityScore)
        #expect(before.balanceScore == after.balanceScore)
    }

    @Test("The headline equals the four visible components and EWMA preserves that identity")
    func qualityIdentity() {
        let ex = AnalyticsTestHelpers.makeExercise()
        let history = (0..<7).map { session(ex, date: Date().addingTimeInterval(Double($0 - 8) * 3 * 86400), weight: 45 + Double($0)) }
        let service = qualityService()
        let last = service.computeScore(for: history.last!, history: history)
        #expect(abs(last.overallScore - (last.volumeScore + last.intensityScore + last.balanceScore + last.consistencyScore) / 4) < 0.00001)
        let aggregate = service.computeAggregateScore(workouts: history)
        #expect(!aggregate.provisional)
        #expect(aggregate.workoutsIncluded < history.count)
        #expect(abs(aggregate.ewmaOverall - (aggregate.ewmaVolume + aggregate.ewmaIntensity + aggregate.ewmaBalance + aggregate.ewmaConsistency) / 4) < 0.00001)
        #expect(AnalyticsCalculations.ewma(values: [70, 80], lambda: 0.3).last == 73)
    }

    @Test("Different exercise rest lengths do not penalize consistent within-block rhythm")
    func restBlocks() {
        let first = AnalyticsTestHelpers.makeExercise(name: "Heavy")
        let second = AnalyticsTestHelpers.makeExercise(name: "Accessory")
        var workout = session(first, date: now, interval: 240)
        workout.exercises += session(second, date: now.addingTimeInterval(1800), interval: 60).exercises
        let score = qualityService().computeScore(for: workout, history: [])
        #expect(score.consistencyScore == 100)
        #expect(score.isProvisional)
    }

    @Test("Logging RPE alone does not change the training load index")
    func loadIsIndependentOfLoggingCoverage() throws {
        let ex = AnalyticsTestHelpers.makeExercise()
        let history = (0..<10).map { session(ex, date: now.addingTimeInterval(Double($0 - 10) * 3 * 86400)) }
        var withRPE = history
        for w in withRPE.indices { for e in withRPE[w].exercises.indices { for s in withRPE[w].exercises[e].sets.indices { withRPE[w].exercises[e].sets[s].rpe = 8 } } }
        let best = [ex.id: 70.0]
        let first = try #require(TrainingLoadService.computeTrainingLoad(bodyWeightKg: 70, workouts: history, bestE1RM: best, now: now))
        let second = try #require(TrainingLoadService.computeTrainingLoad(bodyWeightKg: 70, workouts: withRPE, bestE1RM: best, now: now))
        #expect(first.acwr == second.acwr)
        #expect(first.acuteLoad == second.acuteLoad)
        let tomorrow = try #require(TrainingLoadService.computeTrainingLoad(bodyWeightKg: 70, workouts: history, bestE1RM: best, now: now.addingTimeInterval(86400)))
        #expect(tomorrow.acuteLoad < first.acuteLoad)
    }

    @Test("Recovery sums same-session exercises independent of exercise order")
    func recoveryAggregation() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = RecoveryEstimationService(workoutRepository: MockWorkoutRepository(), feedback: RecoveryFeedbackStore(defaults: defaults))
        let ex = AnalyticsTestHelpers.makeExercise(primaryMuscleGroup: .chest, secondaryMuscleGroups: [])
        let other = AnalyticsTestHelpers.makeExercise(name: "Fly", primaryMuscleGroup: .chest, secondaryMuscleGroups: [])
        var workout = session(ex, date: now.addingTimeInterval(-86400), sets: 3)
        workout.exercises += session(other, date: workout.trainingDate, sets: 4).exercises
        let a = try #require(try await service.computeRecoveryPatterns(workouts: [workout], bodyWeightKg: 70, now: now).first)
        workout.exercises.reverse()
        let b = try #require(try await service.computeRecoveryPatterns(workouts: [workout], bodyWeightKg: 70, now: now).first)
        #expect(a.exposureCredits == 7)
        #expect(a.averageRecoveryHours == b.averageRecoveryHours)
        #expect(a.readyToTrainDate == b.readyToTrainDate)
    }

    @Test("Tiny indirect exposure cannot reset a full recovery timer")
    func tinyIndirectExposure() async throws {
        let ex = AnalyticsTestHelpers.makeExercise(secondaryMuscleGroups: [.triceps, .shoulders, .forearms])
        let service = RecoveryEstimationService(workoutRepository: MockWorkoutRepository(), feedback: RecoveryFeedbackStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let patterns = try await service.computeRecoveryPatterns(workouts: [session(ex, date: now, sets: 1)], bodyWeightKg: 70, now: now)
        #expect(patterns.map(\.muscleGroup) == ["chest"])
    }

    @Test("Check-ins are bounded and one daily answer cannot overwhelm the prior")
    func recoveryFeedback() {
        let store = RecoveryFeedbackStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for _ in 0..<20 { store.record(muscle: "chest", feelsReady: true, hoursSince: 12, predictedHours: 64, now: now) }
        #expect(store.count(for: "chest", asOf: now) == 1)
        #expect(store.multiplier(for: "chest", asOf: now) > 0.95)
        #expect(store.multiplier(for: "chest", asOf: now) < 1)
    }

    @Test("Coverage exposes direct and indirect weekly sets separately")
    func coverageUnits() throws {
        let ex = AnalyticsTestHelpers.makeExercise(secondaryMuscleGroups: [.triceps, .shoulders])
        let result = MuscleBalanceService().analyzeBalance(workouts: [session(ex, date: now, sets: 8)], bodyWeightKg: 70, now: now)
        let chest = try #require(result.muscleGroupVolumes.first { $0.muscleGroup == "chest" })
        let triceps = try #require(result.muscleGroupVolumes.first { $0.muscleGroup == "triceps" })
        #expect(chest.directWeeklySets == 2)
        #expect(triceps.directWeeklySets == 0)
        #expect(triceps.indirectWeeklySets == 0.5)
    }

    @Test("Workout groups and fingerprints preserve duplicate display labels")
    func stableGroups() throws {
        let ex = AnalyticsTestHelpers.makeExercise()
        let service = WorkoutArchetypeService(searchService: VectorSearchService())
        var workouts = (0..<12).map { session(ex, date: Date().addingTimeInterval(Double(-$0) * 86400)) }
        let a = UUID(), b = UUID()
        for i in workouts.indices { workouts[i].templateId = i % 2 == 0 ? a : b }
        let groups = service.cluster(vectors: [], workouts: workouts, bodyWeightKg: 70)
        let reversed = service.cluster(vectors: [], workouts: workouts.reversed(), bodyWeightKg: 70)
        #expect(Set(groups.map(\.id)) == Set([a, b]))
        #expect(Set(groups.map(\.id)) == Set(reversed.map(\.id)))
        #expect(groups.reduce(0) { $0 + $1.memberWorkoutIds.count } == 12)
    }

    @Test("Hold feed never contains encouragement or population volume-limit praise")
    func compatibleHighlights() async {
        let verdict = TrainingVerdict(kind: .hold, urgency: 0, reasons: [], signals: [], action: "Hold loads steady", since: now, computedAt: now, isActiveDeload: false)
        let trend = OverloadTrend(exerciseId: UUID(), exerciseName: "Hip Thrust", weeklyE1RMs: [], slopePerWeek: 1.4, trendStatus: .progressing, overloadIndex: 1)
        let highlights = await TemplateInsightGenerator().generateHighlights(trainingLoad: nil, overloadTrends: [trend], deloadRecommendation: nil, trainingDrift: nil, trainingPhase: nil, recoveryPatterns: [], optimalVolumes: [], verdict: verdict)
        #expect(highlights.count == 1)
        #expect(highlights.first?.isAction == true)
        #expect(highlights.first?.topic == "verdict")
        #expect(highlights.first?.validUntil == now.addingTimeInterval(6 * 3600))
    }

    @Test("Volume response has a scoped registered tool and honest empty result")
    func volumeTool() async throws {
        let service = WorkoutAnalyticsService(analyticsRepository: MockAnalyticsRepository(), workoutRepository: MockWorkoutRepository(), exerciseRepository: MockExerciseRepository(), vectorizer: WorkoutVectorizer(), searchService: VectorSearchService(), plateauService: PlateauDetectionService(), muscleBalanceService: MuscleBalanceService(), recommendationService: ExerciseRecommendationService())
        let tool = GetVolumeResponseTool(analyticsService: service)
        let result = try await tool.call(argumentsJSON: "{\"muscle_group\":\"chest\",\"lookback_weeks\":52}")
        #expect(result.outputForModel.contains("insufficient_data"))
        #expect(result.outputForModel.contains("observational"))
    }

    @Test("Training state uses actual complete periods and marks missing history")
    func trainingState() {
        let empty = TrainingStateService.summarize(workouts: [], now: now)
        #expect(empty.kind == .building)
        #expect(empty.weeks.count == 8)
        #expect(empty.weeks.allSatisfy { $0.sessions == 0 })
        let ex = AnalyticsTestHelpers.makeExercise()
        let history = (1...8).map { session(ex, date: now.addingTimeInterval(Double(-$0) * 7 * 86400)) }
        let state = TrainingStateService.summarize(workouts: history, now: now)
        #expect(state.current.weeklySets == state.previous.weeklySets)
        #expect(state.kind == .usual)
    }
    @Test("Widget expiry and legacy decoding cannot be renewed by an unrelated timestamp")
    func widgetExpiry() throws {
        let highlight = WidgetHighlight(icon: "arrow.up", title: "Progress", detail: "Observed", color: "green", destination: "strengthtracker://analytics?topic=progress", validUntil: now.addingTimeInterval(3600))
        let data = WidgetData(lastWorkoutDate: nil, lastWorkoutName: nil, lastWorkoutExerciseCount: 0, lastWorkoutDuration: nil, weeklyWorkoutCount: 3, weeklyGoal: 3, currentStreak: 1, totalWorkoutsAllTime: 100, updatedAt: now.addingTimeInterval(86400), highlights: [highlight], weeklyQualityScore: 73, analyticsGeneratedAt: now)
        let decoded = try JSONDecoder().decode(WidgetData.self, from: JSONEncoder().encode(data))
        #expect(decoded.visibleHighlights(at: now).count == 1)
        #expect(decoded.visibleHighlights(at: now.addingTimeInterval(3600)).isEmpty)
        #expect(decoded.measuredQuality(at: now) == 73)
        #expect(decoded.measuredQuality(at: now.addingTimeInterval(86400)) == nil)
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        old.removeValue(forKey: "analyticsGeneratedAt")
        old["highlights"] = [["id": UUID().uuidString, "icon": "arrow.up", "title": "Old", "detail": "Old detail", "color": "green"]]
        let legacy = try JSONDecoder().decode(WidgetData.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(legacy.highlights.count == 1)
        #expect(legacy.visibleHighlights(at: now).isEmpty)
        #expect(legacy.measuredQuality(at: now) == nil)
    }

    @Test("Notable sessions compare matching routines and ignore ordinary variation")
    func notableSessions() {
        let ex = AnalyticsTestHelpers.makeExercise()
        let history = (1...5).map { session(ex, date: now.addingTimeInterval(Double(-$0) * 7 * 86400), sets: 4) }
        #expect(TrainingStateService.notableSessions(workouts: history, now: now).isEmpty)
        let reduced = session(ex, date: now, sets: 2)
        let changes = TrainingStateService.notableSessions(workouts: history + [reduced], now: now)
        #expect(changes.count == 1)
        #expect(changes.first?.workout.id == reduced.id)
        #expect(changes.first?.detail.contains("50% fewer") == true)
        let other = session(AnalyticsTestHelpers.makeExercise(), date: now, sets: 2)
        #expect(TrainingStateService.notableSessions(workouts: history + [other], now: now).isEmpty)
    }

    @Test("Noisy slopes remain unclear while stable repeated loads mean maintaining")
    func progressionUncertainty() throws {
        let ex = AnalyticsTestHelpers.makeExercise()
        let flat = (0..<8).map { session(ex, date: now.addingTimeInterval(Double($0 - 7) * 7 * 86400)) }
        let stable = try #require(OverloadTrackingService.computeOverloadTrends(workouts: flat, bodyWeightKg: 70, now: now).first)
        #expect(stable.trendStatus == .plateau)
        #expect(stable.statusLabel == "Maintaining")
        let noisy = (0..<8).map { session(ex, date: now.addingTimeInterval(Double($0 - 7) * 7 * 86400), weight: $0 % 2 == 0 ? 40 : 60) }
        let uncertain = try #require(OverloadTrackingService.computeOverloadTrends(workouts: noisy, bodyWeightKg: 70, now: now).first)
        #expect(uncertain.trendStatus == .uncertain)
        #expect((uncertain.slopeMargin ?? 0) > abs(uncertain.slopePerWeek))
    }

    @Test("Time comparisons use score points, matched routines and proper morning boundaries")
    func matchedTime() throws {
        let ex = AnalyticsTestHelpers.makeExercise()
        var history: [Workout] = []
        var scores: [UUID: WorkoutQualityScore] = [:]
        for i in 0..<12 {
            let day = Calendar.current.date(byAdding: .day, value: -i - 1, to: now)!
            let date = Calendar.current.date(bySettingHour: i % 2 == 0 ? 6 : 17, minute: 0, second: 0, of: day)!
            let workout = session(ex, date: date)
            let value = i % 2 == 0 ? 80.0 : 70.0
            history.append(workout)
            scores[workout.id] = WorkoutQualityScore(workoutId: workout.id, overallScore: value, volumeScore: value, intensityScore: value, balanceScore: value, consistencyScore: value)
        }
        let result = try #require(ChangePointDetectionService().analyzeTimeOfDay(workouts: history, qualityScores: scores, now: now))
        #expect(result.bestWindow.hasPrefix("Morning"))
        #expect(result.message.contains("10 points"))
        #expect(result.bestCount == 6 && result.worstCount == 6)
        for i in history.indices where i % 2 == 1 { history[i].templateId = UUID() }
        #expect(ChangePointDetectionService().analyzeTimeOfDay(workouts: history, qualityScores: scores, now: now) == nil)
    }

    @Test("Quality cache invalidates after a backdated correction but ignores later training")
    func qualityCacheHistory() {
        let service = qualityService()
        let ex = AnalyticsTestHelpers.makeExercise()
        let history = (1...6).map { session(ex, date: now.addingTimeInterval(Double(-$0) * 7 * 86400)) }
        let target = session(ex, date: now)
        let original = service.computeScore(for: target, history: history)
        let later = service.computeScore(for: target, history: history + [session(ex, date: now.addingTimeInterval(86400), weight: 200)])
        #expect(original.id == later.id)
        var edited = history
        edited[0].exercises[0].sets[0].weight = 200
        let corrected = service.computeScore(for: target, history: edited)
        #expect(original.id != corrected.id)
        #expect(corrected.intensityScore < original.intensityScore)
    }

    @Test("An unchanged revision expires on the clock and recomputes decayed load")
    func snapshotClock() async throws {
        let repo = MockWorkoutRepository()
        let ex = AnalyticsTestHelpers.makeExercise()
        repo.seed((1...10).map { session(ex, date: now.addingTimeInterval(Double(-$0) * 3 * 86400)) })
        let revision = DataRevision()
        let service = WorkoutAnalyticsService(analyticsRepository: MockAnalyticsRepository(), workoutRepository: repo, exerciseRepository: MockExerciseRepository(), vectorizer: WorkoutVectorizer(), searchService: VectorSearchService(), plateauService: PlateauDetectionService(), muscleBalanceService: MuscleBalanceService(), recommendationService: ExerciseRecommendationService(), dataRevision: revision)
        let first = try await service.generateInsights(now: now)
        let cached = try await service.generateInsights(now: now.addingTimeInterval(30))
        #expect(cached.generatedAt == first.generatedAt)
        let later = try await service.generateInsights(now: now.addingTimeInterval(86400))
        #expect(later.generatedAt > first.generatedAt)
        let firstLoad = try #require(first.trainingLoad)
        let laterLoad = try #require(later.trainingLoad)
        #expect(laterLoad.acuteLoad < firstLoad.acuteLoad)
        #expect(revision.value == 0)
    }

    @Test("Model migration re-elects derived e1RM records once and preserves manual records")
    func derivedRecordMigration() async throws {
        let repo = InMemoryWorkoutRepository()
        let records = InMemoryPersonalRecordRepository()
        let ex = AnalyticsTestHelpers.makeExercise()
        _ = try await repo.save(session(ex, date: now, weight: 100))
        let manual = PersonalRecord(id: UUID(), exerciseId: ex.id, recordType: .maxWeight, value: 140, setId: nil, achievedAt: now)
        _ = try await records.save(manual)
        let prs = PersonalRecordService(personalRecordRepository: records, workoutRepository: repo)
        let revision = DataRevision()
        let finalizer = WorkoutFinalizer(workoutRepository: repo, analyticsRepository: MockAnalyticsRepository(), analyticsService: nil, personalRecordService: prs, qualityScoreService: nil, healthKitService: MockHealthKitService(), webhookService: nil, widgetRefresh: nil, bodyWeightProvider: nil, dataRevision: revision)
        let suite = "AnalyticsMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(await finalizer.migrateAnalyticsModelIfNeeded(defaults: defaults))
        let migrated = try await records.fetchForExercise(ex.id)
        #expect(migrated.contains { $0.id == manual.id })
        #expect(migrated.contains { $0.recordType == .estimatedOneRepMax && abs($0.value - 116.6666667) < 0.001 })
        #expect(!(await finalizer.migrateAnalyticsModelIfNeeded(defaults: defaults)))
        #expect(revision.value == 1)
    }

}
