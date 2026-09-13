import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("Effective Load Model")
struct EffectiveLoadTests {

    private func makeExercise(
        exerciseType: ExerciseType = .bodyweightReps,
        bodyweightFactor: Double? = nil
    ) -> Exercise {
        Exercise(
            id: UUID(), name: "Test", primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [], category: .bodyweight,
            exerciseType: exerciseType, instructions: nil,
            isCustom: false, isArchived: false,
            bodyweightFactor: bodyweightFactor
        )
    }

    private func makeSet(
        weight: Double? = nil,
        reps: Int? = nil,
        setType: SetType = .normal,
        isCompleted: Bool = true
    ) -> ExerciseSet {
        ExerciseSet(
            id: UUID(), order: 0, setType: setType,
            weight: weight, reps: reps,
            durationSeconds: nil, distanceMeters: nil, rpe: nil,
            isCompleted: isCompleted, isPersonalRecord: false,
            completedAt: isCompleted ? Date() : nil
        )
    }

    // MARK: - baseLoadPerRep

    @Test("baseLoadPerRep multiplies body weight by the factor")
    func baseLoadWithFactor() {
        let pushUp = makeExercise(bodyweightFactor: 0.64)
        #expect(pushUp.baseLoadPerRep(bodyWeightKg: 80) == 51.2)
    }

    @Test("baseLoadPerRep falls back to factor 1.0 when nil")
    func baseLoadFallback() {
        let pullUp = makeExercise(bodyweightFactor: nil)
        #expect(pullUp.baseLoadPerRep(bodyWeightKg: 80) == 80.0)
    }

    @Test("baseLoadPerRep is nil for non-bodyweight exercise types")
    func baseLoadNonBodyweight() {
        for type in [ExerciseType.weightedReps, .duration, .cardio, .weightedCardio] {
            let exercise = makeExercise(exerciseType: type, bodyweightFactor: 0.64)
            #expect(exercise.baseLoadPerRep(bodyWeightKg: 80) == nil, "\(type) should have no base load")
        }
    }

    // MARK: - DropSetEntry.effectiveLoad

    @Test("effectiveLoad matrix: base and extra kg combine; without base weight passes through")
    func effectiveLoadMatrix() {
        let bare = DropSetEntry(weight: nil)
        let weighted = DropSetEntry(weight: 20)
        let bareWithBase: Double? = bare.effectiveLoad(baseLoadPerRep: 70)
        let weightedWithBase: Double? = weighted.effectiveLoad(baseLoadPerRep: 70)
        let weightedNoBase: Double? = weighted.effectiveLoad(baseLoadPerRep: nil)
        let bareNoBase: Double? = bare.effectiveLoad(baseLoadPerRep: nil)
        #expect(bareWithBase == 70.0)
        #expect(weightedWithBase == 90.0)
        #expect(weightedNoBase == 20.0)
        #expect(bareNoBase == nil)
    }

    // MARK: - effectiveLoadParts

    @Test("effectiveLoadParts includes nil-weight bodyweight sets (the 0-volume bug)")
    func partsIncludeNilWeightSets() {
        let set = makeSet(weight: nil, reps: 10)
        let parts = set.effectiveLoadParts(baseLoadPerRep: 51.2)
        #expect(parts.count == 1)
        #expect(parts[0].load == 51.2)
        #expect(parts[0].reps == 10)
        // Without a base, the same set contributes nothing.
        #expect(set.effectiveLoadParts(baseLoadPerRep: nil).isEmpty)
    }

    @Test("effectiveLoadParts covers every drop segment with base added to each")
    func partsCoverDropSegments() {
        var set = makeSet(weight: nil, reps: nil)
        set.applyDropSets([
            DropSetEntry(weight: 20, reps: 5),
            DropSetEntry(weight: 10, reps: 4),
            DropSetEntry(weight: nil, reps: 6),
        ])
        let parts = set.effectiveLoadParts(baseLoadPerRep: 80)
        let loads: [Double] = parts.map(\.load)
        let reps: [Int] = parts.map(\.reps)
        #expect(loads == [100.0, 90.0, 80.0])
        #expect(reps == [5, 4, 6])
    }

    // MARK: - Volume

    @Test("bodyweight set volume = bw × factor × reps (80 kg × 0.64 × 10 = 512)")
    func bodyweightSetVolume() {
        let set = makeSet(weight: nil, reps: 10)
        #expect(set.setVolume(baseLoadPerRep: 80 * 0.64) == 512.0)
    }

    @Test("weighted pull-up regression lock: +20 kg at 80 kg bw is 500 volume for 5 reps, not 100")
    func weightedPullUpVolume() {
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: 20, reps: 5)
        let we = WorkoutExercise(
            id: UUID(), exercise: pullUp, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        #expect(we.exerciseVolume(bodyWeightKg: 80) == 500.0)
    }

    @Test("duration-type exercises keep 0 volume")
    func durationKeepsZeroVolume() {
        let plank = makeExercise(exerciseType: .duration)
        var set = makeSet(weight: nil, reps: nil)
        set.durationSeconds = 60
        let we = WorkoutExercise(
            id: UUID(), exercise: plank, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        #expect(we.exerciseVolume(bodyWeightKg: 80) == 0.0)
    }

    // MARK: - e1RM

    @Test("effective e1RM feeds the shared formula (100 kg × 5 reps)")
    func effectiveE1RM() {
        let set = makeSet(weight: 20, reps: 5)
        let parts = set.effectiveLoadParts(baseLoadPerRep: 80)
        let e1rm = AnalyticsCalculations.calculateOneRM(weight: parts[0].load, reps: parts[0].reps)
        let expected = 100.0 * (1.0 + 5.0 / 30.0)
        #expect(abs(e1rm - expected) < 0.0001)
    }

    // MARK: - Analytics inputs

    @Test("buildBestE1RMMap includes nil-weight bodyweight sets")
    @MainActor
    func bestE1RMMapIncludesBodyweightSets() {
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: nil, reps: 5)
        let we = WorkoutExercise(
            id: UUID(), exercise: pullUp, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        let workout = Workout(
            id: UUID(), name: "Pull", startedAt: Date(), completedAt: Date(),
            notes: nil, templateId: nil, exercises: [we]
        )
        let map = AnalyticsCalculations.buildBestE1RMMap(from: [workout], bodyWeightKg: 80)
        let best: Double = map[pullUp.id] ?? 0
        let expected = 80.0 * (1.0 + 5.0 / 30.0)
        #expect(abs(best - expected) < 0.0001)
    }

    @Test("setIWV counts nil-weight bodyweight sets via the base load")
    func setIWVIncludesBodyweightSets() {
        let set = makeSet(weight: nil, reps: 10)
        // pct1RM = 80/100 → IWV = 10 × 0.8
        let iwv = AnalyticsCalculations.setIWV(for: set, bestE1RM: 100, baseLoadPerRep: 80)
        #expect(abs(iwv - 8.0) < 0.0001)
        // No base → part has no load → 0
        #expect(AnalyticsCalculations.setIWV(for: set, bestE1RM: 100, baseLoadPerRep: nil) == 0)
    }

    // MARK: - PR checks

    @Test("checkForPR records effective-load PRs for a nil-weight bodyweight set")
    @MainActor
    func checkForPREffective() async throws {
        let prRepo = InMemoryPersonalRecordRepository()
        let workoutRepo = InMemoryWorkoutRepository()
        let service = PersonalRecordService(
            personalRecordRepository: prRepo,
            workoutRepository: workoutRepo
        )
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: nil, reps: 5)

        let record = try await service.checkForPR(exercise: pullUp, set: set)
        // Default body weight 70 → maxWeight 70, e1RM 70×(1+5/30); e1RM is most significant.
        #expect(record?.recordType == .estimatedOneRepMax)
        let saved = try await prRepo.fetchForExercise(pullUp.id)
        let maxWeight = saved.first { $0.recordType == .maxWeight }
        #expect(maxWeight?.value == 70.0)
        let maxVolume = saved.first { $0.recordType == .maxVolume }
        #expect(maxVolume?.value == 350.0)
    }

