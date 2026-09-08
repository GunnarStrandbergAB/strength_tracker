import Foundation

/// Detailed reads share the exact services/calculators used by Analytics and exercise history.
/// Fetch full history first, calculate, then filter/page the output — never page the baseline.
@MainActor
public final class DetailedAnalyticsTool: AITool {
    public enum Kind: String, CaseIterable, Sendable {
        case quality = "get_workout_quality", load = "get_training_load", progress = "get_exercise_progress"
        case coverage = "get_muscle_coverage", patterns = "get_training_patterns", recovery = "get_recovery_status"
        case plan = "get_plan_progress"
    }
    private let kind: Kind
    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let plans: any ProgressionPlanRepository
    private let analytics: WorkoutAnalyticsService
    private let quality: WorkoutQualityScoreService
    private let planAnalytics: PlanAnalyticsService
    private let bodyWeight: BodyWeightProvider
    public init(kind: Kind, workouts: any WorkoutRepository, exercises: any ExerciseRepository, plans: any ProgressionPlanRepository,
        analytics: WorkoutAnalyticsService, quality: WorkoutQualityScoreService, planAnalytics: PlanAnalyticsService, bodyWeight: BodyWeightProvider) {
        self.kind = kind; self.workouts = workouts; self.exercises = exercises; self.plans = plans
        self.analytics = analytics; self.quality = quality; self.planAnalytics = planAnalytics; self.bodyWeight = bodyWeight
    }
    public var name: String { kind.rawValue }
    public var description: String {
        switch kind {
        case .quality: return "Per-session quality, provisional reasons, baseline notes, full-history EWMA aggregate and dated history. Same absolute scoring model as Analytics. Optional workout_id."
        case .load: return "Full-history computed acute/chronic training load, ACWR, daily series and muscle ratios. Relative effort units, not kg volume; descriptive, not injury risk."
        case .progress: return "Exercise history: raw and three-observation median points, change over selected dates, deload flags, source workout IDs. exercise_id or exercise_name required. Metric must match exercise type."
        case .coverage: return "Weekly direct and estimated indirect working sets per muscle. Missing/unlogged weeks are unknown, not proof of zero training. Optional muscle_group."
        case .patterns: return "Current training state, previous/current four completed weeks, workout routines, best training time and notable sessions from the Analytics remake."
        case .recovery: return "Per-muscle recovery estimate, last exposure, predicted ready date, credited sets and personal feedback count. A heuristic estimate, not physiological measurement."
        case .plan: return "Progress of the active plan: adherence, exercise progress, weekly volume and expected completion; one workout is attributed to at most one session."
        }
    }
    public var parametersSchema: JSONValue {
        AIToolRegistry.objectSchema(properties: [
            "start_date": AIToolRegistry.stringSchema("Output window start yyyy-MM-dd; default 90 days ago"),
            "end_date": AIToolRegistry.stringSchema("Output window end yyyy-MM-dd inclusive; default today"),
            "offset": AIToolRegistry.integerSchema("Result offset, default 0"),
            "limit": AIToolRegistry.integerSchema("Maximum series/results per page 1–100, default 30"),
            "workout_id": AIToolRegistry.stringSchema("Optional workout UUID for quality"),
            "exercise_id": AIToolRegistry.stringSchema("Library exercise UUID for exercise progress"),
            "exercise_name": AIToolRegistry.stringSchema("Exact exercise name if ID unknown"),
            "metric": AIToolRegistry.enumSchema(ExerciseHistoryMetric.self),
            "target_reps": AIToolRegistry.integerSchema("Exact reps for Weight at reps; default 5"),
            "target_weight_kg": AIToolRegistry.numberSchema("Exact effective kg for Reps at weight; bodyweight load includes the app's bodyweight contribution"),
            "muscle_group": AIToolRegistry.enumSchema(MuscleGroup.self)
        ])
    }
    private struct Arguments: Decodable {
        var start_date: String?; var end_date: String?; var offset: Int?; var limit: Int?
        var workout_id: UUID?; var exercise_id: UUID?; var exercise_name: String?; var metric: ExerciseHistoryMetric?
        var target_reps: Int?; var target_weight_kg: Double?; var muscle_group: MuscleGroup?
    }
    public func call(argumentsJSON: String) async throws -> AIToolResult {
        let a = try decodeArguments(Arguments.self, from: argumentsJSON)
        let now = Date(), cal = Calendar.current
        let start = try parse(a.start_date) ?? cal.date(byAdding: .day, value: -90, to: now)!
        let end = try parse(a.end_date).map { cal.date(byAdding: .day, value: 1, to: $0)!.addingTimeInterval(-0.001) } ?? now
        guard start <= end else { throw AIToolError("start_date must precede end_date") }
        let offset = a.offset ?? 0, limit = a.limit ?? 30
        guard offset >= 0, (1...100).contains(limit) else { throw AIToolError("offset must be nonnegative; limit must be 1–100") }
        let history = try await workouts.fetchAll().filter { $0.completedAt != nil && $0.trainingDate <= now }
        let interval = DateInterval(start: start, end: end)
        let bw = bodyWeight.current
        var payload: [String: JSONValue] = [
            "tool": .string(name), "generated_at": try AIToolData.json(now),
            "output_window": .object(["start": try AIToolData.json(start), "end": try AIToolData.json(end)]),
            "source": .string("Shared app analytics services; full completed history before output filtering/pagination"),
            "history_workout_count": .number(Double(history.count)),
            "body_weight_kg": .number(bw), "body_weight_source": .string(bodyWeight.source.rawValue),
            "body_weight_provenance": .string("Current resolved bodyweight used retrospectively, not dated measurements"),
            "missing_data": .string("Absent observations are unknown. Availability/confidence must be respected."),
            "status": .string("available")
        ]
        func page(_ values: [JSONValue]) -> JSONValue {
            .object(["total": .number(Double(values.count)), "offset": .number(Double(offset)),
                "next_offset": offset + limit < values.count ? .number(Double(offset + limit)) : .null,
                "items": .array(Array(values.dropFirst(offset).prefix(limit)))])
        }
        payload["source_workouts"] = page(try history.sorted { $0.trainingDate > $1.trainingDate }.map { workout in
            .object(["id": .string(workout.id.uuidString), "date": try AIToolData.json(workout.trainingDate)])
        })
        switch kind {
        case .quality:
            payload["model_version"] = .number(Double(WorkoutQualityScore.modelVersion))
            payload["units"] = .string("0–100 score; trend is score points")
            payload["calculation_window"] = .string("All completed history; each session uses its eligible prior baseline; aggregate EWMA excludes provisional sessions once measured sessions exist; otherwise provisional scores are retained and labelled")
            payload["aggregate"] = history.isEmpty ? .null : try AIToolData.json(quality.computeAggregateScore(workouts: history))
            if history.count < 5 { payload["status"] = .string("building_baseline") }
            let observations = quality.computeHistory(workouts: history).filter {
                if let id = a.workout_id { return $0.id == id }
                return interval.contains($0.workout.trainingDate)
            }
            if a.workout_id != nil && observations.isEmpty { throw AIToolError("Completed workout not found") }
            payload["history"] = page(try observations.map { o in
                .object(["workout_id": .string(o.id.uuidString), "date": try AIToolData.json(o.workout.trainingDate),
                    "name": .string(o.workout.name), "score": try AIToolData.json(o.score),
                    "provisional": .bool(o.score.isProvisional), "smoothed_pillars": try AIToolData.json(o.aggregate)])
            })
        case .load:
            let bests = AnalyticsCalculations.buildBestE1RMMap(from: history.filter { !$0.isDeload }, bodyWeightKg: bw, asOf: now)
            let load = TrainingLoadService.computeTrainingLoad(bodyWeightKg: bw, workouts: history, bestE1RM: bests, now: now, historyDays: nil)
            payload["calculation_window"] = .string("Daily EWMA from first logged workout: acute alpha 2/8, chronic alpha 0.069; unlogged days contribute zero recorded load")
            payload["units"] = .string("Relative load: reps × effective load / reference e1RM; ACWR unitless. Muscle ratios use 7-day sum / (28-day sum / 4), not EWMA.")
            if let load {
                payload["acute"] = .number(load.acuteLoad); payload["chronic"] = .number(load.chronicLoad); payload["acwr"] = .number(load.acwr)
                payload["zone"] = .string(AnalyticsFormatting.loadZoneLabel(load.loadZone))
                payload["per_muscle_ratios"] = try AIToolData.json(load.perMuscleGroupACWR)
                payload["history"] = page(try (load.history ?? []).filter { interval.contains($0.date) }.map(AIToolData.json))
            } else { payload["status"] = .string("insufficient_data"); payload["requirement"] = .string("At least 8 workouts spanning 14 days"); payload["acwr"] = .null }
        case .progress:
            let catalog = try await exercises.fetchAll()
            let exercise: Exercise
            if let id = a.exercise_id, let e = catalog.first(where: { $0.id == id }) { exercise = e }
            else if let name = a.exercise_name { exercise = try ExerciseNameResolver.resolve(name: name, in: catalog) }
            else { throw AIToolError("Provide a valid exercise_id or exercise_name") }
            let metric = a.metric ?? ExerciseHistoryMetric.available(for: exercise.exerciseType)[0]
            guard ExerciseHistoryMetric.available(for: exercise.exerciseType).contains(metric) else { throw AIToolError("Metric is not supported for this exercise type") }
            if let reps = a.target_reps, !(1...100).contains(reps) { throw AIToolError("target_reps must be 1–100") }
            if let weight = a.target_weight_kg, !weight.isFinite || weight < 0 { throw AIToolError("target_weight_kg must be nonnegative") }
            let sessions = ExerciseHistoryCalculator.sessions(exerciseId: exercise.id, workouts: history, bodyWeightKg: bw, now: now)
            let points = ExerciseHistoryCalculator.points(sessions: sessions, metric: metric, targetReps: a.target_reps ?? 5, targetWeightKg: a.target_weight_kg ?? 0)
            payload["weight_recording"] = WorkoutJSON.recording(exercise)
            payload["exercise_id"] = .string(exercise.id.uuidString); payload["exercise"] = .string(exercise.name)
            payload["metric"] = .string(metric.rawValue); payload["units"] = .string(metric == .volume ? "kg × reps" : metric.usesWeight ? "kg effective load" : metric == .duration ? "seconds" : metric == .distance ? "meters" : "count")
            payload["smoothing"] = .string("Trailing median of 3 observations; resets after 21-day gaps; performance excludes deload from smoothing/change. Point id is source workout id.")
            payload["recording_by_workout"] = .array(sessions.filter { interval.contains($0.date) }.map { .object(["workout_id": .string($0.id.uuidString), "conventions": .array(($0.entries ?? []).map { WorkoutJSON.recording($0.exercise) })]) })
            payload["history"] = page(try points.filter { interval.contains($0.date) }.map(AIToolData.json))
            payload["change_percent"] = AIToolData.optional(metric.isPerformance ? ExerciseHistoryCalculator.performanceChange(points: points, interval: interval) : ExerciseHistoryCalculator.activityChange(points: points, interval: interval, firstLoggedDate: sessions.first?.date))
            if points.filter({ interval.contains($0.date) }).isEmpty { payload["status"] = .string("no_observations") }
            let insights = try await analytics.generateInsights()
            payload["coaching_trend"] = try AIToolData.json(insights.overloadTrends.first { $0.exerciseId == exercise.id })
        case .coverage:
            payload["units"] = .string("Completed non-warmup sets; primary credit 1, indirect 0.5 split among secondary muscles")
            let muscles = a.muscle_group.map { [$0] } ?? MuscleGroup.allCases
            var rows: [JSONValue] = []
            for muscle in muscles {
                for week in MuscleHistoryCalculator.weeks(workouts: history, muscle: muscle, interval: interval) {
                    let weekEnd = cal.date(byAdding: .day, value: 7, to: week.date)!
                    let sources = history.filter { $0.trainingDate >= max(start, week.date) && $0.trainingDate < weekEnd && $0.trainingDate <= end }
                    rows.append(.object(["muscle": .string(muscle.rawValue), "week_start": try AIToolData.json(week.date),
                        "direct_sets": sources.isEmpty ? .null : .number(week.direct), "indirect_sets": sources.isEmpty ? .null : .number(week.indirect),
                        "observed": .bool(!sources.isEmpty), "source_workout_ids": try AIToolData.json(sources.map(\.id))]))
                }
            }
            payload["weeks"] = page(rows)
        case .patterns:
            let insights = try await analytics.generateInsights()
            payload["calculation_window"] = .string("State: last 4 complete calendar weeks vs preceding 4; routines and counts: trailing 12 weeks; best time: available historical observations; notable sessions: latest 28 days")
            payload["state"] = try AIToolData.json(TrainingStateService.summarize(workouts: history, now: now))
            payload["routines"] = page(try WorkoutArchetypeService.summarizeWorkoutTypes(workouts: history, now: now).map { type in
                .object(["id": .string(type.id.uuidString), "focus": .string(type.label), "session_count": .number(Double(type.memberWorkoutIds.count)),
                    "frequency_per_week": .number(type.frequency), "source_workout_ids": try AIToolData.json(type.memberWorkoutIds), "last_performed": try AIToolData.json(type.lastPerformed)])
            })
            payload["best_training_time"] = try AIToolData.json(insights.timeOfDayAnalysis)
            payload["notable_sessions"] = page(try TrainingStateService.notableSessions(workouts: history, now: now).map {
                .object(["workout_id": .string($0.id.uuidString), "date": try AIToolData.json($0.workout.trainingDate), "detail": .string($0.detail)])
            })
        case .recovery:
            let insights = try await analytics.generateInsights()
            payload["calculation_window"] = .string("Current estimate using last muscle exposure and stored personal recovery feedback")
            payload["interpretation"] = .string("Dose-adjusted heuristic; not measured fatigue. Missing last exposure means unknown. Feedback adjusts the estimate, not medical readiness.")
            let patterns = insights.recoveryPatterns.filter { a.muscle_group == nil || $0.muscleGroup.caseInsensitiveCompare(a.muscle_group!.rawValue) == .orderedSame }
            payload["muscles"] = page(try patterns.map(AIToolData.json))
            if patterns.isEmpty { payload["status"] = .string("insufficient_data"); payload["requirement"] = .string("20 completed workouts for recovery analysis") }
        case .plan:
            guard let plan = try await plans.fetchActive() else { payload["status"] = .string("no_active_plan"); break }
            payload["calculation_window"] = .string("Entire active plan; adherence denominator excludes future and omitted deload sessions")
            payload["plan_id"] = .string(plan.id.uuidString); payload["version"] = .string(PlanEditingService.version(plan))
            let progress = try await planAnalytics.generateProgress(for: plan)
            payload["progress"] = try AIToolData.json(progress)
            payload["source_workout_ids"] = try AIToolData.json(progress.attributions?.map(\.workoutID))
        }
        return .init(outputForModel: AIJSON.string(.object(payload)), activityLabel: "Read \(kind.rawValue.replacingOccurrences(of: "get_", with: "").replacingOccurrences(of: "_", with: " "))")
    }
    private func parse(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        guard let date = AIJSON.parseDate(value) else { throw AIToolError("Dates must use yyyy-MM-dd") }
        return date
    }
}
