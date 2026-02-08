import Foundation

public enum ExerciseSeedData {
    /// Generate deterministic UUID from exercise name
    /// Ensures iPhone and Watch have matching IDs for the same exercises
    private static func deterministicUUID(for name: String) -> UUID {
        // Create stable UUID from exercise name using hash-based approach
        var hash = [UInt8](repeating: 0, count: 16)
        let nameData = name.utf8

        for (index, byte) in nameData.enumerated() {
            let position = index % 16
            hash[position] = hash[position] &+ byte &+ UInt8(position)
        }

        // Additional mixing to improve distribution
        for i in 0..<16 {
            hash[i] = hash[i] &+ hash[(i + 7) % 16]
        }

        // Format as UUID
        let uuid = UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
        return uuid
    }

    public static let allExercises: [Exercise] = [
        // MARK: - Chest Exercises
        Exercise(
            id: deterministicUUID(for: "Barbell Bench Press"),
            name: "Barbell Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Lie on bench, lower bar to chest, press up to full extension",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Incline Barbell Bench Press"),
            name: "Incline Barbell Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Set bench to 30-45 degrees, press barbell from upper chest",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Bench Press"),
            name: "Dumbbell Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Press dumbbells from chest to full extension with controlled motion",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Incline Dumbbell Press"),
            name: "Incline Dumbbell Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Press dumbbells on incline bench targeting upper chest",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Chest Fly"),
            name: "Dumbbell Chest Fly",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Lower dumbbells in wide arc until chest stretch, return to center",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Push-Up"),
            name: "Push-Up",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders, .core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Lower body until chest nearly touches ground, push back up",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Crossover"),
            name: "Cable Crossover",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Pull cable handles together in front of chest with slight bend in elbows",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Back Exercises
        Exercise(
            id: deterministicUUID(for: "Conventional Deadlift"),
            name: "Conventional Deadlift",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.hamstrings, .glutes, .traps, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Lift barbell from floor by extending hips and knees to full stand",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Row"),
            name: "Barbell Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.biceps, .traps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Pull barbell to lower chest while bent at hips, squeeze shoulder blades",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Pull-Up"),
            name: "Pull-Up",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.biceps, .lats],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Pull body up until chin clears bar, lower with control",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Lat Pulldown"),
            name: "Lat Pulldown",
            primaryMuscleGroup: .lats,
            secondaryMuscleGroups: [.biceps, .back],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Pull bar down to upper chest, squeeze shoulder blades together",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Seated Cable Row"),
            name: "Seated Cable Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.biceps, .traps],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Pull handle to torso while keeping back straight, squeeze shoulders back",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "T-Bar Row"),
            name: "T-Bar Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.biceps, .traps],
            category: .landmine,
            exerciseType: .weightedReps,
            instructions: "Pull T-bar to chest while maintaining hip hinge position",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "One-Arm Dumbbell Row"),
            name: "One-Arm Dumbbell Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.biceps, .traps],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Pull dumbbell to hip while bracing on bench, keep back flat",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Shoulder Exercises
        Exercise(
            id: deterministicUUID(for: "Overhead Press"),
            name: "Overhead Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Press barbell overhead from shoulders to full lockout",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Shoulder Press"),
            name: "Dumbbell Shoulder Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Press dumbbells overhead from shoulder height to full extension",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Lateral Raise"),
            name: "Lateral Raise",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Raise dumbbells to sides until arms parallel with floor",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Front Raise"),
            name: "Front Raise",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Raise dumbbells to front until arms parallel with floor",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Face Pull"),
            name: "Face Pull",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.traps],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Pull rope attachment to face, externally rotate shoulders at end",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Reverse Pec Deck Fly"),
            name: "Reverse Pec Deck Fly",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.back],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Pull handles apart targeting rear deltoids, squeeze shoulder blades",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Biceps Exercises
        Exercise(
            id: deterministicUUID(for: "Barbell Curl"),
            name: "Barbell Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Curl barbell from thighs to shoulders, keep elbows stationary",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Curl"),
            name: "Dumbbell Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Curl dumbbells alternating or together, supinate wrists at top",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Hammer Curl"),
            name: "Hammer Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Curl dumbbells with neutral grip, targeting brachialis",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Preacher Curl"),
            name: "Preacher Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .ezBar,
            exerciseType: .weightedReps,
            instructions: "Curl EZ bar on preacher bench, isolating biceps",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Curl"),
            name: "Cable Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Curl cable attachment with constant tension throughout movement",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Triceps Exercises
        Exercise(
            id: deterministicUUID(for: "Tricep Pushdown"),
            name: "Tricep Pushdown",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Push cable attachment down until arms fully extended, control return",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Skull Crusher"),
            name: "Skull Crusher",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Lower bar to forehead by bending elbows, extend back to start",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Overhead Tricep Extension"),
            name: "Overhead Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Extend dumbbell overhead from behind head, keep elbows in",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dips"),
            name: "Dips",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.chest, .shoulders],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Lower body by bending elbows, push back up to full extension",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Close-Grip Bench Press"),
            name: "Close-Grip Bench Press",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.chest, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Press barbell with hands shoulder-width apart, emphasizing triceps",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Quadriceps Exercises
        Exercise(
            id: deterministicUUID(for: "Barbell Back Squat"),
            name: "Barbell Back Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .hamstrings, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Squat down with bar on back until thighs parallel, drive up through heels",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Front Squat"),
            name: "Front Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Squat with bar on front shoulders, keep torso upright",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Goblet Squat"),
            name: "Goblet Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .core],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Hold dumbbell at chest, squat down keeping elbows inside knees",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Leg Press"),
            name: "Leg Press",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .hamstrings],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Press platform away by extending knees and hips to full extension",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Leg Extension"),
            name: "Leg Extension",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Extend knees to raise pad, squeeze quads at top, lower with control",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Walking Lunge"),
            name: "Walking Lunge",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .hamstrings],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Step forward into lunge, drive through front heel to next step",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Bulgarian Split Squat"),
            name: "Bulgarian Split Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Squat with rear foot elevated on bench, front leg does the work",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Hamstring Exercises
        Exercise(
            id: deterministicUUID(for: "Romanian Deadlift"),
            name: "Romanian Deadlift",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .back],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Hinge at hips lowering bar down legs, feel hamstring stretch, return",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Lying Leg Curl"),
            name: "Lying Leg Curl",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Curl pad toward glutes by flexing knees, squeeze hamstrings",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Seated Leg Curl"),
            name: "Seated Leg Curl",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Curl pad down by flexing knees while seated, focus on hamstrings",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Good Morning"),
            name: "Good Morning",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .back],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Hinge at hips with bar on back, maintain straight back throughout",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Nordic Curl"),
            name: "Nordic Curl",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Lower body forward with knees anchored, use hamstrings to control descent",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Glute Exercises
        Exercise(
            id: deterministicUUID(for: "Hip Thrust"),
            name: "Hip Thrust",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Thrust hips up from bench with bar on hips, squeeze glutes at top",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Glute Bridge"),
            name: "Glute Bridge",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Thrust hips up from floor with bar on hips, squeeze glutes at top",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Pull-Through"),
            name: "Cable Pull-Through",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Pull cable between legs by extending hips, squeeze glutes forward",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Kickback"),
            name: "Cable Kickback",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Kick leg back against cable resistance, squeeze glute at extension",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Core Exercises
        Exercise(
            id: deterministicUUID(for: "Plank"),
            name: "Plank",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.shoulders],
            category: .bodyweight,
            exerciseType: .duration,
            instructions: "Hold body straight from head to heels on forearms, engage core",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Ab Rollout"),
            name: "Ab Rollout",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.back, .shoulders],
            category: .other,
            exerciseType: .weightedReps,
            instructions: "Roll wheel forward extending body, pull back with core engaged",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Crunch"),
            name: "Cable Crunch",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Crunch down bringing elbows to knees, squeeze abs at bottom",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Hanging Leg Raise"),
            name: "Hanging Leg Raise",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Raise legs to parallel or higher while hanging, control descent",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Russian Twist"),
            name: "Russian Twist",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [],
            category: .plate,
            exerciseType: .weightedReps,
            instructions: "Rotate torso side to side with plate, keep core engaged throughout",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dead Bug"),
            name: "Dead Bug",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Alternate extending opposite arm and leg while maintaining flat back",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Calves Exercises
        Exercise(
            id: deterministicUUID(for: "Standing Calf Raise"),
            name: "Standing Calf Raise",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Raise up on toes while standing, squeeze calves at top, full stretch at bottom",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Seated Calf Raise"),
            name: "Seated Calf Raise",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Raise heels while seated with weight on knees, full range of motion",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Calf Press on Leg Press"),
            name: "Calf Press on Leg Press",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Press platform with toes only, full extension and stretch",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Trap Exercises
        Exercise(
            id: deterministicUUID(for: "Barbell Shrug"),
            name: "Barbell Shrug",
            primaryMuscleGroup: .traps,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Shrug shoulders straight up toward ears with barbell, squeeze at top",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Shrug"),
            name: "Dumbbell Shrug",
            primaryMuscleGroup: .traps,
            secondaryMuscleGroups: [],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Shrug shoulders up with dumbbells at sides, hold peak contraction",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Full Body / Compound Exercises
        Exercise(
            id: deterministicUUID(for: "Clean and Press"),
            name: "Clean and Press",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.shoulders, .back, .quadriceps, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Clean bar to shoulders, then press overhead in one fluid motion",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Thruster"),
            name: "Thruster",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.quadriceps, .shoulders, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Front squat transitioning into overhead press in one movement",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Burpee"),
            name: "Burpee",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.chest, .core, .quadriceps],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Drop to push-up, perform push-up, jump feet to hands, jump up",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Swing"),
            name: "Kettlebell Swing",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.glutes, .hamstrings, .shoulders, .core],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Swing kettlebell from between legs to shoulder height using hip power",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Man Maker"),
            name: "Man Maker",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.chest, .back, .shoulders, .core],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Push-up with dumbbells, row each arm, clean to squat, press overhead",
            isCustom: false,
            isArchived: false
        )
    ]
}