    @Test("recalculateAllPRs replaces extra-kg-era records with effective-load values")
    @MainActor
    func recalculateReplacesExtraKgRecords() async throws {
        let prRepo = InMemoryPersonalRecordRepository()
        let workoutRepo = InMemoryWorkoutRepository()
        let service = PersonalRecordService(
            personalRecordRepository: prRepo,
            workoutRepository: workoutRepo
        )
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: 20, reps: 5)

        // Extra-kg-era record: maxWeight 20 from the same set.
        _ = try await prRepo.save(PersonalRecord(
            id: UUID(), exerciseId: pullUp.id, recordType: .maxWeight,
            value: 20.0, setId: set.id, achievedAt: Date()
        ))

        let we = WorkoutExercise(
            id: UUID(), exercise: pullUp, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        _ = try await workoutRepo.save(Workout(
            id: UUID(), name: "Pull", startedAt: Date(), completedAt: Date(),
            notes: nil, templateId: nil, exercises: [we]
        ))

        try await service.recalculateAllPRs()

        let records = try await prRepo.fetchForExercise(pullUp.id)
        let maxWeight = records.first { $0.recordType == .maxWeight }
        // Default body weight 70 + 20 extra = 90 effective.
        #expect(maxWeight?.value == 90.0)
        let staleRecords = records.filter { $0.recordType == .maxWeight && $0.value == 20.0 }
        #expect(staleRecords.isEmpty)
    }

    // MARK: - Progression points

    @Test("history progression points include nil-weight bodyweight sets at effective load")
    @MainActor
    func progressionPointsIncludeBodyweightSets() async {
        let pullUp = makeExercise(bodyweightFactor: 1.0)
        let set = makeSet(weight: nil, reps: 8)
        let we = WorkoutExercise(
            id: UUID(), exercise: pullUp, order: 0,
            supersetGroup: nil, notes: nil, restTimerSeconds: nil,
            sets: [set]
        )
        let workout = Workout(
            id: UUID(), name: "Pull", startedAt: Date(), completedAt: Date(),
            notes: nil, templateId: nil, exercises: [we]
        )
        let workoutRepo = InMemoryWorkoutRepository()
        _ = try? await workoutRepo.save(workout)

        let vm = HistoryViewModel(workoutRepository: workoutRepo)
        await vm.loadHistory()
        let points = vm.exerciseProgression(for: pullUp.id)
        #expect(points.count == 1)
        #expect(points.first?.weight == 70.0)
        #expect(points.first?.reps == 8)
    }
}

