#!/usr/bin/env python3
"""Generate docs/exercise-library.md from the app's exercise seed data.

The seed file (StrengthTracker/Shared/Services/ExerciseSeedData.swift) is the
single source of truth for the built-in exercise library. This script parses it
and regenerates the canonical documentation so the doc can never drift from
reality. Run from the repo root after any seed-data change:

    python3 scripts/generate_exercise_doc.py

It also prints the summary counts, which the README's "Exercise Library"
section must match.
"""

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SEED_FILE = REPO_ROOT / "StrengthTracker/Shared/Services/ExerciseSeedData.swift"
OUT_FILE = REPO_ROOT / "docs/exercise-library.md"

ENTRY_RE = re.compile(
    r"Exercise\(\s*"
    r"id:\s*deterministicUUID\(for:\s*\"(?P<name>[^\"]+)\"\),\s*"
    r"name:\s*\"(?P<name2>[^\"]+)\",\s*"
    r"primaryMuscleGroup:\s*\.(?P<primary>\w+),\s*"
    r"secondaryMuscleGroups:\s*\[(?P<secondary>[^\]]*)\],\s*"
    r"category:\s*\.(?P<category>\w+),\s*"
    r"exerciseType:\s*\.(?P<type>\w+),",
    re.DOTALL,
)

CATEGORY_NAMES = {
    "barbell": "Barbell", "dumbbell": "Dumbbell", "machine": "Machine",
    "cable": "Cable", "bodyweight": "Bodyweight", "smithMachine": "Smith Machine",
    "kettlebell": "Kettlebell", "resistanceBand": "Resistance Band",
    "plate": "Plate", "medicineBall": "Medicine Ball",
    "exerciseBall": "Exercise Ball", "trx": "TRX", "landmine": "Landmine",
    "trapBar": "Trap Bar", "ezBar": "EZ Bar", "other": "Other",
}

TYPE_NAMES = {
    "weightedReps": "Weighted Reps", "bodyweightReps": "Bodyweight Reps",
    "duration": "Duration", "distance": "Distance", "cardio": "Cardio",
    "weightedCardio": "Weighted Cardio",
}

# Display order + names for muscle groups (matches the MuscleGroup enum order)
MUSCLE_NAMES = {
    "chest": "Chest", "back": "Back", "shoulders": "Shoulders",
    "biceps": "Biceps", "triceps": "Triceps", "forearms": "Forearms",
    "core": "Core", "quadriceps": "Quadriceps", "hamstrings": "Hamstrings",
    "glutes": "Glutes", "calves": "Calves", "adductors": "Adductors",
    "abductors": "Abductors", "traps": "Traps", "lats": "Lats",
    "hipFlexors": "Hip Flexors", "lowerBack": "Lower Back",
    "obliques": "Obliques", "fullBody": "Full Body", "cardio": "Cardio",
    "other": "Other",
}


def muscle_name(raw: str) -> str:
    return MUSCLE_NAMES.get(raw, raw.capitalize())


def main() -> None:
    source = SEED_FILE.read_text()
    total_declared = source.count("Exercise(")
    entries = []
    for m in ENTRY_RE.finditer(source):
        if m.group("name") != m.group("name2"):
            sys.exit(f"ERROR: id/name mismatch for {m.group('name')!r}")
        secondary = [s.strip().lstrip(".") for s in m.group("secondary").split(",") if s.strip()]
        entries.append({
            "name": m.group("name"),
            "primary": m.group("primary"),
            "secondary": secondary,
            "category": m.group("category"),
            "type": m.group("type"),
        })

    if len(entries) != total_declared:
        sys.exit(
            f"ERROR: parsed {len(entries)} entries but the file contains "
            f"{total_declared} 'Exercise(' occurrences — the seed format changed; "
            f"update this script before trusting its output."
        )

    by_category = Counter(e["category"] for e in entries)
    by_type = Counter(e["type"] for e in entries)
    by_primary = Counter(e["primary"] for e in entries)
    grouped = defaultdict(list)
    for e in entries:
        grouped[e["primary"]].append(e)

    lines = []
    lines.append("# Exercise Library")
    lines.append("")
    lines.append(f"**{len(entries)} built-in exercises.**")
    lines.append("")
    lines.append("> Generated from `StrengthTracker/Shared/Services/ExerciseSeedData.swift` —")
    lines.append("> the single source of truth. **Do not hand-edit this file.** Regenerate with:")
    lines.append("> `python3 scripts/generate_exercise_doc.py`")
    lines.append("")

    lines.append("## By Equipment")
    lines.append("")
    lines.append("| Category | Exercises |")
    lines.append("|---|---|")
    for cat, n in by_category.most_common():
        lines.append(f"| {CATEGORY_NAMES.get(cat, cat)} | {n} |")
    lines.append("")

    lines.append("## By Exercise Type")
    lines.append("")
    lines.append("| Type | Exercises |")
    lines.append("|---|---|")
    for t, n in by_type.most_common():
        lines.append(f"| {TYPE_NAMES.get(t, t)} | {n} |")
    lines.append("")

    lines.append("## By Primary Muscle Group")
    lines.append("")
    lines.append("| Muscle Group | Exercises |")
    lines.append("|---|---|")
    for mg in MUSCLE_NAMES:
        if by_primary.get(mg):
            lines.append(f"| {muscle_name(mg)} | {by_primary[mg]} |")
    lines.append("")

    lines.append("## Full Listing")
    lines.append("")
    for mg in MUSCLE_NAMES:
        group = grouped.get(mg)
        if not group:
            continue
        lines.append(f"### {muscle_name(mg)} ({len(group)})")
        lines.append("")
        lines.append("| Exercise | Category | Type | Secondary Muscles |")
        lines.append("|---|---|---|---|")
        for e in sorted(group, key=lambda x: x["name"].lower()):
            sec = ", ".join(muscle_name(s) for s in e["secondary"]) or "—"
            lines.append(
                f"| {e['name']} | {CATEGORY_NAMES.get(e['category'], e['category'])} "
                f"| {TYPE_NAMES.get(e['type'], e['type'])} | {sec} |"
            )
        lines.append("")

    OUT_FILE.write_text("\n".join(lines) + "\n")

    print(f"Wrote {OUT_FILE.relative_to(REPO_ROOT)} with {len(entries)} exercises")
    print("\nBy equipment:")
    for cat, n in by_category.most_common():
        print(f"  {CATEGORY_NAMES.get(cat, cat)}: {n}")
    print("\nBy type:")
    for t, n in by_type.most_common():
        print(f"  {TYPE_NAMES.get(t, t)}: {n}")
    print("\nBy primary muscle group:")
    for mg in MUSCLE_NAMES:
        if by_primary.get(mg):
            print(f"  {muscle_name(mg)}: {by_primary[mg]}")


if __name__ == "__main__":
    main()
