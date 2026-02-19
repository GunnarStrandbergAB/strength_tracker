import Foundation

public enum TemplateSeedData {
    /// Deterministic UUID — same algorithm as ExerciseSeedData
    private static func deterministicUUID(for name: String) -> UUID {
        var hash = [UInt8](repeating: 0, count: 16)
        let nameData = name.utf8

        for (index, byte) in nameData.enumerated() {
            let position = index % 16
            hash[position] = hash[position] &+ byte &+ UInt8(position)
        }

        for i in 0..<16 {
            hash[i] = hash[i] &+ hash[(i + 7) % 16]
        }

        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }

    /// Lookup exercise snapshot from seed data by name
    private static let exercisesByName: [String: Exercise] = {
        Dictionary(uniqueKeysWithValues: ExerciseSeedData.allExercises.map { ($0.name, $0) })
    }()

    private static func exercise(_ name: String) -> Exercise {
        guard let ex = exercisesByName[name] else {
            fatalError("TemplateSeedData references unknown exercise: \(name)")
        }
        return ex
    }

    private static func templateExercise(
        templateName: String,
        exerciseName: String,
        order: Int,
        sets: Int,
        reps: Int,
        restSeconds: Int
    ) -> TemplateExercise {
        TemplateExercise(
            id: deterministicUUID(for: "tpl:\(templateName):\(exerciseName)"),
            exercise: exercise(exerciseName),
            order: order,
            supersetGroup: nil,
            notes: nil,
            restTimerSeconds: restSeconds,
            targetSets: sets,
            targetReps: reps,
            targetWeight: nil,
            targetDurationSeconds: nil,
            targetDistanceMeters: nil
        )
    }