@Suite("Dumbbell recording conventions")
@MainActor
struct DumbbellRecordingTests {
    private func exercise(_ recording: WeightRecording? = nil, id: UUID = UUID()) -> Exercise {
        Exercise(id: id, name: "Dumbbell Bench Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [.triceps], category: .dumbbell, exerciseType: .weightedReps, instructions: nil, isCustom: true, isArchived: false, weightRecording: recording)
    }
    private func set(_ weight: Double = 20, _ reps: Int = 10) -> ExerciseSet {
        ExerciseSet(id: UUID(), order: 1, setType: .normal, weight: weight, reps: reps, durationSeconds: nil, distanceMeters: nil, rpe: 8, isCompleted: true, isPersonalRecord: false, completedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    private func workout(_ e: Exercise, date: Date = Date(timeIntervalSince1970: 1_700_000_000), sets: [ExerciseSet]? = nil) -> Workout {
        Workout(id: UUID(), name: "Push", startedAt: date, completedAt: date.addingTimeInterval(1000), notes: nil, templateId: nil,
                exercises: [WorkoutExercise(id: UUID(), exercise: e, order: 1, supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: sets ?? [set()])])
    }
    @Test("Paired, single, unilateral, combined and unresolved logging have explicit tonnage")
    func volumeMatrix() {
        let cases: [(WeightRecording?, Double, Double)] = [
            (nil, 20, 200), (.init(), 20, 400), (.init(equipment: .single), 20, 200),
            (.init(equipment: .single, repetitions: .perSide), 20, 400),
            (.init(equipment: .single, repetitions: .oneSide), 20, 200),
            (.init(weightEntry: .combined), 40, 400),
            (.init(repetitions: .perSide), 20, 800),
            (.init(equipment: .single, repetitions: .totalAlternating), 20, 200)
        ]
        for (config, weight, expected) in cases {
            #expect(workout(exercise(config), sets: [set(weight)]).totalVolume(bodyWeightKg: 80) == expected)
        }
    }
    @Test("Drop segments count once; warmups and incomplete sets never add volume")
    func drops() {
        var drop = set(); drop.applyDropSets([DropSetEntry(weight: 20, reps: 10), DropSetEntry(weight: 15.25, reps: 8)])
        var warmup = set(); warmup.setType = .warmup
        var incomplete = set(); incomplete.isCompleted = false
        let w = workout(exercise(.init()), sets: [drop, warmup, incomplete])
        #expect(w.totalVolume(bodyWeightKg: 80) == 644)
        #expect(w.exercises[0].sets[0].totalReps == 18)
        #expect(AnalyticsCalculations.bestE1RM(for: drop, baseLoadPerRep: nil) == AnalyticsCalculations.calculateOneRM(weight: 20, reps: 10))
    }
    @Test("The chart and summary share volume even with mixed recording configurations in one workout")
    func historyVolume() {
        let id = UUID(); var w = workout(exercise(.init(), id: id))
        w.exercises.append(workout(exercise(.init(equipment: .single), id: id)).exercises[0])
        let sessions = ExerciseHistoryCalculator.sessions(exerciseId: id, workouts: [w], bodyWeightKg: 80)
        #expect(sessions[0].recordedVolume == 600)
        #expect(sessions[0].value(for: .volume) == w.totalVolume(bodyWeightKg: 80))
        #expect(sessions[0].value(for: .strength) == nil)
    }
    @Test("Explicit weight conversions retain exact decimals and do not accept unresolved conventions")
    func conversion() throws {
        let e = exercise(.init())
        #expect(try WeightRecordingHistory.inputWeight(40.5, entry: .combined, for: e) == 20.25)
        #expect(try WeightRecordingHistory.inputWeight(20.25, entry: .perDumbbell, for: exercise(.init(weightEntry: .combined))) == 40.5)
        #expect(throws: WorkoutEditError.self) { try WeightRecordingHistory.inputWeight(40, entry: .combined, for: exercise()) }
        let pounds = WeightUnit.lbs.fromKg(20.25)
        #expect(abs(WeightUnit.lbs.toKg(pounds) - 20.25) < 0.0001)
    }
    @Test("Every seeded dumbbell is classified; single dumbbell exceptions never receive paired defaults")
    func seeds() {
        let dumbbells = ExerciseSeedData.allExercises.filter(\.isDumbbell)
        #expect(dumbbells.count == 54)
        #expect(dumbbells.allSatisfy { $0.weightRecording != nil })
        for name in ["Goblet Squat", "Dumbbell Pullover", "Dumbbell Overhead Tricep Extension"] {
            #expect(dumbbells.first { $0.name == name }?.volumeMultiplier == 1)
        }
        #expect(DumbbellDefaults.recording(for: "Unknown custom curl") == nil)
    }
    @Test("Snapshot JSON round-trips and legacy data remains unresolved")
    func codable() throws {
        let original = workout(exercise(.init(repetitions: .perSide)))
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        #expect(try JSONDecoder().decode(Workout.self, from: data) == original)
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(original.exercises[0].exercise)) as? [String: Any])
        object.removeValue(forKey: "weightRecording")
        let legacy = try JSONDecoder().decode(Exercise.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.weightRecording == nil)
        #expect(legacy.volumeMultiplier == 1)
    }
    @Test("Changing volume interpretation never doubles e1RM or intensity-weighted load")
    func relativeCalculations() {
        let id = UUID(); let old = exercise(nil, id: id), fixed = exercise(.init(), id: id)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let dates = (0..<12).map { now.addingTimeInterval(-Double($0) * 3 * 86400) }
        let before = dates.map { workout(old, date: $0) }, after = dates.map { workout(fixed, date: $0) }
        let baseline = AnalyticsCalculations.buildBestE1RMMap(from: before, bodyWeightKg: 80, asOf: now.addingTimeInterval(2000))
        #expect(baseline == AnalyticsCalculations.buildBestE1RMMap(from: after, bodyWeightKg: 80, asOf: now.addingTimeInterval(2000)))
        let a = TrainingLoadService.computeTrainingLoad(bodyWeightKg: 80, workouts: before, bestE1RM: baseline, now: now.addingTimeInterval(2000))
        let b = TrainingLoadService.computeTrainingLoad(bodyWeightKg: 80, workouts: after, bestE1RM: baseline, now: now.addingTimeInterval(2000))
        #expect(a?.acwr == b?.acwr)
        #expect(a?.acuteLoad == b?.acuteLoad)
    }
    @Test("Performance histories separate conventions and never smooth a false weight jump")
    func boundaries() {
        let id = UUID(), date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = workout(exercise(.init(), id: id), date: date)
        let b = workout(exercise(.init(equipment: .single, repetitions: .totalAlternating), id: id), date: date.addingTimeInterval(86400), sets: [set(40)])
        let sessions = ExerciseHistoryCalculator.sessions(exerciseId: id, workouts: [a,b], bodyWeightKg: 80)
        let points = ExerciseHistoryCalculator.points(sessions: sessions, metric: .strength)
        #expect(points.count == 2)
        #expect(points[0].segment != points[1].segment)
        #expect(points[1].median == nil)
        let latest = WeightRecordingHistory.matching([a,b])
        #expect(latest[0].exercises.isEmpty)
        #expect(latest[1].exercises.count == 1)
    }
    @Test("Correction preview, retries and undo preserve all source entries and skip active workouts")
    func correction() async throws {
        let ws = InMemoryWorkoutRepository(), es = InMemoryExerciseRepository(), ts = InMemoryTemplateRepository(), ps = InMemoryProgressionPlanRepository()
        let suite = "dumbbell-tests-\(UUID())"; let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let e = exercise(); _ = try await es.save(e)
        let original = workout(e); _ = try await ws.save(original)
        var active = workout(e); active.completedAt = nil; _ = try await ws.save(active)
        let service = WeightRecordingService(workouts: ws, exercises: es, templates: ts, plans: ps, defaults: defaults)
        let range = DateInterval(start: .distantPast, end: .distantFuture)
        let preview = try await service.preview(selections: [e.id: .init()], history: range, updateFuture: true, bodyWeightKg: 80)
        #expect(preview.workoutCount == 1)
        #expect(preview.beforeVolume == 200)
        #expect(preview.afterVolume == 400)
        #expect(try await ws.fetchAll().first { $0.id == original.id } == original)
        var rebuilds = 0
        service.rebuild = { rebuilds += 1; if rebuilds == 1 { throw WeightRecordingService.Failure.busy } }
        await #expect(throws: WeightRecordingService.Failure.self) { try await service.apply(preview) }
        #expect(!service.canUndo)
        // An interrupted update is durable and resumes with a new service instance.
        let restarted = WeightRecordingService(workouts: ws, exercises: es, templates: ts, plans: ps, defaults: defaults)
        restarted.rebuild = { rebuilds += 1 }
        await restarted.resume()
        #expect(restarted.canUndo)
        try await restarted.apply(preview) // replay does not double the correction
        let fixed = try #require(try await ws.fetchAll().first { $0.id == original.id })
        #expect(fixed.exercises[0].sets == original.exercises[0].sets)
        #expect(fixed.totalVolume(bodyWeightKg: 80) == 400)
        #expect(try await ws.fetchAll().first { $0.id == active.id } == active)
        #expect(rebuilds == 2)
        try await restarted.undo()
        #expect(!restarted.canUndo)
        #expect(try await ws.fetchAll().first { $0.id == original.id } == original)
    }
    @Test("An edited workout invalidates a pending correction preview")
    func stalePreview() async throws {
        let ws = InMemoryWorkoutRepository(), es = InMemoryExerciseRepository(), ts = InMemoryTemplateRepository(), ps = InMemoryProgressionPlanRepository()
        let suite = "dumbbell-stale-\(UUID())"; let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let e = exercise(); _ = try await es.save(e)
        var w = workout(e); _ = try await ws.save(w)
        let service = WeightRecordingService(workouts: ws, exercises: es, templates: ts, plans: ps, defaults: defaults)
        let preview = try await service.preview(selections: [e.id: .init()], history: DateInterval(start: .distantPast, end: .distantFuture), updateFuture: false, bodyWeightKg: 80)
        w.exercises[0].sets[0].weight = 25; _ = try await ws.save(w)
        await #expect(throws: WeightRecordingService.Failure.stale) { try await service.apply(preview) }
        #expect(try await ws.fetchAll()[0].exercises[0].exercise.weightRecording == nil)
    }
    @Test("Known each/total changes normalize strength and retain source volume and weights")
    func normalizedHistory() {
        let id = UUID(), date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = workout(exercise(.init(), id: id), date: date)
        let b = workout(exercise(.init(weightEntry: .combined), id: id), date: date.addingTimeInterval(86400), sets: [set(40)])
        let sessions = ExerciseHistoryCalculator.sessions(exerciseId: id, workouts: [a, b], bodyWeightKg: 80)
        let points = ExerciseHistoryCalculator.points(sessions: sessions, metric: .strength)
        #expect(points[0].value == points[1].value)
        #expect(points[0].segment == points[1].segment)
        #expect(sessions.map(\.recordedVolume) == [400, 400])
        #expect(a.exercises[0].sets[0].weight == 20)
        #expect(WeightRecordingHistory.matching([a, b])[0].exercises[0].sets[0].weight == 40)
    }
    @Test("A known convention switch never earns a false live PR; manual values remain stored")
    func recordsAcrossKnownConventions() async throws {
        let ws = InMemoryWorkoutRepository(), prs = InMemoryPersonalRecordRepository()
        let id = UUID(), each = exercise(.init(), id: id), total = exercise(.init(weightEntry: .combined), id: id)
        let w = workout(each); _ = try await ws.save(w)
        let manual = PersonalRecord(id: UUID(), exerciseId: id, recordType: .estimatedOneRepMax, value: 999, setId: nil, achievedAt: Date())
        _ = try await prs.save(manual)
        let service = PersonalRecordService(personalRecordRepository: prs, workoutRepository: ws)
        try await service.recalculateAllPRs()
        #expect(try await service.checkForPR(exercise: total, set: set(40)) == nil)
        #expect(try await prs.fetchAll().contains(manual))
        #expect(try await prs.fetchForExercise(id).matching(total).bestPerType().first { $0.recordType == .maxWeight }?.value == 40)
    }
    @Test("Volume PRs include older incompatible histories without mixing strength")
    func volumeRecordsAcrossIncompatibleConventions() async throws {
        let ws = InMemoryWorkoutRepository(), prs = InMemoryPersonalRecordRepository(), id = UUID()
        _ = try await ws.save(workout(exercise(.init(), id: id), sets: [set(30, 20)]))
        _ = try await ws.save(workout(exercise(.init(equipment: .single, repetitions: .totalAlternating), id: id), date: Date(), sets: [set(10)]))
        try await PersonalRecordService(personalRecordRepository: prs, workoutRepository: ws).recalculateAllPRs()
        let records = try await prs.fetchForExercise(id)
        #expect(records.first { $0.recordType == .maxVolume }?.value == 1200)
        #expect(records.first { $0.recordType == .maxWeight }?.value == 10)
    }
    @Test("Relative load is invariant when known each and total conventions are mixed")
    func mixedRelativeLoad() {
        let id = UUID(), now = Date(timeIntervalSince1970: 1_700_000_000)
        let original = (0..<12).map { workout(exercise(.init(), id: id), date: now.addingTimeInterval(-Double($0) * 3 * 86400)) }
        var mixed = original
        for i in mixed.indices where i < 5 {
            mixed[i].exercises[0].exercise.weightRecording = .init(weightEntry: .combined)
            mixed[i].exercises[0].sets[0].weight = 40
        }
        func load(_ history: [Workout]) -> TrainingLoad? {
            TrainingLoadService.computeTrainingLoad(bodyWeightKg: 80, workouts: history,
                bestE1RM: AnalyticsCalculations.buildBestE1RMMap(from: history, bodyWeightKg: 80, asOf: now), now: now)
        }
        #expect(load(original)?.acuteLoad == load(mixed)?.acuteLoad)
        #expect(load(original)?.acwr == load(mixed)?.acwr)
    }
    @Test("Future defaults annotate unresolved targets but preserve existing known template and plan snapshots")
    func targetSnapshots() async throws {
        let ws = InMemoryWorkoutRepository(), es = InMemoryExerciseRepository(), ts = InMemoryTemplateRepository(), ps = InMemoryProgressionPlanRepository()
        let suite = "dumbbell-targets-\(UUID())"; let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let e = exercise(); _ = try await es.save(e)
        let legacy = TemplateExerciseFactory.make(exercise: e, order: 0, defaultReps: 10)
        var known = legacy; known.exercise.weightRecording = .init(weightEntry: .combined)
        let template = WorkoutTemplate(id: UUID(), name: "Legacy", notes: nil, sortOrder: 0, lastUsedAt: nil, timesUsed: 0, exercises: [legacy])
        let confirmed = WorkoutTemplate(id: UUID(), name: "Confirmed", notes: nil, sortOrder: 1, lastUsedAt: nil, timesUsed: 0, exercises: [known])
        _ = try await ts.save(template); _ = try await ts.save(confirmed)
        let service = WeightRecordingService(workouts: ws, exercises: es, templates: ts, plans: ps, defaults: defaults)
        let preview = try await service.preview(selections: [e.id: .init()], history: nil, updateFuture: true, bodyWeightKg: 80)
        #expect(preview.workoutCount == 0)
        try await service.apply(preview)
        let saved = try await ts.fetchAll()
        #expect(saved.first { $0.id == confirmed.id } == confirmed)
        #expect(saved.first { $0.id == template.id }?.exercises[0].exercise.weightRecording == .init())
        #expect(saved.first { $0.id == template.id }?.exercises[0].setTargets == legacy.setTargets)
        try await service.undo()
        #expect(try await ts.fetchAll().first { $0.id == template.id } == template)
    }
    @Test("Widget payloads describe each/total and decode older payloads without new fields")
    func widgets() throws {
        let widget = WidgetActiveWorkout(workoutName: "Push", currentExerciseName: "DB press", currentExerciseId: UUID().uuidString,
            completedSets: 0, totalPlannedSets: 3, startedAt: Date(), isResting: false, restEndDate: nil,
            nextSetWeight: 20.25, nextSetReps: 10, nextExerciseName: nil, weightRecording: .init(repetitions: .perSide))
        #expect(widget.targetLabel == "20.25 kg each × 10 reps/side")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(widget)) as? [String: Any])
        object.removeValue(forKey: "weightRecording"); object.removeValue(forKey: "dumbbellConventionUnconfirmed")
        let legacy = try JSONDecoder().decode(WidgetActiveWorkout.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.weightRecording == nil)
        #expect(legacy.nextSetWeight == 20.25)
    }
    @Test("Seeding never guesses existing historical defaults or overwrites custom conventions")
    func preservesExistingSeedConventions() async throws {
        let es = InMemoryExerciseRepository()
        var e = try #require(ExerciseSeedData.allExercises.first { $0.name == "Dumbbell Bench Press" })
        e.name = "Old seed name"; e.weightRecording = nil
        _ = try await es.save(e)
        await ExerciseSeeder(exerciseRepository: es).seedIfNeeded()
        #expect(try await es.fetchAll().first { $0.id == e.id }?.weightRecording == nil)
        e.weightRecording = .init(weightEntry: .combined); _ = try await es.save(e)
        await ExerciseSeeder(exerciseRepository: es).seedIfNeeded()
        #expect(try await es.fetchAll().first { $0.id == e.id }?.weightRecording == e.weightRecording)
    }
    @Test("Planned targets retain their convention despite subsequent library changes")
    func plannedSnapshots() throws {
        let id = UUID(), each = exercise(.init(), id: id), combined = exercise(.init(weightEntry: .combined), id: id)
        let target = PlannedExerciseSet(planExerciseId: UUID(), exerciseId: id, exerciseName: each.name,
            sets: 3, targetReps: 10, targetWeight: 20.25, percentageOf1RM: 0, weightRecording: each.weightRecording)
        let session = PlannedSession(dayOfWeek: 2, sessionLabel: "Push", plannedExercises: [target], estimatedDurationMinutes: 60)
        let prepared = session.toWorkoutTemplate(exercises: [combined])
        #expect(prepared.exercises[0].exercise.weightRecording == each.weightRecording)
        #expect(prepared.exercises[0].targetWeight == 20.25)
        #expect(try JSONDecoder().decode(PlannedSession.self, from: JSONEncoder().encode(session)) == session)
        #expect(WeightRecordingHistory.convertWeight(20.25, from: each.weightRecording, to: combined.weightRecording) == 40.5)
        #expect(WeightRecordingHistory.convertWeight(20.25, from: nil, to: combined.weightRecording) == nil)
    }
    @Test("Training plan 1RM updates use plan units when the performed workout uses combined weights")
    func planExecutionUnits() {
        let id = UUID(), config = WeightRecording(), combined = exercise(.init(weightEntry: .combined), id: id)
        let plan = PlanExercise(exerciseId: id, exerciseName: combined.name, primaryMuscleGroup: .chest, category: .dumbbell,
            estimated1RM: 0, oneRMSource: .estimated, current1RM: 0, isCompound: true, order: 0, weightRecording: config)
        let target = PlannedExerciseSet(planExerciseId: plan.id, exerciseId: id, exerciseName: combined.name,
            sets: 1, targetReps: 10, targetWeight: 20, percentageOf1RM: 0, weightRecording: config)
        let session = PlannedSession(dayOfWeek: 2, sessionLabel: "Push", plannedExercises: [target], estimatedDurationMinutes: 60)
        let result = SessionExecutionService().completeSession(session, workout: workout(combined, sets: [set(40)]), planExercises: [plan], bodyWeightKg: 80)
        let expected = AnalyticsCalculations.calculateOneRM(weight: 20, reps: 10).rounded(toNearest: 2.5)
        #expect(result.updatedExercises[0].current1RM == expected)
        #expect(result.updatedExercises[0].weightRecording == config)
    }
    @Test("Quality intensity and volume stay stable for equivalent each and combined entries")
    func qualityUnits() {
        let ws = InMemoryWorkoutRepository(), prefs = UserPreferencesService()
        let service = WorkoutQualityScoreService(workoutRepository: ws, muscleBalanceService: MuscleBalanceService(), healthKitService: NoOpHealthKitService(), userPreferencesService: prefs)
        let id = UUID(), now = Date()
        let history = (1...5).map { workout(exercise(.init(), id: id), date: now.addingTimeInterval(-Double($0) * 86400)) }
        let a = workout(exercise(.init(), id: id), date: now)
        let b = workout(exercise(.init(weightEntry: .combined), id: id), date: now, sets: [set(40)])
        let x = service.computeScore(for: a, history: history), y = service.computeScore(for: b, history: history)
        #expect(x.intensityScore == y.intensityScore)
        #expect(x.volumeScore == y.volumeScore)
        #expect(x.balanceScore == y.balanceScore)
    }
    @Test("Future plan correction includes saved deload prescriptions and undo restores both")
    func planCorrection() async throws {
        let ws = InMemoryWorkoutRepository(), es = InMemoryExerciseRepository(), ts = InMemoryTemplateRepository(), ps = InMemoryProgressionPlanRepository()
        let suite = "dumbbell-plans-\(UUID())"; let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let e = exercise(); _ = try await es.save(e)
        let pe = ProgressionTestHelpers.makeTestPlanExercise(exerciseId: e.id, category: .dumbbell)
        let target = ProgressionTestHelpers.makeTestPlannedExerciseSet(planExerciseId: pe.id, exerciseId: e.id, targetWeight: 20.25)
        var pending = ProgressionTestHelpers.makeIncompleteSession(exercises: [target])
        PlanDeloadPolicy.apply(to: &pending, weightPercentage: 50, restPercentage: 100)
        let done = ProgressionTestHelpers.makeCompletedSession(exercises: [ProgressionTestHelpers.makeTestPlannedExerciseSet(exerciseId: e.id)])
        let block = ProgressionTestHelpers.makeTestTrainingBlock(weeks: [ProgressionTestHelpers.makeTestTrainingWeek(sessions: [pending, done])])
        let plan = ProgressionTestHelpers.makeTestPlan(blocks: [block], exercises: [pe]); try await ps.save(plan)
        let service = WeightRecordingService(workouts: ws, exercises: es, templates: ts, plans: ps, defaults: defaults)
        let preview = try await service.preview(selections: [e.id: .init()], history: nil, updateFuture: true, bodyWeightKg: 80)
        try await service.apply(preview)
        let fixed = try #require(try await ps.fetch(id: plan.id))
        #expect(fixed.blocks[0].weeks[0].sessions[0].plannedExercises[0].weightRecording == .init())
        #expect(fixed.blocks[0].weeks[0].sessions[0].deloadPrescription?.normalExercises[0].weightRecording == .init())
        #expect(fixed.blocks[0].weeks[0].sessions[0].plannedExercises[0].targetWeight == pending.plannedExercises[0].targetWeight)
        #expect(fixed.blocks[0].weeks[0].sessions[1] == done)
        try await service.undo()
        #expect(try await ps.fetch(id: plan.id) == plan)
    }
    @Test("Every generated program retains dumbbell target conventions")
    func generatedTargets() {
        var pe = ProgressionTestHelpers.makeTestPlanExercise(category: .dumbbell); pe.weightRecording = .init()
        for kind in ProgramType.allCases {
            let plan = ProgressionTestHelpers.makeTestPlan(exercises: [pe], programType: kind)
            let targets = ProgramDesignService().generateProgram(for: plan).flatMap(\.weeks).flatMap(\.sessions).flatMap(\.plannedExercises)
            #expect(!targets.isEmpty)
            #expect(targets.allSatisfy { $0.weightRecording == pe.weightRecording })
        }
    }
    #if canImport(SwiftData)
    @Test("Exercise, workout and template SwiftData mappers retain their own recording snapshots")
    func persistence() {
        let e = exercise(.init()), w = workout(e)
        #expect(ExerciseMapper.toDomain(ExerciseMapper.toEntity(e)) == e)
        #expect(WorkoutMapper.toDomain(WorkoutMapper.toEntity(w)) == w)
        let template = WorkoutTemplate(id: UUID(), name: "Push", notes: nil, sortOrder: 0, lastUsedAt: nil, timesUsed: 0,
            exercises: [TemplateExerciseFactory.make(exercise: e, order: 0, defaultReps: 10)])
        #expect(TemplateMapper.toDomain(TemplateMapper.toEntity(template)).exercises[0].exercise.weightRecording == e.weightRecording)
    }
    #endif
}

@Suite("Personal bodyweight percentage")
@MainActor
struct BodyweightPercentageTests {
    private func exercise(_ factor: Double = 0.64, id: UUID = UUID()) -> Exercise {
        Exercise(id: id, name: "Push-Up", primaryMuscleGroup: .chest, secondaryMuscleGroups: [],
            category: .bodyweight, exerciseType: .bodyweightReps, instructions: nil,
            isCustom: false, isArchived: false, bodyweightFactor: factor)
    }
    private func workout(_ exercise: Exercise, day: Int = 0, added: Double = 10) -> Workout {
        let date = Date().addingTimeInterval(Double(day) * 86400 - 60)
        let set = ExerciseSet(id: UUID(), order: 1, setType: .normal, weight: added, reps: 10,
            durationSeconds: nil, distanceMeters: nil, rpe: nil, isCompleted: true,
            isPersonalRecord: false, completedAt: date)
        return Workout(id: UUID(), name: "Training", startedAt: date, completedAt: date,
            notes: nil, templateId: nil, exercises: [WorkoutExercise(id: UUID(), exercise: exercise, order: 1,
                supersetGroup: nil, notes: nil, restTimerSeconds: nil, sets: [set])])
    }
    private func template(_ exercise: Exercise) -> WorkoutTemplate {
        WorkoutTemplate(id: UUID(), name: "Push", notes: nil, sortOrder: 0, lastUsedAt: nil, timesUsed: 0,
            exercises: [TemplateExerciseFactory.make(exercise: exercise, order: 1, defaultReps: 10, targetWeightKg: 10)])
    }

