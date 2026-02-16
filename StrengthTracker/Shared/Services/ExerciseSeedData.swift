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
        ),

        // MARK: - === NEW EXERCISES (235 additions) ===

        // MARK: - Chest (new)
        Exercise(
            id: deterministicUUID(for: "Decline Barbell Bench Press"),
            name: "Decline Barbell Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Lie on a decline bench, lower the barbell to your lower chest, then press back up to full extension.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Wide-Grip Barbell Bench Press"),
            name: "Wide-Grip Barbell Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Bench press with a grip 1.5× shoulder width to increase pec stretch and emphasize the outer chest.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Reverse-Grip Barbell Bench Press"),
            name: "Reverse-Grip Barbell Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Bench press with a supinated (underhand) grip at shoulder width, lowering the bar to your lower chest to emphasize the upper chest.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Floor Press"),
            name: "Barbell Floor Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Lie on the floor, lower the barbell until upper arms contact the ground, pause, then press up — limits ROM and builds lockout strength.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Landmine Chest Press"),
            name: "Landmine Chest Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Anchor one end of a barbell in a landmine, clasp the free end at chest level, and press up and away to target the upper chest.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Decline Dumbbell Bench Press"),
            name: "Decline Dumbbell Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Press dumbbells from chest level on a decline bench, emphasizing the lower pecs.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Floor Press"),
            name: "Dumbbell Floor Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Lie on the floor holding dumbbells at chest level, press up to full extension, lower until upper arms touch the floor.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Single-Arm Dumbbell Bench Press"),
            name: "Single-Arm Dumbbell Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .core],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Press one dumbbell from a flat bench while bracing your core to resist rotation; alternate arms between sets.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Pullover"),
            name: "Dumbbell Pullover",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.lats, .triceps],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Lie across a bench, hold one dumbbell overhead with both hands, lower in an arc behind your head, then pull it back over your chest.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Incline Dumbbell Fly"),
            name: "Incline Dumbbell Fly",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "On a 30–45° incline bench, lower dumbbells in a wide arc with slight elbow bend, then squeeze pecs to bring weights together.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Squeeze Press"),
            name: "Dumbbell Squeeze Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Press two hex dumbbells together with neutral grip on a flat bench, maintaining constant inward pressure throughout to maximize inner pec contraction.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "High-to-Low Cable Crossover"),
            name: "High-to-Low Cable Crossover",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "With pulleys set high, step forward and bring handles down and together in front of your hips in a sweeping arc.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Low-to-High Cable Fly"),
            name: "Low-to-High Cable Fly",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "With pulleys set low, bring handles up and together in front of your upper chest, targeting the upper pecs.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Standing Cable Chest Press"),
            name: "Standing Cable Chest Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Set pulleys to chest height, face away, and press handles forward until arms are fully extended.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Machine Chest Press"),
            name: "Machine Chest Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Press handles forward from mid-chest level to full arm extension, then return slowly.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Machine Incline Chest Press"),
            name: "Machine Incline Chest Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Press handles forward and upward from upper-chest level to full extension on an incline press machine.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Pec Deck"),
            name: "Pec Deck",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Squeeze pads or handles together in front of your chest, then return slowly to feel a pec stretch.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Bench Press"),
            name: "Smith Machine Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Flat bench press on the Smith machine for added stability and heavier loading.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Incline Bench Press"),
            name: "Smith Machine Incline Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Incline bench press (30–45°) on the Smith machine, targeting upper pecs with guided stability.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Decline Bench Press"),
            name: "Smith Machine Decline Bench Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Decline bench press on the Smith machine, emphasizing the lower pecs.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Svend Press"),
            name: "Svend Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders],
            category: .plate,
            exerciseType: .weightedReps,
            instructions: "Standing, squeeze weight plates between palms at chest level and press straight out, then return — maximizes inner pec contraction.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Floor Press"),
            name: "Kettlebell Floor Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.triceps, .shoulders],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Lie on the floor, press a kettlebell from shoulder level to full extension with one arm; repeat both sides.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Band Chest Press"),
            name: "Band Chest Press",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Loop a band across your upper back and press forward until arms are extended, squeezing the chest at peak contraction.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Decline Push-Up"),
            name: "Decline Push-Up",
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [.shoulders, .triceps],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Push-up with feet elevated on a bench, placing greater emphasis on the upper chest and shoulders.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Back (new)
        Exercise(
            id: deterministicUUID(for: "Pendlay Row"),
            name: "Pendlay Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps, .traps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "With torso parallel to the floor, explosively row a barbell from a dead stop on the ground to your abdomen each rep.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Yates Row"),
            name: "Yates Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Bent-over row with a supinated grip and more upright torso (~70°), pulling to your lower abdomen.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Seal Row"),
            name: "Seal Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .traps, .biceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Lie face-down on an elevated bench and row a barbell from a dead hang, completely eliminating lower-back involvement.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Rack Row"),
            name: "Rack Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.traps, .lats, .biceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Row a barbell from safety pins at knee height, allowing heavier loading for upper-back thickness.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "EZ Bar Bent-Over Row"),
            name: "EZ Bar Bent-Over Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps, .traps],
            category: .ezBar,
            exerciseType: .weightedReps,
            instructions: "Hinge forward and row an EZ bar toward your abdomen — the angled grip reduces wrist strain.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kroc Row"),
            name: "Kroc Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .traps, .forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Heavy, high-rep single-arm dumbbell rows (15–25+ reps) with controlled body English while bracing against a bench.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Chest-Supported Dumbbell Row"),
            name: "Chest-Supported Dumbbell Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Lie face-down on a 30–45° incline bench and row two dumbbells toward your hips, squeezing shoulder blades together.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Helms Row"),
            name: "Helms Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Chest-down on a low-incline bench (~30°), perform single-arm dumbbell rows with zero momentum.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Single-Arm Cable Row"),
            name: "Single-Arm Cable Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps, .core],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Row a D-handle to your hip with one arm from a low cable while keeping your torso square.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Wide-Grip Cable Row"),
            name: "Wide-Grip Cable Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.traps, .shoulders, .biceps],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Seated cable row with a wide-grip bar and elbows flared out to emphasize the middle traps and rhomboids.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Chest-Supported Machine Row"),
            name: "Chest-Supported Machine Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps, .traps],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Sit braced against the chest pad and pull handles toward your torso, squeezing shoulder blades at the top.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Inverted Row"),
            name: "Inverted Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps, .core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Hang under a barbell set at waist height, body straight, and row your chest to the bar.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Renegade Row"),
            name: "Renegade Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.core, .lats, .shoulders],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "From a high plank on two kettlebells, row one to your hip while pressing the other into the ground; alternate sides.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Gorilla Row"),
            name: "Gorilla Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .core, .forearms],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Hinge over two kettlebells, alternately row one while pressing the other into the ground for stability.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Band Bent-Over Row"),
            name: "Band Bent-Over Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps, .traps],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Stand on a band, hinge forward, and row both ends toward your abdomen.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Band Pull-Apart"),
            name: "Band Pull-Apart",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.shoulders, .traps],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Hold a band at arms' length in front of you and pull it apart by retracting your shoulder blades until the band touches your chest.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Bent-Over Row"),
            name: "Smith Machine Bent-Over Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .biceps, .traps],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Hinge forward under the Smith machine bar and row along the fixed guided path.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Trap Bar Row"),
            name: "Trap Bar Row",
            primaryMuscleGroup: .back,
            secondaryMuscleGroups: [.lats, .traps, .forearms],
            category: .trapBar,
            exerciseType: .weightedReps,
            instructions: "Stand inside a loaded trap bar, hinge forward, and row upward using the neutral-grip handles.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Lats (new)
        Exercise(
            id: deterministicUUID(for: "Meadows Row"),
            name: "Meadows Row",
            primaryMuscleGroup: .lats,
            secondaryMuscleGroups: [.back, .biceps, .forearms],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Stand perpendicular to a landmine, grip the thick end with one hand, and row toward your hip. Named after bodybuilder John Meadows.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Pullover"),
            name: "Barbell Pullover",
            primaryMuscleGroup: .lats,
            secondaryMuscleGroups: [.chest, .triceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Lie on a bench, lower a barbell behind your head in an arc until you feel a lat stretch, then pull back over your chest.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Straight-Arm Pulldown"),
            name: "Straight-Arm Pulldown",
            primaryMuscleGroup: .lats,
            secondaryMuscleGroups: [.triceps, .core],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Stand facing a high pulley with a straight bar, keep arms nearly straight, and pull the bar down to your thighs.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Close-Grip Lat Pulldown"),
            name: "Close-Grip Lat Pulldown",
            primaryMuscleGroup: .lats,
            secondaryMuscleGroups: [.biceps, .back],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Using a V-handle on a lat pulldown, pull to your upper chest with elbows driving close to your sides.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Reverse-Grip Lat Pulldown"),
            name: "Reverse-Grip Lat Pulldown",
            primaryMuscleGroup: .lats,
            secondaryMuscleGroups: [.biceps, .back],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Lat pulldown with a supinated shoulder-width grip, emphasizing the lower lats and increasing bicep recruitment.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Single-Arm Lat Pulldown"),
            name: "Single-Arm Lat Pulldown",
            primaryMuscleGroup: .lats,
            secondaryMuscleGroups: [.biceps, .core],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Pull down with one arm using a D-handle, allowing slight torso rotation to maximize lat contraction.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Pullover"),
            name: "Cable Pullover",
            primaryMuscleGroup: .lats,
            secondaryMuscleGroups: [.core, .triceps],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Stand facing a high pulley, pull the attachment down in an arc to your hips with straight arms.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Machine High Row"),
            name: "Machine High Row",
            primaryMuscleGroup: .lats,
            secondaryMuscleGroups: [.back, .biceps],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Pull handles downward and toward your torso in a combined pulldown/row motion on a converging high-row machine.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Shoulders (new)
        Exercise(
            id: deterministicUUID(for: "Arnold Press"),
            name: "Arnold Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps, .chest],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Press dumbbells overhead while rotating wrists from palms-facing-you at the bottom to palms-forward at the top.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Front Raise"),
            name: "Barbell Front Raise",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.chest],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Standing, raise a barbell from thigh level to shoulder height with straight arms, then lower slowly.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Front Raise"),
            name: "Dumbbell Front Raise",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.chest],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Raise one or both dumbbells from your thighs to shoulder height in front of you with a slight elbow bend.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Lateral Raise"),
            name: "Cable Lateral Raise",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.traps],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Stand sideways to a low pulley, grasp the handle with the far hand, and raise your arm to shoulder height.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Front Raise"),
            name: "Cable Front Raise",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.chest],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Facing away from a low pulley, raise the handle in front of you to shoulder height with a straight arm.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Upright Row"),
            name: "Barbell Upright Row",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.traps, .biceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Pull a barbell straight up along your body to chin level, leading with elbows, then lower with control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Upright Row"),
            name: "Cable Upright Row",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.traps, .biceps],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Pull a straight bar from a low cable up along your torso to chin height, leading with elbows.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Machine Shoulder Press"),
            name: "Machine Shoulder Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Press handles overhead from shoulder height until arms are fully extended, then lower under control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Shoulder Press"),
            name: "Smith Machine Shoulder Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Seated overhead press on the Smith machine for heavier, more stable loading.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Single-Arm Landmine Press"),
            name: "Single-Arm Landmine Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.chest, .triceps, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Hold the loaded end of a landmine barbell at shoulder height with one hand and press up and forward to extension.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Z Press"),
            name: "Z Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Sit on the floor with legs extended and press a barbell overhead with no leg drive or back support — demands exceptional core stability.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Push Press"),
            name: "Push Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps, .glutes, .quadriceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "From a front rack, dip at the knees then explosively drive the barbell overhead using leg power.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Behind-the-Neck Press"),
            name: "Behind-the-Neck Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps, .traps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Press a barbell from behind your neck to overhead lockout. Requires good shoulder mobility.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Single-Arm Press"),
            name: "Kettlebell Single-Arm Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps, .core],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Clean a kettlebell to the rack position and press overhead to full lockout while bracing your core.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Band Shoulder Press"),
            name: "Band Shoulder Press",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Stand on a band and press both ends from shoulder height to overhead.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Band Lateral Raise"),
            name: "Band Lateral Raise",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.traps],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Stand on a band, raise both arms to your sides to shoulder height with a slight elbow bend.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Plate Front Raise"),
            name: "Plate Front Raise",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.chest, .core],
            category: .plate,
            exerciseType: .weightedReps,
            instructions: "Raise a weight plate from thigh level to shoulder height or overhead with both hands and straight arms.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Machine Lateral Raise"),
            name: "Machine Lateral Raise",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.traps],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Raise arm pads outward to shoulder height on the lateral raise machine, squeeze at the top, lower slowly.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Reverse Pec Deck"),
            name: "Reverse Pec Deck",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.traps, .back],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Face the pad on a pec deck, pull handles back in a reverse fly motion, squeezing rear deltoids and shoulder blades.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Rear Delt Fly"),
            name: "Dumbbell Rear Delt Fly",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.traps, .back],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Bent forward at the hips, raise dumbbells to your sides with a slight elbow bend, squeezing the rear delts at the top.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Pike Push-Up"),
            name: "Pike Push-Up",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps, .chest],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "From a push-up position, walk feet toward hands forming an inverted V, then lower your head toward the floor and press back up.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Handstand Push-Up"),
            name: "Handstand Push-Up",
            primaryMuscleGroup: .shoulders,
            secondaryMuscleGroups: [.triceps, .traps],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "In a handstand against a wall, lower your head toward the ground by bending elbows, then press to full arm extension.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Traps (new)
        Exercise(
            id: deterministicUUID(for: "Cable Shrug"),
            name: "Cable Shrug",
            primaryMuscleGroup: .traps,
            secondaryMuscleGroups: [.forearms],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Shrug your shoulders toward your ears holding a straight bar from a low cable, squeezing for 2–3 seconds at the top.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Trap Bar Shrug"),
            name: "Trap Bar Shrug",
            primaryMuscleGroup: .traps,
            secondaryMuscleGroups: [.forearms],
            category: .trapBar,
            exerciseType: .weightedReps,
            instructions: "Stand inside a loaded trap bar and shrug straight up with the neutral handles for heavy, stable trap loading.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Shrug"),
            name: "Smith Machine Shrug",
            primaryMuscleGroup: .traps,
            secondaryMuscleGroups: [.forearms],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Shrug on the Smith machine for guided, heavy trap work.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Upright Row"),
            name: "Dumbbell Upright Row",
            primaryMuscleGroup: .traps,
            secondaryMuscleGroups: [.shoulders, .biceps],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Pull dumbbells up along your body leading with elbows to chest height; the free path allows natural shoulder movement.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Incline Prone Dumbbell Shrug"),
            name: "Incline Prone Dumbbell Shrug",
            primaryMuscleGroup: .traps,
            secondaryMuscleGroups: [.back],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Lie face-down on a 45° incline bench and shrug by squeezing shoulder blades up and together, targeting middle and lower traps.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Prone Y-Raise"),
            name: "Prone Y-Raise",
            primaryMuscleGroup: .traps,
            secondaryMuscleGroups: [.shoulders],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Face-down on an incline bench, raise light dumbbells overhead in a \"Y\" shape with thumbs up, focusing on lower-trap activation.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Band Shrug"),
            name: "Band Shrug",
            primaryMuscleGroup: .traps,
            secondaryMuscleGroups: [.forearms],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Stand on a band, hold both ends, and shrug against the increasing resistance, pausing at the top.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Biceps (new)
        Exercise(
            id: deterministicUUID(for: "Incline Dumbbell Curl"),
            name: "Incline Dumbbell Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Sit on a 45° incline bench, let dumbbells hang, and curl to shoulders — emphasizes the long head in a stretched position.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Concentration Curl"),
            name: "Concentration Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Seated, brace the back of your upper arm against your inner thigh and curl a dumbbell with strict isolation.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Spider Curl"),
            name: "Spider Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Face-down on an incline bench with arms hanging straight, curl dumbbells upward for maximum peak contraction with no momentum.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Zottman Curl"),
            name: "Zottman Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Curl dumbbells up palms-up, rotate to palms-down at the top, then lower slowly with the pronated grip to overload forearms eccentrically.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Incline Hammer Curl"),
            name: "Incline Hammer Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "On a 45° incline bench, curl dumbbells with a neutral (hammer) grip to emphasize the long head and brachialis.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cross-Body Hammer Curl"),
            name: "Cross-Body Hammer Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Curl one dumbbell across your body toward the opposite shoulder with a neutral grip, targeting the brachialis.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Bayesian Curl"),
            name: "Bayesian Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Face away from a low cable, hold a D-handle with your arm behind your torso, and curl forward — maximizes long-head stretch.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Standing Cable Curl"),
            name: "Standing Cable Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Curl a bar or EZ attachment from a low cable toward your shoulders, benefiting from constant tension throughout.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "High Cable Curl"),
            name: "High Cable Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Stand between two high pulleys with arms in a \"T\" position, curl fists toward ears while keeping upper arms fixed.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Rope Hammer Curl"),
            name: "Cable Rope Hammer Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Curl a rope attachment from a low cable with a neutral grip, elbows pinned to your sides.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Drag Curl"),
            name: "Barbell Drag Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Curl a barbell while dragging it up along your torso by pulling elbows back, minimizing front-delt involvement.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Machine Bicep Curl"),
            name: "Machine Bicep Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Curl handles toward shoulders on a preacher-style machine for strict, cheat-proof isolation.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Band Bicep Curl"),
            name: "Band Bicep Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Stand on a band, curl with a supinated grip against ascending resistance that peaks at the top.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Curl"),
            name: "Kettlebell Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Curl a kettlebell by the handle — the offset, bottom-heavy center of gravity uniquely challenges grip and stabilization.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "EZ Bar Spider Curl"),
            name: "EZ Bar Spider Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .ezBar,
            exerciseType: .weightedReps,
            instructions: "Face-down on an incline bench, curl an EZ bar with arms hanging vertical for strict peak contraction.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Drag Curl"),
            name: "Smith Machine Drag Curl",
            primaryMuscleGroup: .biceps,
            secondaryMuscleGroups: [.forearms],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Drag the bar up your torso on the Smith machine by pulling elbows back — the guided path enforces strict form.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Triceps (new)
        Exercise(
            id: deterministicUUID(for: "Cable Overhead Tricep Extension"),
            name: "Cable Overhead Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.shoulders],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Face away from a high pulley, hold a rope behind your head, and extend arms overhead to full lockout.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Single-Arm Cable Tricep Extension"),
            name: "Single-Arm Cable Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "With a high cable, keep your elbow pinned and extend one arm down to full lockout.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Reverse-Grip Tricep Pushdown"),
            name: "Reverse-Grip Tricep Pushdown",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.forearms],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Pushdown with an underhand grip on a straight bar, emphasizing the medial head of the triceps.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Tricep Kickback"),
            name: "Cable Tricep Kickback",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Hinge forward, pull elbow back, then extend your forearm straight behind you from a low cable.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Overhead Tricep Extension"),
            name: "Dumbbell Overhead Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.shoulders],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Hold one dumbbell overhead with both hands, lower behind your head by bending elbows, then extend back up.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Single-Arm Dumbbell Overhead Extension"),
            name: "Single-Arm Dumbbell Overhead Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.shoulders],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "One arm at a time, lower a dumbbell behind your head then extend to lockout.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Kickback"),
            name: "Dumbbell Kickback",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Hinged forward, upper arm parallel to floor, extend your forearm back until straight, squeeze, then lower.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Tate Press"),
            name: "Tate Press",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.chest],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "On a flat bench, lower dumbbells inward toward your chest by bending elbows outward, then press up — named after powerlifter Dave Tate.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Overhead Tricep Extension"),
            name: "Barbell Overhead Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Hold a barbell overhead, lower behind your head by bending elbows, then extend back to the start.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "JM Press"),
            name: "JM Press",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.chest, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "On a flat bench with a close grip, lower the bar toward your throat in a skull-crusher/close-grip bench hybrid, then press to lockout.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "California Press"),
            name: "California Press",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.chest, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Close-grip bench variant where you lower to your upper chest/neck area combining a skull-crusher path with a pressing motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "EZ Bar Overhead Tricep Extension"),
            name: "EZ Bar Overhead Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.shoulders],
            category: .ezBar,
            exerciseType: .weightedReps,
            instructions: "Hold an EZ bar overhead on the inner angled grips, lower behind your head, then extend — the angled grip reduces wrist strain.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Diamond Push-Up"),
            name: "Diamond Push-Up",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.chest, .shoulders],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Push-up with hands close together forming a diamond shape, elbows tucked to your sides.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Bench Dip"),
            name: "Bench Dip",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.chest, .shoulders],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Hands gripping a bench edge behind you, lower body by bending elbows to ~90°, then press back up.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Bodyweight Tricep Extension"),
            name: "Bodyweight Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.core, .shoulders],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Hands on a bar at waist height, lean forward and lower your forehead toward the bar bending only at the elbows, then extend.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Machine Tricep Extension"),
            name: "Machine Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Seated, extend elbows against resistance until arms are straight, then return slowly.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Machine Tricep Dip"),
            name: "Machine Tricep Dip",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.chest, .shoulders],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Press handles down by extending elbows on the lever dip machine.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Band Overhead Tricep Extension"),
            name: "Band Overhead Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.shoulders],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Stand on one end of a band, hold the other behind your head, and extend arms overhead against resistance.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Overhead Tricep Extension"),
            name: "Kettlebell Overhead Tricep Extension",
            primaryMuscleGroup: .triceps,
            secondaryMuscleGroups: [.shoulders],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Hold a kettlebell by the horns overhead, lower behind your head, then extend back up.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Forearms (new)
        Exercise(
            id: deterministicUUID(for: "Barbell Wrist Curl"),
            name: "Barbell Wrist Curl",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [.biceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Forearms on thighs (palms up), curl the barbell by flexing your wrists, then lower with control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Reverse Wrist Curl"),
            name: "Barbell Reverse Wrist Curl",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Forearms on thighs (palms down), raise the barbell by extending your wrists to target forearm extensors.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Wrist Curl"),
            name: "Dumbbell Wrist Curl",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [.biceps],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Forearms on thighs (palms up), curl dumbbells by flexing wrists through a full range of motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Reverse Wrist Curl"),
            name: "Dumbbell Reverse Wrist Curl",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Forearms on thighs (palms down), extend wrists upward to target forearm extensors.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Behind-the-Back Barbell Wrist Curl"),
            name: "Behind-the-Back Barbell Wrist Curl",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [.biceps],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Stand holding a barbell behind your back, let it roll to your fingertips, then curl back up by flexing wrists and closing fingers.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Wrist Curl"),
            name: "Cable Wrist Curl",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [.biceps],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Kneel facing a low cable, forearms on a bench (palms up), and flex wrists to curl the attachment upward.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Wrist Roller"),
            name: "Wrist Roller",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [.shoulders],
            category: .other,
            exerciseType: .weightedReps,
            instructions: "Hold a wrist roller at arms' length, roll the weighted cord up by alternating wrist rotations, then slowly unroll.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Plate Pinch Hold"),
            name: "Plate Pinch Hold",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [],
            category: .plate,
            exerciseType: .duration,
            instructions: "Pinch two smooth weight plates together with fingertips and thumb, lift off the ground, and hold for max time.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dead Hang"),
            name: "Dead Hang",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [.lats, .core],
            category: .bodyweight,
            exerciseType: .duration,
            instructions: "Hang from a pull-up bar with arms fully extended, maintaining a firm grip for as long as possible.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Towel Hang"),
            name: "Towel Hang",
            primaryMuscleGroup: .forearms,
            secondaryMuscleGroups: [.lats, .biceps],
            category: .bodyweight,
            exerciseType: .duration,
            instructions: "Drape a thick towel over a pull-up bar, grip each end, and hang for time — the unstable surface dramatically increases grip demand.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Quadriceps (new)
        Exercise(
            id: deterministicUUID(for: "Barbell Front Squat"),
            name: "Barbell Front Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .core, .hamstrings],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Hold barbell across front deltoids with elbows high, squat until thighs are at least parallel, then drive through heels.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Zercher Squat"),
            name: "Zercher Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Cradle the barbell in the crooks of your elbows, squat to parallel with an upright posture, then stand.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Jefferson Squat"),
            name: "Jefferson Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .adductors, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Straddle a barbell with one foot forward and one back, grip with alternating hands, and squat. Alternate foot positions between sets.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Step-Up"),
            name: "Dumbbell Step-Up",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .hamstrings],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Hold dumbbells at your sides, step onto a box leading with one foot, drive through the heel to stand on top, then step down.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Hack Squat"),
            name: "Hack Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .hamstrings],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Back against the sled pad, shoulders under pads, lower until thighs are parallel, then press through the full foot.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Belt Squat"),
            name: "Belt Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .adductors],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "With a weight belt around your hips connected to the machine, squat to parallel standing on elevated platforms, then drive up.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Pendulum Squat"),
            name: "Pendulum Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .hamstrings],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Under shoulder pads on the pendulum machine, squat deep following the machine's arc, then drive through feet.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Front Squat"),
            name: "Smith Machine Front Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .core],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Front squat on the Smith machine with bar across front deltoids, feet slightly forward for upright torso.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Trap Bar Squat"),
            name: "Trap Bar Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .hamstrings, .core],
            category: .trapBar,
            exerciseType: .weightedReps,
            instructions: "Stand inside a trap bar with an upright torso, squat down keeping weight centered and chest up, then extend to stand.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Spanish Squat"),
            name: "Spanish Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Loop a thick band behind both knees anchored at knee height, lean back into the tension and squat with an upright torso.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Landmine Squat"),
            name: "Landmine Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .core],
            category: .landmine,
            exerciseType: .weightedReps,
            instructions: "Hold the free end of a landmine barbell at chest height and squat with an upright torso, then stand.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Sissy Squat"),
            name: "Sissy Squat",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.core, .hipFlexors],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Stand on the balls of your feet, lean torso back while bending knees forward with hips fully extended, then use quads to return.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Poliquin Step-Up"),
            name: "Poliquin Step-Up",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.calves, .glutes],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "On a slant board on an elevated surface, slowly step down by bending the working knee forward, tap opposite heel to floor, then extend.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Peterson Step-Up"),
            name: "Peterson Step-Up",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.calves, .glutes],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "On an elevated surface, rise onto the ball of your working foot, step down bending the knee forward past the toes, then return.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Reverse Nordic Curl"),
            name: "Reverse Nordic Curl",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Kneel upright with hips locked forward, lean back by bending only at the knees, then use quad strength to pull back up.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Wall Sit"),
            name: "Wall Sit",
            primaryMuscleGroup: .quadriceps,
            secondaryMuscleGroups: [.glutes, .core],
            category: .bodyweight,
            exerciseType: .duration,
            instructions: "Back flat against a wall, thighs parallel to the floor, knees at 90°. Hold for time.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Hamstrings (new)
        Exercise(
            id: deterministicUUID(for: "Barbell Good Morning"),
            name: "Barbell Good Morning",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .lowerBack],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Barbell on upper back, hinge forward at the hips with slight knee bend until torso is near parallel, then extend hips to stand.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "EZ Bar Good Morning"),
            name: "EZ Bar Good Morning",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .lowerBack],
            category: .ezBar,
            exerciseType: .weightedReps,
            instructions: "Good morning performed with an EZ bar — the angled grips offer more comfortable wrist positioning.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Stiff-Leg Deadlift"),
            name: "Dumbbell Stiff-Leg Deadlift",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .lowerBack],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Hinge at the hips with nearly straight legs, lower dumbbells toward the floor until deep hamstring stretch, then drive hips forward.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Single-Leg Dumbbell Romanian Deadlift"),
            name: "Single-Leg Dumbbell Romanian Deadlift",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .core],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Hold a dumbbell opposite your standing leg, hinge at the hip extending the free leg behind you, then return to standing.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Glute-Ham Raise"),
            name: "Glute-Ham Raise",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .lowerBack],
            category: .machine,
            exerciseType: .bodyweightReps,
            instructions: "On a GHD, lower your torso by extending at the knees, then powerfully curl back up using hamstring contraction with hips extended.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Nordic Hamstring Curl"),
            name: "Nordic Hamstring Curl",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Ankles secured, slowly lower your torso toward the ground resisting with hamstrings, then pull back up or push off to return.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Sliding Leg Curl"),
            name: "Sliding Leg Curl",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "On your back with heels on sliders, bridge hips up, slide heels away to extend legs, then curl back in while staying elevated.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Trap Bar Romanian Deadlift"),
            name: "Trap Bar Romanian Deadlift",
            primaryMuscleGroup: .hamstrings,
            secondaryMuscleGroups: [.glutes, .lowerBack],
            category: .trapBar,
            exerciseType: .weightedReps,
            instructions: "Inside a trap bar, hinge at hips with slight knee bend lowering along thighs until deep hamstring stretch, then extend hips.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Glutes (new)
        Exercise(
            id: deterministicUUID(for: "Barbell Glute Bridge"),
            name: "Barbell Glute Bridge",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Lie on the floor, roll a padded barbell over your hips, drive through heels to full extension, squeeze hard at the top.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Hip Thrust"),
            name: "Smith Machine Hip Thrust",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings, .core],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Upper back against a bench, Smith machine bar across hips — drive hips upward to full extension, then lower under control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Glute Kickback"),
            name: "Cable Glute Kickback",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings, .core],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Ankle cuff on a low cable, face the machine, drive the attached leg straight back squeezing the glute to full hip extension.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Machine Glute Kickback"),
            name: "Machine Glute Kickback",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "On a glute kickback machine, drive the pad back by extending the hip, pause, and return slowly.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Reverse Hyperextension"),
            name: "Reverse Hyperextension",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings, .lowerBack],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Face-down with hips at the machine edge, raise legs by extending hips until body is straight, then lower under control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "45-Degree Back Extension"),
            name: "45-Degree Back Extension",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings, .lowerBack],
            category: .machine,
            exerciseType: .bodyweightReps,
            instructions: "On a 45° hyperextension bench, lower torso toward the floor, then squeeze glutes to drive back to a straight body position.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Sumo Squat"),
            name: "Kettlebell Sumo Squat",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.quadriceps, .adductors],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Hold a kettlebell at chest height with a wide sumo stance, toes out 45°, squat to parallel, then stand.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Single-Leg Glute Bridge"),
            name: "Single-Leg Glute Bridge",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings, .core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "One foot planted, other leg raised — drive through the planted heel to lift hips, squeeze the glute, then lower.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Frog Pump"),
            name: "Frog Pump",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.adductors, .core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "On your back, soles of feet together, knees flared — squeeze glutes to raise hips, then lower with control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Donkey Kick"),
            name: "Donkey Kick",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.hamstrings, .core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "From hands and knees, drive one foot toward the ceiling with knee bent at 90°, squeeze glute at the top, lower with control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Banded Fire Hydrant"),
            name: "Banded Fire Hydrant",
            primaryMuscleGroup: .glutes,
            secondaryMuscleGroups: [.abductors, .core],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Mini band above knees in a quadruped position, lift one knee out to the side to 45° while keeping it bent, then lower with control.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Calves (new)
        Exercise(
            id: deterministicUUID(for: "Machine Seated Calf Raise"),
            name: "Machine Seated Calf Raise",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Knees under the pad, balls of feet on the platform edge — press through forefoot, raise heels as high as possible, lower through full stretch. Targets the soleus.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Donkey Calf Raise"),
            name: "Donkey Calf Raise",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Hips hinged forward with pad on lower back, balls of feet on the edge — raise heels as high as possible, then lower with control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Leg Press Calf Raise"),
            name: "Leg Press Calf Raise",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Legs nearly extended on the leg press, only balls of feet on the platform edge — plantar flex fully, then lower slowly.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Smith Machine Standing Calf Raise"),
            name: "Smith Machine Standing Calf Raise",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [.core],
            category: .smithMachine,
            exerciseType: .weightedReps,
            instructions: "Bar on traps, stand on a raised block with balls of feet on the edge — raise heels through full range of motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Single-Leg Calf Raise"),
            name: "Dumbbell Single-Leg Calf Raise",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [.core],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Hold a dumbbell on the working side, stand on the ball of one foot on a raised surface — raise heel, squeeze, lower through full stretch.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Seated Calf Raise"),
            name: "Barbell Seated Calf Raise",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Seated with a padded barbell across lower thighs, balls of feet on a raised block — press through forefoot. Targets the soleus.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Tibialis Raise"),
            name: "Tibialis Raise",
            primaryMuscleGroup: .calves,
            secondaryMuscleGroups: [],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Back against a wall, heels 12 inches from the base — raise toes and forefoot as high as possible by dorsiflexing ankles. Targets the tibialis anterior.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Hip Flexors (new)
        Exercise(
            id: deterministicUUID(for: "Hanging Knee Raise"),
            name: "Hanging Knee Raise",
            primaryMuscleGroup: .hipFlexors,
            secondaryMuscleGroups: [.core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Hang from a bar, raise knees toward chest by flexing hips, pause, then lower with control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Captain's Chair Knee Raise"),
            name: "Captain's Chair Knee Raise",
            primaryMuscleGroup: .hipFlexors,
            secondaryMuscleGroups: [.core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Support yourself on a captain's chair, raise knees toward chest contracting abs, then lower with control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Hip Flexion"),
            name: "Cable Hip Flexion",
            primaryMuscleGroup: .hipFlexors,
            secondaryMuscleGroups: [.quadriceps],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Ankle cuff on a low cable, face away, raise the attached leg forward by flexing the hip, then lower.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Decline Sit-Up"),
            name: "Decline Sit-Up",
            primaryMuscleGroup: .hipFlexors,
            secondaryMuscleGroups: [.core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Feet secured on a decline bench, lower torso back, then sit up by flexing at the hips until upright.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Weighted Standing Knee Raise"),
            name: "Weighted Standing Knee Raise",
            primaryMuscleGroup: .hipFlexors,
            secondaryMuscleGroups: [.quadriceps, .core],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "With an ankle weight or dumbbell hooked over one foot, raise the knee until thigh is parallel, then lower.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Banded Psoas March"),
            name: "Banded Psoas March",
            primaryMuscleGroup: .hipFlexors,
            secondaryMuscleGroups: [.core],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Mini band around both feet, alternate driving each knee toward chest in a slow, controlled marching motion.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Adductors (new)
        Exercise(
            id: deterministicUUID(for: "Machine Hip Adduction"),
            name: "Machine Hip Adduction",
            primaryMuscleGroup: .adductors,
            secondaryMuscleGroups: [.glutes],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Legs apart, inner thighs against pads — squeeze legs together against resistance, hold briefly at full adduction.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Hip Adduction"),
            name: "Cable Hip Adduction",
            primaryMuscleGroup: .adductors,
            secondaryMuscleGroups: [.core],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Ankle cuff on the working-leg side, stand sideways, sweep attached leg across your body past the midline, then return.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Copenhagen Adductor Exercise"),
            name: "Copenhagen Adductor Exercise",
            primaryMuscleGroup: .adductors,
            secondaryMuscleGroups: [.core, .obliques],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Side-plank position with top foot on a bench — lift hips and drive bottom leg up to meet the bench using adductor strength.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Lateral Lunge"),
            name: "Dumbbell Lateral Lunge",
            primaryMuscleGroup: .adductors,
            secondaryMuscleGroups: [.quadriceps, .glutes],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Hold dumbbells at your sides, step wide to one side bending that knee while the trailing leg stays straight, then return to center.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Cossack Squat"),
            name: "Kettlebell Cossack Squat",
            primaryMuscleGroup: .adductors,
            secondaryMuscleGroups: [.quadriceps, .glutes],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Kettlebell at chest height in a wide stance, shift weight fully to one side and squat deep while the other leg straightens.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Side-Lying Adductor Raise"),
            name: "Side-Lying Adductor Raise",
            primaryMuscleGroup: .adductors,
            secondaryMuscleGroups: [.core],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "On your side, top leg crossed over in front, lift the bottom leg using inner thigh muscles, hold briefly, then lower.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Banded Adduction"),
            name: "Banded Adduction",
            primaryMuscleGroup: .adductors,
            secondaryMuscleGroups: [.core],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Band anchored at ankle height, pull the working leg across your body toward the midline against band tension.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Abductors (new)
        Exercise(
            id: deterministicUUID(for: "Machine Hip Abduction"),
            name: "Machine Hip Abduction",
            primaryMuscleGroup: .abductors,
            secondaryMuscleGroups: [.glutes],
            category: .machine,
            exerciseType: .weightedReps,
            instructions: "Legs together, outer thighs against pads — press legs apart against resistance, hold at full abduction.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Hip Abduction"),
            name: "Cable Hip Abduction",
            primaryMuscleGroup: .abductors,
            secondaryMuscleGroups: [.glutes],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Ankle cuff on the far side, stand sideways, lift the far leg out to the side against resistance, then return.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Banded Lateral Walk"),
            name: "Banded Lateral Walk",
            primaryMuscleGroup: .abductors,
            secondaryMuscleGroups: [.glutes, .quadriceps],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Mini band around ankles, quarter-squat position — walk sideways in controlled steps maintaining constant outward tension.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Banded Clamshell"),
            name: "Banded Clamshell",
            primaryMuscleGroup: .abductors,
            secondaryMuscleGroups: [.glutes],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "On your side with mini band above knees, knees bent at 45°, feet together — rotate top knee open against resistance, then close.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Banded Monster Walk"),
            name: "Banded Monster Walk",
            primaryMuscleGroup: .abductors,
            secondaryMuscleGroups: [.glutes, .quadriceps],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Band around ankles, quarter-squat — walk forward taking small diagonal steps outward to maintain constant outward tension.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Side-Lying Hip Abduction"),
            name: "Side-Lying Hip Abduction",
            primaryMuscleGroup: .abductors,
            secondaryMuscleGroups: [.glutes],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "On your side, legs straight and stacked — lift the top leg upward keeping toes forward, hold briefly, then lower.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Core (new)
        Exercise(
            id: deterministicUUID(for: "Hollow Body Hold"),
            name: "Hollow Body Hold",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors, .quadriceps],
            category: .bodyweight,
            exerciseType: .duration,
            instructions: "Lie face-up, lift shoulders and legs simultaneously with arms overhead forming a banana shape. Hold while pressing lower back into the floor.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dragon Flag"),
            name: "Dragon Flag",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors, .lats],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Grip behind your head on a bench, raise your entire body in a rigid line until only upper back contacts the bench, then lower under control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Body Saw"),
            name: "Body Saw",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.shoulders, .lats],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Forearm plank with feet on sliders — push body backward by extending through shoulders while maintaining rigid core, then pull back.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Stability Ball Stir-the-Pot"),
            name: "Stability Ball Stir-the-Pot",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.shoulders, .chest],
            category: .exerciseBall,
            exerciseType: .duration,
            instructions: "Forearms on a stability ball in plank position — move forearms in small circles while keeping hips level and core braced.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Pallof Press"),
            name: "Cable Pallof Press",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .shoulders],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Stand perpendicular to a cable at chest height, press the handle straight out resisting the rotational pull, hold, then return.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Band Pallof Press"),
            name: "Band Pallof Press",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .shoulders],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Band anchored at chest height, stand sideways, press straight out resisting rotation, hold at full extension, then return.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Copenhagen Plank"),
            name: "Copenhagen Plank",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.adductors, .obliques],
            category: .bodyweight,
            exerciseType: .duration,
            instructions: "Side-lying with top foot on a bench, bottom leg unsupported — lift hips and hold a straight line engaging obliques and adductors.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Side Plank"),
            name: "Side Plank",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .glutes],
            category: .bodyweight,
            exerciseType: .duration,
            instructions: "On your side propped on your forearm, feet stacked — lift hips forming a straight line from head to feet. Hold for time.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Suitcase Carry"),
            name: "Suitcase Carry",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .forearms, .traps],
            category: .dumbbell,
            exerciseType: .distance,
            instructions: "Hold a heavy dumbbell in one hand, walk for distance maintaining an upright torso resisting lateral flexion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Bicycle Crunch"),
            name: "Bicycle Crunch",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors, .obliques],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Face-up, hands behind head — bring opposite elbow to opposite knee while extending the other leg, alternating in a pedaling motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "V-Up"),
            name: "V-Up",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Arms overhead, simultaneously lift legs and torso to form a V reaching hands toward toes, then lower.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "GHD Sit-Up"),
            name: "GHD Sit-Up",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors, .quadriceps],
            category: .machine,
            exerciseType: .bodyweightReps,
            instructions: "Feet secured on a GHD, lean back to full extension then sit up through a large range of motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Weighted Decline Sit-Up"),
            name: "Weighted Decline Sit-Up",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "On a decline bench holding a dumbbell at your chest, perform a full sit-up with control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Toes-to-Bar"),
            name: "Toes-to-Bar",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors, .lats],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Hang from a bar and use core and hip flexors to raise feet all the way up to touch the bar, then lower with control.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "L-Sit"),
            name: "L-Sit",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors, .shoulders, .triceps],
            category: .bodyweight,
            exerciseType: .duration,
            instructions: "Support yourself on parallel bars with locked arms, raise legs to horizontal forming an L. Hold for time.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Woodchop High-to-Low"),
            name: "Cable Woodchop High-to-Low",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .shoulders],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Cable at highest position, stand sideways, pull handle diagonally across body from high to low in a controlled chopping motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Cable Woodchop Low-to-High"),
            name: "Cable Woodchop Low-to-High",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .shoulders],
            category: .cable,
            exerciseType: .weightedReps,
            instructions: "Cable at lowest position, stand sideways, drive handle diagonally upward across body in a lifting motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Landmine Rotation"),
            name: "Landmine Rotation",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .shoulders],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Hold the free end of a landmine barbell with both hands at arm's length and rotate the bar side to side keeping hips stable.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Hanging Windshield Wiper"),
            name: "Hanging Windshield Wiper",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .hipFlexors],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Hang from a bar, raise legs to horizontal, then rotate both legs side to side like windshield wipers.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Medicine Ball Rotational Slam"),
            name: "Medicine Ball Rotational Slam",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .shoulders],
            category: .medicineBall,
            exerciseType: .weightedReps,
            instructions: "Rotate and forcefully slam a medicine ball into the ground to one side, catch the rebound, repeat to the other side.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Back Extension"),
            name: "Back Extension",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.glutes, .hamstrings],
            category: .machine,
            exerciseType: .bodyweightReps,
            instructions: "Face-down on a 45° hyperextension bench, lower torso then extend back to a straight line squeezing lower back and glutes.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Bird Dog"),
            name: "Bird Dog",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.glutes, .shoulders],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "On all fours, extend opposite arm and leg simultaneously while keeping hips level and core braced, then alternate.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Superman"),
            name: "Superman",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.glutes],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "Lie face-down, simultaneously lift arms, chest, and legs off the ground, hold briefly, then lower.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Side Bend"),
            name: "Dumbbell Side Bend",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Stand with a dumbbell in one hand, laterally flex away from the weight, then return upright using obliques to control the motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Windmill"),
            name: "Kettlebell Windmill",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.obliques, .shoulders],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Press a kettlebell overhead and lock it out, hinge at the hip and lower your free hand toward the floor while keeping eyes on the weight.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Mountain Climber"),
            name: "Mountain Climber",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors, .shoulders],
            category: .bodyweight,
            exerciseType: .bodyweightReps,
            instructions: "High plank position, drive one knee toward your chest then rapidly switch legs in an alternating running motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Seated Band Hip Flexion"),
            name: "Seated Band Hip Flexion",
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [.hipFlexors, .quadriceps],
            category: .resistanceBand,
            exerciseType: .weightedReps,
            instructions: "Sit on a bench with a band around one foot anchored behind you, raise the knee toward chest against resistance, then return.",
            isCustom: false,
            isArchived: false
        ),

        // MARK: - Full Body (new)
        Exercise(
            id: deterministicUUID(for: "Power Clean"),
            name: "Power Clean",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.hamstrings, .glutes, .traps, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Pull a barbell explosively from the floor using triple extension and catch it in the front rack with a partial squat.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Hang Clean"),
            name: "Hang Clean",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.hamstrings, .glutes, .traps, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "From a hang position at hip height, explosively extend hips and shrug, catching the bar in a front rack squat.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Clean and Press"),
            name: "Barbell Clean and Press",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.shoulders, .back, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Clean a barbell from the floor to front rack, then press overhead to lockout.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Barbell Thruster"),
            name: "Barbell Thruster",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.quadriceps, .shoulders, .glutes],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Front squat then drive out of the bottom pressing the barbell overhead in one fluid motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Landmine Squat-to-Press"),
            name: "Landmine Squat-to-Press",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.quadriceps, .shoulders, .core],
            category: .barbell,
            exerciseType: .weightedReps,
            instructions: "Hold the end of a landmine at chest height, squat to depth, then drive up pressing the bar overhead along its arc.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Dumbbell Thruster"),
            name: "Dumbbell Thruster",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.quadriceps, .shoulders, .glutes],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Dumbbells at shoulders, squat deep, then explosively stand pressing dumbbells overhead in one motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Devil Press"),
            name: "Devil Press",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.shoulders, .hamstrings, .core],
            category: .dumbbell,
            exerciseType: .weightedReps,
            instructions: "Perform a burpee over dumbbells on the floor, then swing them between your legs and overhead in one powerful snatch motion.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Turkish Get-Up"),
            name: "Turkish Get-Up",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.core, .shoulders, .glutes],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Lying down with a kettlebell overhead, move through transitions (elbow → hand → kneel → stand) keeping the weight locked out, then reverse.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Clean and Press"),
            name: "Kettlebell Clean and Press",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.shoulders, .hamstrings, .core],
            category: .kettlebell,
            exerciseType: .weightedReps,
            instructions: "Swing-clean a kettlebell to the rack position, press overhead to lockout, lower to rack, drop to hang, repeat.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Kettlebell Farmer's Walk"),
            name: "Kettlebell Farmer's Walk",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.forearms, .traps, .core],
            category: .kettlebell,
            exerciseType: .distance,
            instructions: "Hold a heavy kettlebell in each hand at your sides, walk for distance with upright posture — the offset center of gravity adds stabilization demand.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Farmer's Walk"),
            name: "Farmer's Walk",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.forearms, .traps, .core],
            category: .dumbbell,
            exerciseType: .distance,
            instructions: "Heavy dumbbell in each hand at your sides, walk for distance with an upright posture, braced core, and packed shoulders.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Trap Bar Farmer's Walk"),
            name: "Trap Bar Farmer's Walk",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.forearms, .traps, .core],
            category: .trapBar,
            exerciseType: .distance,
            instructions: "Deadlift a loaded trap bar and walk for distance maintaining an upright torso and braced core.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Overhead Barbell Carry"),
            name: "Overhead Barbell Carry",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.shoulders, .core, .traps],
            category: .barbell,
            exerciseType: .distance,
            instructions: "Press a barbell to full lockout overhead and walk for distance with arms locked and core braced.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Sled Push"),
            name: "Sled Push",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.quadriceps, .glutes, .calves],
            category: .other,
            exerciseType: .distance,
            instructions: "Grip sled handles, lean forward with braced core, and drive the sled forward using powerful alternating leg pushes.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Sled Pull"),
            name: "Sled Pull",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.back, .biceps, .core],
            category: .other,
            exerciseType: .distance,
            instructions: "Face the sled and pull a rope attached to it hand-over-hand, engaging back, arms, and legs.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Yoke Walk"),
            name: "Yoke Walk",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.traps, .core, .back],
            category: .other,
            exerciseType: .distance,
            instructions: "Load a yoke bar across upper traps, brace hard, stand tall, and walk with short quick steps under maximal load.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Wall Ball"),
            name: "Wall Ball",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.quadriceps, .shoulders, .core],
            category: .medicineBall,
            exerciseType: .weightedReps,
            instructions: "Hold a medicine ball at chest height, squat to depth, explosively stand throwing the ball to a high wall target, catch and repeat.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Bear Crawl"),
            name: "Bear Crawl",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.core, .shoulders, .quadriceps],
            category: .bodyweight,
            exerciseType: .distance,
            instructions: "On all fours with knees hovering 1–2 inches off the ground, crawl forward moving opposite hand and foot simultaneously.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Tire Flip"),
            name: "Tire Flip",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.quadriceps, .glutes, .back, .shoulders],
            category: .other,
            exerciseType: .weightedReps,
            instructions: "Squat down under a large tire, drive hands underneath, explosively extend hips to lift and push it over.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Sandbag Clean and Carry"),
            name: "Sandbag Clean and Carry",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.back, .biceps, .core],
            category: .other,
            exerciseType: .weightedReps,
            instructions: "Bear-hug a heavy sandbag from the ground, clean it to your chest using a hip drive, then carry for distance.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Battle Ropes"),
            name: "Battle Ropes",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.shoulders, .core, .forearms],
            category: .other,
            exerciseType: .cardio,
            instructions: "Grip heavy rope ends, alternately whip each arm creating waves while in a half-squat stance for time or intervals.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Rowing Machine"),
            name: "Rowing Machine",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.back, .quadriceps, .core],
            category: .machine,
            exerciseType: .cardio,
            instructions: "Drive through legs first, lean back slightly pulling the handle to lower chest, then extend arms and bend knees to recover.",
            isCustom: false,
            isArchived: false
        ),
        Exercise(
            id: deterministicUUID(for: "Assault Bike"),
            name: "Assault Bike",
            primaryMuscleGroup: .fullBody,
            secondaryMuscleGroups: [.quadriceps, .shoulders, .core],
            category: .machine,
            exerciseType: .cardio,
            instructions: "Pedal an air-resistance bike while pushing and pulling arm handles — the harder you work, the greater the resistance.",
            isCustom: false,
            isArchived: false
        ),
    ]
}
