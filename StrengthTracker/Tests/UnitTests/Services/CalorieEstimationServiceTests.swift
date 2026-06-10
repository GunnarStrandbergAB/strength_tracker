import Foundation
import Testing
@testable import StrengthTrackerShared

@Suite("CalorieEstimationService")
struct CalorieEstimationServiceTests {

    let service = CalorieEstimationService()

    // MARK: - Helpers

    func makeExercise(
        name: String = "Test Exercise",
        primaryMuscle: MuscleGroup = .chest,
        category: ExerciseCategory = .barbell,
        exerciseType: ExerciseType = .weightedReps
    ) -> Exercise {
        Exercise(
            id: UUID(),
            name: name,
            primaryMuscleGroup: primaryMuscle,
            secondaryMuscleGroups: [],
            category: category,
            exerciseType: exerciseType,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    func makeSet(
        weight: Double? = 100,
        reps: Int? = 10,
        rpe: Double? = nil,
        setType: SetType = .normal,
        isCompleted: Bool = true
    ) -> ExerciseSet {
        ExerciseSet(
            id: UUID(),
            order: 1,
            setType: setType,
            weight: weight,
            reps: reps,
            durationSeconds: nil,
            distanceMeters: nil,
            rpe: rpe,
            isCompleted: isCompleted,
            isPersonalRecord: false,
            completedAt: isCompleted ? Date() : nil
        )
    }

    func makeWorkout(
        exercises: [WorkoutExercise],
        durationMinutes: Double = 45
    ) -> Workout {
        let start = Date()
        return Workout(
            id: UUID(),
            name: "Test Workout",
            startedAt: start,
            completedAt: start.addingTimeInterval(durationMinutes * 60),
            notes: nil,
            templateId: nil,
            exercises: exercises
        )
    }

    func makeWorkoutExercise(
        exercise: Exercise,
        order: Int = 1,
        sets: [ExerciseSet],
        supersetGroup: Int? = nil
    ) -> WorkoutExercise {
        WorkoutExercise(
            id: UUID(),
            exercise: exercise,
            order: order,
            supersetGroup: supersetGroup,
            notes: nil,
            restTimerSeconds: nil,
            sets: sets
        )
    }

    // MARK: - Basic Estimation

    @Test("Returns zero calories for incomplete workout")
    func incompleteWorkoutReturnsZero() {
        let workout = Workout(
            id: UUID(),
            name: "Incomplete",
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            exercises: []
        )
        let result = service.estimateCalories(workout: workout, bodyWeightKg: 80)
        #expect(result.totalCalories == 0)
    }

    @Test("Returns zero calories for zero body weight")
    func zeroBodyWeightReturnsZero() {
        let exercise = makeExercise()
        let sets = [makeSet()]
        let we = makeWorkoutExercise(exercise: exercise, sets: sets)
        let workout = makeWorkout(exercises: [we])

        let result = service.estimateCalories(workout: workout, bodyWeightKg: 0)
        #expect(result.totalCalories == 0)
    }

    @Test("Returns positive calories for valid workout")
    func validWorkoutReturnsPositive() {
        let exercise = makeExercise(primaryMuscle: .chest, category: .barbell)
        let sets = (0..<5).map { _ in makeSet(weight: 100, reps: 5) }
        let we = makeWorkoutExercise(exercise: exercise, sets: sets)
        let workout = makeWorkout(exercises: [we], durationMinutes: 30)

        let result = service.estimateCalories(workout: workout, bodyWeightKg: 80)
        #expect(result.totalCalories > 0)
        #expect(result.sessionCalories > 0)
        #expect(result.volumeBonus > 0)
        #expect(result.epocCalories > 0)
    }

    // MARK: - MET Lookup

    @Test("Compound barbell gets higher MET than isolation machine")
    func compoundVsIsolationMET() {
        let compoundExercise = makeExercise(name: "Squat", primaryMuscle: .quadriceps, category: .barbell)
        let isolationExercise = makeExercise(name: "Leg Extension", primaryMuscle: .quadriceps, category: .machine)
        let sets = [makeSet()]

        let compoundMET = service.metForExercise(compoundExercise, sets: sets, hasSupersetGroup: false)
        let isolationMET = service.metForExercise(isolationExercise, sets: sets, hasSupersetGroup: false)

        #expect(compoundMET > isolationMET)
    }

    @Test("Superset exercises get circuit training MET (5.8)")
    func supersetMET() {
        let exercise = makeExercise(primaryMuscle: .biceps, category: .dumbbell)
        let sets = [makeSet()]

        let met = service.metForExercise(exercise, sets: sets, hasSupersetGroup: true)
        #expect(met == 5.8)
    }

    @Test("Kettlebell compound gets highest MET")
    func kettlebellMET() {
        let kettlebell = makeExercise(name: "KB Swing", primaryMuscle: .fullBody, category: .kettlebell)
        let sets = [makeSet()]

        let met = service.metForExercise(kettlebell, sets: sets, hasSupersetGroup: false)
        #expect(met == 9.0)
    }

    @Test("Bodyweight with high RPE gets 6.5 MET")
    func bodyweightHighRPE() {
        let bw = makeExercise(name: "Pull-up", primaryMuscle: .back, category: .bodyweight)
        let sets = [makeSet(rpe: 9.0), makeSet(rpe: 8.5)]

        let met = service.metForExercise(bw, sets: sets, hasSupersetGroup: false)
        #expect(met == 6.5)
    }

    // MARK: - Compound Detection

    @Test("Large muscle groups are detected as compound")
    func compoundDetection() {
        let squat = makeExercise(primaryMuscle: .quadriceps, category: .barbell)
        let deadlift = makeExercise(primaryMuscle: .back, category: .barbell)
        let bench = makeExercise(primaryMuscle: .chest, category: .barbell)
        let curl = makeExercise(primaryMuscle: .biceps, category: .barbell)

        #expect(service.isCompoundExercise(squat) == true)
        #expect(service.isCompoundExercise(deadlift) == true)
        #expect(service.isCompoundExercise(bench) == true)
        #expect(service.isCompoundExercise(curl) == false)
    }

    // MARK: - Volume Bonus

    @Test("Volume bonus scales with total volume")
    func volumeBonusScaling() {
        let exercise = makeExercise(primaryMuscle: .chest, category: .barbell)

        // Light workout: 3x10 @ 60kg = 1800 kg volume
        let lightSets = (0..<3).map { _ in makeSet(weight: 60, reps: 10) }
        let lightWE = makeWorkoutExercise(exercise: exercise, sets: lightSets)
        let lightWorkout = makeWorkout(exercises: [lightWE], durationMinutes: 20)

        // Heavy workout: 5x5 @ 140kg = 3500 kg volume
        let heavySets = (0..<5).map { _ in makeSet(weight: 140, reps: 5) }
        let heavyWE = makeWorkoutExercise(exercise: exercise, sets: heavySets)
        let heavyWorkout = makeWorkout(exercises: [heavyWE], durationMinutes: 30)

        let lightResult = service.estimateCalories(workout: lightWorkout, bodyWeightKg: 80)
        let heavyResult = service.estimateCalories(workout: heavyWorkout, bodyWeightKg: 80)

        #expect(heavyResult.volumeBonus > lightResult.volumeBonus)
    }

    // MARK: - EPOC Factor

    @Test("EPOC factor is 6% minimum")
    func epocMinimum() {
        let factor = service.calculateEpocFactor(averageRPE: nil, compoundRatio: 0)
        #expect(factor == 0.06)
    }

    @Test("EPOC factor is capped at 10% for max RPE")
    func epocMaximum() {
        // EPOC is deliberately capped at 10% (literature upper bound for
        // resistance training), so max RPE yields 0.10, not the nominal 0.15.
        let factor = service.calculateEpocFactor(averageRPE: 10.0, compoundRatio: 0)
        #expect(factor == 0.10)
    }

    @Test("EPOC factor scales with RPE")
    func epocScalesWithRPE() {
        let lowRPE = service.calculateEpocFactor(averageRPE: 5.0, compoundRatio: 0)
        let highRPE = service.calculateEpocFactor(averageRPE: 9.0, compoundRatio: 0)
        #expect(highRPE > lowRPE)
    }

    @Test("EPOC uses compound ratio when no RPE available")
    func epocFallbackToCompoundRatio() {
        let allCompound = service.calculateEpocFactor(averageRPE: nil, compoundRatio: 1.0)
        let allIsolation = service.calculateEpocFactor(averageRPE: nil, compoundRatio: 0.0)
        #expect(allCompound > allIsolation)
        // All-compound hits the deliberate 10% EPOC cap (literature upper bound)
        #expect(allCompound == 0.10)
        #expect(allIsolation == 0.06)
    }

    // MARK: - Warmup Exclusion

    @Test("Warmup sets are excluded from calorie calculation")
    func warmupSetsExcluded() {
        let exercise = makeExercise(primaryMuscle: .quadriceps, category: .barbell)
        let warmupSet = makeSet(weight: 60, reps: 10, setType: .warmup)
        let workingSets = (0..<3).map { _ in makeSet(weight: 100, reps: 5) }

        let withWarmup = makeWorkoutExercise(exercise: exercise, sets: [warmupSet] + workingSets)
        let withoutWarmup = makeWorkoutExercise(exercise: exercise, sets: workingSets)

        let resultWith = service.estimateCalories(
            workout: makeWorkout(exercises: [withWarmup], durationMinutes: 30),
            bodyWeightKg: 80
        )
        let resultWithout = service.estimateCalories(
            workout: makeWorkout(exercises: [withoutWarmup], durationMinutes: 30),
            bodyWeightKg: 80
        )

        // Session calories should be similar since warmup sets are excluded
        // (duration is the same, so MET-based calories are equal)
        #expect(resultWith.sessionCalories == resultWithout.sessionCalories)
    }

    // MARK: - Bodyweight Exercises (No Weight)

    @Test("Bodyweight exercises with nil weight still produce calories")
    func bodyweightNoWeight() {
        let exercise = makeExercise(name: "Push-up", primaryMuscle: .chest, category: .bodyweight)
        let sets = (0..<3).map { _ in makeSet(weight: nil, reps: 20) }
        let we = makeWorkoutExercise(exercise: exercise, sets: sets)
        let workout = makeWorkout(exercises: [we], durationMinutes: 15)

        let result = service.estimateCalories(workout: workout, bodyWeightKg: 75)
        #expect(result.sessionCalories > 0)
        // Volume bonus should be zero since no weight
        #expect(result.volumeBonus == 0)
    }

    // MARK: - Multi-Exercise Workout

    @Test("Multi-exercise workout sums per-exercise calories")
    func multiExerciseWorkout() {
        let squat = makeExercise(name: "Squat", primaryMuscle: .quadriceps, category: .barbell)
        let bench = makeExercise(name: "Bench", primaryMuscle: .chest, category: .barbell)
        let curl = makeExercise(name: "Curl", primaryMuscle: .biceps, category: .dumbbell)

        let squatSets = (0..<5).map { _ in makeSet(weight: 100, reps: 5) }
        let benchSets = (0..<4).map { _ in makeSet(weight: 80, reps: 8) }
        let curlSets = (0..<3).map { _ in makeSet(weight: 15, reps: 12) }

        let exercises = [
            makeWorkoutExercise(exercise: squat, order: 1, sets: squatSets),
            makeWorkoutExercise(exercise: bench, order: 2, sets: benchSets),
            makeWorkoutExercise(exercise: curl, order: 3, sets: curlSets)
        ]
        let workout = makeWorkout(exercises: exercises, durationMinutes: 60)

        let result = service.estimateCalories(workout: workout, bodyWeightKg: 80)
        #expect(result.perExerciseCalories.count == 3)

        let sumPerExercise = result.perExerciseCalories.values.reduce(0, +)
        #expect(abs(sumPerExercise - result.sessionCalories) < 0.01)
    }

    // MARK: - Realistic Range Check

    @Test("Typical workout calories fall within research-validated range")
    func realisticCalorieRange() {
        // João et al. (2021): ~6 kcal/min average for resistance training
        // A 45-min session → ~270 kcal ± EPOC & volume → roughly 150-400 kcal
        let squat = makeExercise(name: "Squat", primaryMuscle: .quadriceps, category: .barbell)
        let bench = makeExercise(name: "Bench Press", primaryMuscle: .chest, category: .barbell)
        let row = makeExercise(name: "Barbell Row", primaryMuscle: .back, category: .barbell)

        let exercises = [
            makeWorkoutExercise(exercise: squat, order: 1, sets: (0..<4).map { _ in makeSet(weight: 100, reps: 8) }),
            makeWorkoutExercise(exercise: bench, order: 2, sets: (0..<4).map { _ in makeSet(weight: 80, reps: 8) }),
            makeWorkoutExercise(exercise: row, order: 3, sets: (0..<4).map { _ in makeSet(weight: 70, reps: 10) })
        ]
        let workout = makeWorkout(exercises: exercises, durationMinutes: 45)

        let result = service.estimateCalories(workout: workout, bodyWeightKg: 80)

        // Should be in a reasonable range for 45 min of strength training
        #expect(result.totalCalories > 100, "Calories too low for a 45-min session")
        #expect(result.totalCalories < 500, "Calories too high for a 45-min session")
    }

    // MARK: - Active/Rest Split

    @Test("Active/rest split does not exceed total duration")
    func activeRestSplitBounds() {
        let sets = (0..<10).map { _ in makeSet() }
        let (active, rest) = service.estimateActiveRestSplit(sets: sets, totalDuration: 600)

        #expect(active + rest == 600)
        #expect(active > 0)
        #expect(rest > 0)
        #expect(active <= 300) // at most 50% active
    }

    @Test("Zero duration returns zero split")
    func zeroDurationSplit() {
        let sets = [makeSet()]
        let (active, rest) = service.estimateActiveRestSplit(sets: sets, totalDuration: 0)
        #expect(active == 0)
        #expect(rest == 0)
    }

    // MARK: - Exercise Duration Distribution

    @Test("Duration is distributed proportionally by set count")
    func durationDistribution() {
        let ex1 = makeExercise(name: "A", primaryMuscle: .chest)
        let ex2 = makeExercise(name: "B", primaryMuscle: .back)

        // Ex1 has 4 sets, Ex2 has 1 set → Ex1 gets 80%, Ex2 gets 20%
        let exercises = [
            makeWorkoutExercise(exercise: ex1, order: 1, sets: (0..<4).map { _ in makeSet() }),
            makeWorkoutExercise(exercise: ex2, order: 2, sets: [makeSet()])
        ]
        let workout = makeWorkout(exercises: exercises, durationMinutes: 50)

        let durations = service.estimateExerciseDurations(workout: workout, totalDuration: 3000)

        let d1 = durations[1] ?? 0
        let d2 = durations[2] ?? 0
        #expect(abs(d1 - 2400) < 1) // 80% of 3000
        #expect(abs(d2 - 600) < 1)  // 20% of 3000
    }
}