    @Test("Percentage input accepts decimal commas, dots and blank reset; rejects invalid input")
    func validation() throws {
        #expect(try BodyweightPercentage.parse(" 64,25 ") == 64.25)
        #expect(try BodyweightPercentage.parse("64.25") == 64.25)
        #expect(try BodyweightPercentage.parse(" ") == nil)
        #expect(try BodyweightPercentage.factor(percent: 10) == 0.1)
        #expect(try BodyweightPercentage.factor(percent: 150) == 1.5)
        for text in ["0", "9.99", "150.01", "-10", "abc", "NaN", "inf", "64,2.5"] {
            #expect(throws: BodyweightPercentage.Invalid.self) { try BodyweightPercentage.parse(text) }
        }
    }

    @Test("Built-in override retains identity and default, resets cleanly, and survives library refresh")
    func overrideAndSeed() async throws {
        let repo = InMemoryExerciseRepository()
        var seed = try #require(ExerciseSeedData.allExercises.first { $0.name == "Push-Up" })
        _ = try await repo.save(seed)
        let vm = ExerciseListViewModel(exerciseRepository: repo)
        var updates = 0
        vm.didSave = { updates += 1 }
        let changed = try #require(await vm.saveBodyweightPercentage(exerciseId: seed.id, percent: 70))
        #expect(changed.id == seed.id && !changed.isCustom)
        #expect(changed.bodyweightFactor == 0.64)
        #expect(changed.resolvedBodyweightFactor == 0.7)
        #expect(changed.baseLoadPerRep(bodyWeightKg: 80) == 56)
        #expect(updates == 1)
        #if canImport(SwiftData)
        seed = changed; seed.instructions = "Old instructions"
        _ = try await repo.save(seed)
        await ExerciseSeeder(exerciseRepository: repo).seedIfNeeded()
        let refreshed = try #require(try await repo.fetchAll().first { $0.id == seed.id })
        #expect(refreshed.instructions != "Old instructions")
        #expect(refreshed.bodyweightFactorOverride == 0.7)
        #endif
        let reset = try #require(await vm.saveBodyweightPercentage(exerciseId: seed.id, percent: nil))
        #expect(reset.bodyweightFactorOverride == nil)
        #expect(reset.resolvedBodyweightFactor == 0.64)
        #expect(updates == 2)
    }

