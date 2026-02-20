# ADR-016: Training Status Detection & 1RM Estimation

**Status:** Accepted
**Date:** 2026-02-20
**Context:** Progression Planning Module — Training Status Service

## Decision

`TrainingStatusDetector` service determines user's training level from workout history and estimates 1RM values with time-windowed detraining penalties.

## Classification Rules
- **Beginner**: < 3 months OR < 50 completed workouts
- **Intermediate**: 3-18 months OR 50-200 workouts, ≥ 2x/week recently
- **Advanced**: > 18 months AND > 200 workouts AND ≥ 3x/week recently

## 1RM Estimation
- **Recent window** (≤ 6 months): Direct estimate, no penalty
- **Extended window** (6-12 months): 10% detraining penalty applied
- **Beyond 12 months**: No usable data
- Epley formula for ≤5 reps: `weight × (1 + reps/30)`
- Brzycki formula for 6-15 reps: `weight × 36/(37 - reps)`
- Beyond 15 reps: unreliable, returns nil

## Files
- `Shared/Services/Progression/TrainingStatusDetector.swift`
- `Tests/UnitTests/Progression/Services/TrainingStatusDetectorTests.swift`

## Consequences
- Depends only on WorkoutRepository (existing protocol)
- Used during plan creation to auto-detect training level
- 1RM estimates used to pre-fill PlanExercise.estimated1RM values
