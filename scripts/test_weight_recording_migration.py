#!/usr/bin/env python3
"""Exercise a real pre-dumbbell-fix SQLite store upgrade, outside the iOS test host.

Uses the committed baseline entity sources and today's entity sources, with the
same Swift module name in separate executables. Requires macOS/Xcode and the
baseline commit in local Git history. Creates only temporary files; never
regenerates or edits the Xcode project or opens the user's application database.
Run: python3 scripts/test_weight_recording_migration.py
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "261d507009e38e66b0db5bf2c9ec4747009c174f"
ENTITIES = Path("StrengthTracker/Shared/Persistence/SwiftData/Entities")
CHECK = r'''
import Foundation
import SwiftData
@main struct MigrationCheck {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let schema = Schema([MODEL_TYPES])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        let id = UUID(uuidString: "ABCD0000-0000-0000-0000-000000000001")!
        #if LEGACY
        let exercise = ExerciseEntity(id: id, name: "Dumbbell Bench Press", primaryMuscleGroup: "chest", secondaryMuscleGroups: ["triceps"], category: "dumbbell", exerciseType: "weightedReps", instructions: nil, isCustom: false, isArchived: false)
        let row = WorkoutExerciseEntity(id: UUID(), exerciseId: id, exerciseName: exercise.name, primaryMuscleGroup: "chest", secondaryMuscleGroups: ["triceps"], category: "dumbbell", exerciseType: "weightedReps", instructions: nil, isCustom: false, isArchived: false, order: 1)
        row.sets = [ExerciseSetEntity(id: UUID(), order: 1, setType: "normal", weight: 20.25, reps: 11, rpe: 8, isCompleted: true, isPersonalRecord: false, completedAt: Date(timeIntervalSince1970: 1_700_000_000))]
        let target = TemplateExerciseEntity(id: UUID(), exerciseId: id, exerciseName: exercise.name, primaryMuscleGroup: "chest", secondaryMuscleGroups: [], category: "dumbbell", exerciseType: "weightedReps", instructions: nil, isCustom: false, isArchived: false, order: 1, targetSets: 3, targetReps: 11, targetWeight: 20.25)
        let record = PersonalRecordEntity(id: UUID(), exerciseId: id, recordType: "maxWeight", value: 20.25, setId: nil, achievedAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(exercise); context.insert(row); context.insert(target); context.insert(record)
        try context.save()
        print("Legacy SQLite fixture saved")
        #else
        let exercise = try context.fetch(FetchDescriptor<ExerciseEntity>()).first!
        let row = try context.fetch(FetchDescriptor<WorkoutExerciseEntity>()).first!
        let target = try context.fetch(FetchDescriptor<TemplateExerciseEntity>()).first!
        let record = try context.fetch(FetchDescriptor<PersonalRecordEntity>()).first!
        precondition(exercise.id == id && exercise.name == "Dumbbell Bench Press")
        precondition(row.exerciseId == id && row.sets.count == 1)
        precondition(row.sets[0].weight == 20.25 && row.sets[0].reps == 11 && row.sets[0].rpe == 8)
        precondition(row.sets[0].completedAt == Date(timeIntervalSince1970: 1_700_000_000))
        precondition(target.targetWeight == 20.25 && target.targetSets == 3)
        precondition(record.value == 20.25 && record.setId == nil)
        if CommandLine.arguments.count == 2 {
            precondition(exercise.weightRecordingJSON == nil && row.weightRecordingJSON == nil && target.weightRecordingJSON == nil && record.weightRecordingKey == nil)
            exercise.weightRecordingJSON = "confirmed-library"
            row.weightRecordingJSON = "confirmed-history"
            target.weightRecordingJSON = "confirmed-template"
            record.weightRecordingKey = "pair/perDumbbell/perMovement"
            try context.save()
            print("Migration passed: legacy source values retained; new fields are nullable")
        } else {
            precondition(exercise.weightRecordingJSON == "confirmed-library")
            precondition(row.weightRecordingJSON == "confirmed-history")
            precondition(target.weightRecordingJSON == "confirmed-template")
            precondition(record.weightRecordingKey == "pair/perDumbbell/perMovement")
            print("Reopen passed: all four new metadata fields persisted independently")
        }
        #endif
    }
}
'''


def run(args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)


with tempfile.TemporaryDirectory(prefix="strength-recording-migration-") as temp:
    temp = Path(temp)
    sources = sorted((ROOT / ENTITIES).glob("*.swift"))
    model_types = re.findall(r"public final class (\w+)", "\n".join(p.read_text() for p in sources))
    main = temp / "Check.swift"
    main.write_text(CHECK.replace("MODEL_TYPES", ", ".join(n + ".self" for n in model_types)))
    old = temp / "old"
    old.mkdir()
    for source in sources:
        data = subprocess.check_output(["git", "show", f"{BASELINE}:{ENTITIES / source.name}"], cwd=ROOT)
        (old / source.name).write_bytes(data)
    for name, paths, flags in [("legacy", sorted(old.glob("*.swift")), ["-DLEGACY"]), ("current", sources, [])]:
        run(["xcrun", "swiftc", "-parse-as-library", "-module-name", "StrengthTrackerMigrationCheck",
             "-module-cache-path", temp / "cache", *flags, *paths, main, "-o", temp / name])
    store = temp / "fixture.store"
    run([temp / "legacy", store])
    run([temp / "current", store])
    run([temp / "current", store, "reopen"])