    @Test("Custom reset uses 100%; errors do not announce success or replace stored settings")
    func resetAndFailure() async throws {
        let repo = MockExerciseRepository()
        var e = exercise(); e.isCustom = true
        repo.seed([e])
        let vm = ExerciseListViewModel(exerciseRepository: repo)
        var updates = 0; vm.didSave = { updates += 1 }
        let reset = try #require(await vm.saveBodyweightPercentage(exerciseId: e.id, percent: nil))
        #expect(reset.resolvedBodyweightFactor == 1)
        #expect(await vm.saveBodyweightPercentage(exerciseId: e.id, percent: 151) == nil)
        #expect(vm.errorMessage != nil)
        repo.shouldThrowOnSave = true
        #expect(await vm.saveBodyweightPercentage(exerciseId: e.id, percent: 65) == nil)
        #expect(vm.errorMessage != nil)
        #expect(updates == 1)
        #expect(repo.exercises[e.id]?.resolvedBodyweightFactor == 1)
    }

    @Test("Old templates resolve at iPhone and Watch starts; existing workouts and entered values retain their snapshots")
    func newSessions() async throws {
        let e = exercise(), old = template(exercise())
        var t = old; t.exercises[0].exercise = e
        var current = e; current.bodyweightFactorOverride = 0.8
        let library = InMemoryExerciseRepository(); _ = try await library.save(current)
        let workouts = InMemoryWorkoutRepository(), templates = InMemoryTemplateRepository()
        _ = try await templates.save(t)
        let vm = WorkoutViewModel(workoutRepository: workouts, templateRepository: templates,
            healthKitService: MockHealthKitService(), exerciseRepository: library)
        await vm.startWorkout(name: "Push", from: t)
        let active = try #require(vm.currentWorkout)
        #expect(active.exercises[0].exercise.resolvedBodyweightFactor == 0.8)
        #expect(active.exercises[0].sets[0].weight == 10)
        current.bodyweightFactorOverride = 0.9; _ = try await library.save(current)
        #expect(vm.currentWorkout == active)
        #expect(try await templates.fetchAll().first?.exercises[0].exercise.bodyweightFactor == 0.64)
        let watch = WatchWorkoutViewModel(workoutRepository: InMemoryWorkoutRepository(), healthKitService: MockHealthKitService(),
            connectivityManager: ConnectivityManager(), exerciseRepository: library)
        await watch.startWorkout(name: "Push", from: t)
        #expect(watch.activeWorkout?.exercises[0].exercise.resolvedBodyweightFactor == 0.9)
        #expect(watch.activeWorkout?.exercises[0].sets[0].weight == 10)
        let historic = workout(e)
        #expect(historic.totalVolume(bodyWeightKg: 80) == 612)
        #expect(historic.exercises[0].exercise.bodyweightFactor == 0.64)
        #expect(t.resolvingBodyweight(from: [current]).exercises[0].targetWeight == 10)
    }

