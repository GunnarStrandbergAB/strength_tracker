# ADR-014: Progression Domain Models & Enums

**Status:** Accepted
**Date:** 2026-02-20
**Context:** Progression Planning Module — Domain Layer

## Decision

All progression enums and core domain models live in `Shared/Models/Domain/Progression/`. Models are pure Swift value types (`struct`/`enum`) conforming to `Identifiable`, `Codable`, `Equatable`, `Sendable`. No SwiftData or SwiftUI dependencies.

## Files
- `ProgressionEnums.swift` — TrainingStatus, ProgramType, TrainingGoal, BlockPhase, DUPSessionType, PlanStatus, AdjustmentType, DeloadTrigger, AdjustmentTrigger
- `ProgressionPlan.swift` — Root aggregate with computed properties (progress, projections)
- `PlanExercise.swift` — Exercise with 1RM tracking, target weight calculation
- `TrainingBlock.swift` — Mesocycle block (3-6 weeks)
- `TrainingWeek.swift` — Microcycle (session-count-driven, not calendar-pinned)
- `PlannedSession.swift` — Single workout session with completion tracking
- `PlannedExerciseSet.swift` — Exercise prescription with APRE load adjustment tables
- `PlanAdjustment.swift` — Modification record with trigger tracking
- `PlanProgress.swift` — ExerciseProgress, BlockProgress, WeeklyVolume
- `ProgressionHelpers.swift` — `Double.rounded(toNearest:)` extension

## Consequences
- Pure domain layer testable on Linux without SwiftData/SwiftUI
- APRE tables embedded in PlannedExerciseSet for co-location with prescription data
- Week progression is session-count-driven (Review Fix #4)