    public static let allTemplates: [WorkoutTemplate] = [
        // MARK: - 1. Push Day
        WorkoutTemplate(
            id: deterministicUUID(for: "template:Push Day"),
            name: "Push Day",
            notes: "Chest, shoulders, triceps",
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                templateExercise(templateName: "Push Day", exerciseName: "Barbell Bench Press", order: 0, sets: 4, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Push Day", exerciseName: "Incline Dumbbell Press", order: 1, sets: 3, reps: 10, restSeconds: 90),
                templateExercise(templateName: "Push Day", exerciseName: "Dumbbell Chest Fly", order: 2, sets: 3, reps: 12, restSeconds: 60),
                templateExercise(templateName: "Push Day", exerciseName: "Overhead Press", order: 3, sets: 3, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Push Day", exerciseName: "Lateral Raise", order: 4, sets: 3, reps: 15, restSeconds: 60),
                templateExercise(templateName: "Push Day", exerciseName: "Tricep Pushdown", order: 5, sets: 3, reps: 12, restSeconds: 60),
            ],
            isCustom: false
        ),

        // MARK: - 2. Pull Day
        WorkoutTemplate(
            id: deterministicUUID(for: "template:Pull Day"),
            name: "Pull Day",
            notes: "Back, biceps",
            sortOrder: 1,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                templateExercise(templateName: "Pull Day", exerciseName: "Barbell Row", order: 0, sets: 4, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Pull Day", exerciseName: "Lat Pulldown", order: 1, sets: 3, reps: 10, restSeconds: 90),
                templateExercise(templateName: "Pull Day", exerciseName: "One-Arm Dumbbell Row", order: 2, sets: 3, reps: 10, restSeconds: 90),
                templateExercise(templateName: "Pull Day", exerciseName: "Pull-Up", order: 3, sets: 3, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Pull Day", exerciseName: "Face Pull", order: 4, sets: 3, reps: 15, restSeconds: 60),
                templateExercise(templateName: "Pull Day", exerciseName: "Barbell Curl", order: 5, sets: 3, reps: 10, restSeconds: 60),
            ],
            isCustom: false
        ),

        // MARK: - 3. Leg Day
        WorkoutTemplate(
            id: deterministicUUID(for: "template:Leg Day"),
            name: "Leg Day",
            notes: "Quads, hamstrings, glutes, calves",
            sortOrder: 2,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                templateExercise(templateName: "Leg Day", exerciseName: "Barbell Back Squat", order: 0, sets: 4, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Leg Day", exerciseName: "Romanian Deadlift", order: 1, sets: 3, reps: 10, restSeconds: 90),
                templateExercise(templateName: "Leg Day", exerciseName: "Leg Press", order: 2, sets: 3, reps: 12, restSeconds: 90),
                templateExercise(templateName: "Leg Day", exerciseName: "Lying Leg Curl", order: 3, sets: 3, reps: 12, restSeconds: 60),
                templateExercise(templateName: "Leg Day", exerciseName: "Walking Lunge", order: 4, sets: 3, reps: 10, restSeconds: 90),
                templateExercise(templateName: "Leg Day", exerciseName: "Standing Calf Raise", order: 5, sets: 3, reps: 15, restSeconds: 60),
            ],
            isCustom: false
        ),

        // MARK: - 4. Upper Body
        WorkoutTemplate(
            id: deterministicUUID(for: "template:Upper Body"),
            name: "Upper Body",
            notes: "Chest, back, shoulders, arms",
            sortOrder: 3,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                templateExercise(templateName: "Upper Body", exerciseName: "Barbell Bench Press", order: 0, sets: 4, reps: 6, restSeconds: 90),
                templateExercise(templateName: "Upper Body", exerciseName: "Barbell Row", order: 1, sets: 4, reps: 6, restSeconds: 90),
                templateExercise(templateName: "Upper Body", exerciseName: "Overhead Press", order: 2, sets: 3, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Upper Body", exerciseName: "Pull-Up", order: 3, sets: 3, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Upper Body", exerciseName: "Dumbbell Curl", order: 4, sets: 3, reps: 10, restSeconds: 60),
                templateExercise(templateName: "Upper Body", exerciseName: "Tricep Pushdown", order: 5, sets: 3, reps: 12, restSeconds: 60),
            ],
            isCustom: false
        ),

        // MARK: - 5. Lower Body
        WorkoutTemplate(
            id: deterministicUUID(for: "template:Lower Body"),
            name: "Lower Body",
            notes: "Quads, hamstrings, glutes",
            sortOrder: 4,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                templateExercise(templateName: "Lower Body", exerciseName: "Barbell Back Squat", order: 0, sets: 4, reps: 6, restSeconds: 90),
                templateExercise(templateName: "Lower Body", exerciseName: "Romanian Deadlift", order: 1, sets: 3, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Lower Body", exerciseName: "Leg Press", order: 2, sets: 3, reps: 10, restSeconds: 90),
                templateExercise(templateName: "Lower Body", exerciseName: "Leg Extension", order: 3, sets: 3, reps: 12, restSeconds: 60),
                templateExercise(templateName: "Lower Body", exerciseName: "Lying Leg Curl", order: 4, sets: 3, reps: 12, restSeconds: 60),
                templateExercise(templateName: "Lower Body", exerciseName: "Standing Calf Raise", order: 5, sets: 3, reps: 15, restSeconds: 60),
            ],
            isCustom: false
        ),

        // MARK: - 6. Full Body A
        WorkoutTemplate(
            id: deterministicUUID(for: "template:Full Body A"),
            name: "Full Body A",
            notes: "Compound-focused",
            sortOrder: 5,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                templateExercise(templateName: "Full Body A", exerciseName: "Barbell Back Squat", order: 0, sets: 3, reps: 5, restSeconds: 90),
                templateExercise(templateName: "Full Body A", exerciseName: "Barbell Bench Press", order: 1, sets: 3, reps: 5, restSeconds: 90),
                templateExercise(templateName: "Full Body A", exerciseName: "Barbell Row", order: 2, sets: 3, reps: 5, restSeconds: 90),
                templateExercise(templateName: "Full Body A", exerciseName: "Overhead Press", order: 3, sets: 3, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Full Body A", exerciseName: "Barbell Curl", order: 4, sets: 3, reps: 10, restSeconds: 60),
            ],
            isCustom: false
        ),

        // MARK: - 7. Full Body B
        WorkoutTemplate(
            id: deterministicUUID(for: "template:Full Body B"),
            name: "Full Body B",
            notes: "Variation day",
            sortOrder: 6,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                templateExercise(templateName: "Full Body B", exerciseName: "Conventional Deadlift", order: 0, sets: 3, reps: 5, restSeconds: 90),
                templateExercise(templateName: "Full Body B", exerciseName: "Incline Barbell Bench Press", order: 1, sets: 3, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Full Body B", exerciseName: "Pull-Up", order: 2, sets: 3, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Full Body B", exerciseName: "Dumbbell Shoulder Press", order: 3, sets: 3, reps: 10, restSeconds: 90),
                templateExercise(templateName: "Full Body B", exerciseName: "Dips", order: 4, sets: 3, reps: 10, restSeconds: 90),
            ],
            isCustom: false
        ),

        // MARK: - 8. Chest & Triceps
        WorkoutTemplate(
            id: deterministicUUID(for: "template:Chest & Triceps"),
            name: "Chest & Triceps",
            notes: "Isolation split",
            sortOrder: 7,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                templateExercise(templateName: "Chest & Triceps", exerciseName: "Barbell Bench Press", order: 0, sets: 4, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Chest & Triceps", exerciseName: "Incline Dumbbell Press", order: 1, sets: 3, reps: 10, restSeconds: 90),
                templateExercise(templateName: "Chest & Triceps", exerciseName: "Dumbbell Chest Fly", order: 2, sets: 3, reps: 12, restSeconds: 60),
                templateExercise(templateName: "Chest & Triceps", exerciseName: "Cable Crossover", order: 3, sets: 3, reps: 15, restSeconds: 60),
                templateExercise(templateName: "Chest & Triceps", exerciseName: "Tricep Pushdown", order: 4, sets: 3, reps: 12, restSeconds: 60),
                templateExercise(templateName: "Chest & Triceps", exerciseName: "Skull Crusher", order: 5, sets: 3, reps: 10, restSeconds: 60),
            ],
            isCustom: false
        ),

        // MARK: - 9. Back & Biceps
        WorkoutTemplate(
            id: deterministicUUID(for: "template:Back & Biceps"),
            name: "Back & Biceps",
            notes: "Isolation split",
            sortOrder: 8,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: [
                templateExercise(templateName: "Back & Biceps", exerciseName: "Barbell Row", order: 0, sets: 4, reps: 8, restSeconds: 90),
                templateExercise(templateName: "Back & Biceps", exerciseName: "Lat Pulldown", order: 1, sets: 3, reps: 10, restSeconds: 90),
                templateExercise(templateName: "Back & Biceps", exerciseName: "Seated Cable Row", order: 2, sets: 3, reps: 12, restSeconds: 90),
                templateExercise(templateName: "Back & Biceps", exerciseName: "Face Pull", order: 3, sets: 3, reps: 15, restSeconds: 60),
                templateExercise(templateName: "Back & Biceps", exerciseName: "Barbell Curl", order: 4, sets: 3, reps: 10, restSeconds: 60),
                templateExercise(templateName: "Back & Biceps", exerciseName: "Hammer Curl", order: 5, sets: 3, reps: 12, restSeconds: 60),
            ],
            isCustom: false
        ),
    ]
}