    @Test("Library and Watch JSON preserve overrides; legacy JSON decodes without an override")
    func json() throws {
        var e = exercise(); e.bodyweightFactorOverride = 0.75
        let data = try JSONEncoder().encode(e)
        #expect(try JSONDecoder().decode(Exercise.self, from: data) == e)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "bodyweightFactorOverride")
        let legacy = try JSONDecoder().decode(Exercise.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.resolvedBodyweightFactor == 0.64)
        let copy = e.duplicatedAsVariant()
        #expect(copy.id != e.id && copy.isCustom)
        #expect(copy.resolvedBodyweightFactor == 0.75)
        #expect(copy.bodyweightFactorOverride == nil)
    }

    @Test("Type controls percentage; defaults and overrides cannot change external-load exercises")
    func categoryVersusType() {
        var e = exercise(); e.category = .trx; e.bodyweightFactorOverride = 0.5
        #expect(e.baseLoadPerRep(bodyWeightKg: 80) == 40)
        e.exerciseType = .weightedReps; e.category = .bodyweight
        #expect(e.baseLoadPerRep(bodyWeightKg: 80) == nil)
        #expect(workout(e).totalVolume(bodyWeightKg: 80) == 100)
    }

    @Test("Percentage changes split strength lines and medians, retain volume history, and do not produce a progression trend")
    func historyComparisons() {
        let original = exercise(); var changed = original; changed.bodyweightFactor = 0.8
        let history = (-7...0).map { week in workout(week < -3 ? original : changed, day: week * 7) }
        let sessions = ExerciseHistoryCalculator.sessions(exerciseId: original.id, workouts: history, bodyWeightKg: 80)
        let points = ExerciseHistoryCalculator.points(sessions: sessions, metric: .strength)
        #expect(points.count == 8)
        #expect(points[3].segment != points[4].segment)
        #expect(points[4].median == nil && points[5].median == nil && points[6].median != nil)
        #expect(ExerciseHistoryCalculator.performanceChange(points: points, interval: DateInterval(start: history[0].trainingDate, end: Date())) == nil)
        #expect(ExerciseHistoryCalculator.points(sessions: sessions, metric: .volume).count == 8)
        let trend = OverloadTrackingService.computeOverloadTrends(workouts: history, bodyWeightKg: 80).first
        #expect(trend?.trendStatus != .progressing)
        #expect(abs(trend?.slopePerWeek ?? 0) < 0.0001)
        #expect(WeightRecordingHistory.matching(history).flatMap(\.exercises).count == 4)
        var legacy = exercise(1, id: original.id); legacy.bodyweightFactor = nil
        #expect(legacy.performanceConvention == exercise(1, id: original.id).performanceConvention)
    }

