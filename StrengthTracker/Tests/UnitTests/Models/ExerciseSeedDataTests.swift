import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("ExerciseSeedData")
struct ExerciseSeedDataTests {

    @Test("Has expected total exercise count")
    func totalCount() {
        #expect(ExerciseSeedData.allExercises.count == 344)
    }

    @Test("No duplicate names")
    func uniqueNames() {
        let names = ExerciseSeedData.allExercises.map(\.name)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count, "Found \(names.count - uniqueNames.count) duplicate name(s)")
    }

    @Test("No duplicate UUIDs")
    func uniqueIds() {
        let ids = ExerciseSeedData.allExercises.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Found \(ids.count - uniqueIds.count) duplicate UUID(s)")
    }

    @Test("Every exercise has non-empty name")
    func nonEmptyNames() {
        for exercise in ExerciseSeedData.allExercises {
            #expect(!exercise.name.isEmpty, "Exercise has empty name")
        }
    }

    @Test("Every bodyweight-reps exercise has a researched bodyweight factor in 0.2...1.5")
    func bodyweightFactorsPresent() {
        for exercise in ExerciseSeedData.allExercises where exercise.exerciseType == .bodyweightReps {
            let factor = exercise.bodyweightFactor
            #expect(factor != nil, "\(exercise.name) is bodyweightReps but has no bodyweightFactor")
            if let factor {
                #expect((0.2...1.5).contains(factor), "\(exercise.name) factor \(factor) outside 0.2...1.5")
            }
        }
    }

    @Test("Non-bodyweight exercises carry no bodyweight factor")
    func noFactorOnNonBodyweight() {
        for exercise in ExerciseSeedData.allExercises where exercise.exerciseType != .bodyweightReps {
            #expect(exercise.bodyweightFactor == nil,
                    "\(exercise.name) is \(exercise.exerciseType) but has bodyweightFactor")
        }
    }

    @Test("Every exercise has instructions")
    func hasInstructions() {
        for exercise in ExerciseSeedData.allExercises {
            let instructions = exercise.instructions ?? ""
            #expect(!instructions.isEmpty, "\(exercise.name) has no instructions")
        }
    }
}