    @Test("A changed percentage establishes a PR baseline without a celebration or badge; real improvement still wins")
    func records() async throws {
        let original = exercise(); var changed = original; changed.bodyweightFactor = 0.8
        let repo = InMemoryWorkoutRepository(), prs = InMemoryPersonalRecordRepository()
        let service = PersonalRecordService(personalRecordRepository: prs, workoutRepository: repo)
        let old = workout(original, day: -7), next = workout(changed, day: -1)
        _ = try await repo.save(old)
        try await service.recalculateAllPRs()
        #expect(try await service.checkForPR(exercise: changed, set: next.exercises[0].sets[0]) == nil)
        _ = try await repo.save(next)
        try await service.recalculateAllPRs()
        let history = try await repo.fetchAll()
        #expect(history.first { $0.id == next.id }?.exercises[0].sets[0].isPersonalRecord == false)
        let improved = workout(changed, added: 15)
        #expect(try await service.checkForPR(exercise: changed, set: improved.exercises[0].sets[0]) != nil)
        _ = try await repo.save(improved)
        try await service.recalculateAllPRs()
        #expect(try await repo.fetchAll().first { $0.id == improved.id }?.exercises[0].sets[0].isPersonalRecord == true)
    }

    @Test("Weight suggestions require evidence under the selected percentage")
    func suggestions() {
        let original = exercise(); var changed = original; changed.bodyweightFactor = 0.8
        let history = (-4 ... -1).map { workout(original, day: $0 * 7, added: 30) }
        let result = WeightSuggestionService().suggest(exerciseId: original.id, exerciseName: original.name,
            targetReps: 5, recentWorkouts: history, overloadTrend: nil, recoveryStatus: nil, trainingLoad: nil,
            isDeload: false, bodyWeightKg: 80, recordingReference: changed)
        #expect(result == nil)
    }

    @Test("Plan strength baselines reject another percentage, while targets still use entered additional weight")
    func planBasis() {
        let e = exercise()
        let plan = PlanExercise(exerciseId: e.id, exerciseName: e.name, primaryMuscleGroup: .chest,
            category: .bodyweight, estimated1RM: 80, oneRMSource: .estimated, current1RM: 80,
            isCompound: true, order: 0, bodyweightFactor: 0.64)
        #expect(plan.acceptsBodyweightBasis(of: e))
        var changed = e; changed.bodyweightFactorOverride = 0.8
        #expect(!plan.acceptsBodyweightBasis(of: changed))
    }

    @Test("Added-weight suggestions subtract the selected factor even when input history begins with an older percentage")
    func suggestionUsesSelectedBase() throws {
        let old = exercise(); var current = old; current.bodyweightFactor = 0.8
        let recent = workout(current, day: -1, added: 30)
        let mixed = [workout(old, day: -8, added: 30), recent]
        func suggestion(_ rows: [Workout]) -> WeightSuggestion? {
            WeightSuggestionService().suggest(exerciseId: current.id, exerciseName: current.name,
                targetReps: 5, recentWorkouts: rows, overloadTrend: nil, recoveryStatus: nil, trainingLoad: nil,
                isDeload: false, bodyWeightKg: 80, recordingReference: current)
        }
        #expect(try #require(suggestion(mixed)).weight == #require(suggestion([recent])).weight)
    }

    @Test("Intensity-weighted load uses each percentage's own strength baseline")
    func workloadBaselines() {
        let old = exercise(); var current = old; current.bodyweightFactor = 0.8
        let history = [workout(old, day: -8), workout(current, day: -1)]
        let baselines = WeightRecordingHistory.relativeBaselines(history, bodyWeightKg: 80)
        let loads = history.map { row -> Double in
            let entry = row.exercises[0]
            return AnalyticsCalculations.setIWV(for: entry.sets[0],
                bestE1RM: baselines[WeightRecordingHistory.relativeKey(entry.exercise)],
                baseLoadPerRep: entry.exercise.baseLoadPerRep(bodyWeightKg: 80), modulateRPE: false)
        }
        #expect(abs(loads[0] - loads[1]) < 0.000001)
    }

    @Test("Linked plan templates, deloads and Watch payloads use current percentages without altering targets")
    func plannedSessions() throws {
        let original = exercise(); var current = original; current.bodyweightFactorOverride = 0.75
        let planExercise = PlanExercise(exerciseId: original.id, exerciseName: original.name, primaryMuscleGroup: .chest,
            category: .bodyweight, estimated1RM: 80, oneRMSource: .estimated, current1RM: 80,
            isCompound: true, order: 0, bodyweightFactor: 0.64)
        let target = PlannedExerciseSet(planExerciseId: planExercise.id, exerciseId: original.id,
            exerciseName: original.name, sets: 3, targetReps: 10, targetWeight: 10, percentageOf1RM: 0.5, restSeconds: 90)
        let session = PlannedSession(sessionLabel: "Push", plannedExercises: [target], isDeload: true)
        let repo = InMemoryWorkoutRepository()
        let vm = ProgressionPlanViewModel(progressionPlanRepository: InMemoryProgressionPlanRepository(),
            trainingStatusDetector: TrainingStatusDetector(workoutRepository: repo), programDesignService: ProgramDesignService(),
            planAnalyticsService: PlanAnalyticsService(workoutRepository: repo), exerciseRepository: InMemoryExerciseRepository(),
            templateRepository: InMemoryTemplateRepository())
        let merged = vm.mergeSessionIntoTemplate(session: session, template: template(original), exercises: [current])
        #expect(merged.exercises[0].exercise.resolvedBodyweightFactor == 0.75)
        #expect(merged.exercises[0].targetWeight == 10)
        let unlinked = session.toWorkoutTemplate(exercises: [current])
        #expect(unlinked.exercises[0].exercise.resolvedBodyweightFactor == 0.75)
        let payload = PlannedSessionSync(id: session.id, planId: UUID(), planName: "Plan", sessionLabel: "Push",
            weekLabel: "Week 1", blockName: nil, isDeload: true, template: merged)
        let restored = try JSONDecoder().decode(PlannedSessionSync.self, from: JSONEncoder().encode(payload))
        #expect(restored.template.exercises[0].exercise.resolvedBodyweightFactor == 0.75)
        let execution = SessionExecutionService().completeSession(PlannedSession(sessionLabel: "Push", plannedExercises: [target]),
            workout: workout(current), planExercises: [planExercise], bodyWeightKg: 80)
        #expect(execution.updatedExercises[0].current1RM == 80)
        #expect(execution.adjustments.isEmpty)
    }

    @Test("Grok reads the resolved percentage and additional-weight convention")
    func grok() async throws {
        let repo = InMemoryExerciseRepository(); var e = exercise(); e.bodyweightFactorOverride = 0.7
        _ = try await repo.save(e)
        let result = try await ListExercisesTool(exerciseRepository: repo).call(argumentsJSON: "{}")
        #expect(result.outputForModel.contains("bodyweight_percent"))
        #expect(result.outputForModel.contains("additional_weight"))
        #expect(result.outputForModel.contains("70"))
    }
}
