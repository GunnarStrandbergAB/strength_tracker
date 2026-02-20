# ADR-018: Session Execution & APRE Load Adjustment

**Status:** Accepted
**Date:** 2026-02-20
**Context:** Progression Planning Module — Execution Layer

## Decision

`SessionExecutionService` bridges planned sessions with actual workout execution. Handles APRE load adjustments, 1RM EWMA smoothing, and post-workout plan linkage.

## APRE Protocol
- Percentage-based adjustments from actual workingWeight (Review Fix #3)
- Three protocols: 3RM (strength), 6RM (hypertrophy), 10RM (endurance)
- See PlannedExerciseSet.apreAdjustedWeight for full tables

## 1RM Smoothing (Review Fix #8)
- EWMA with α=0.3 for stability
- Outlier rejection at ±15% from running average
- Regression guard: only apply downward adjustments if >5% below current

## Session Completion Flow
1. Link completed workout to planned session
2. Capture workout notes for downstream AI signal extraction
3. Compute 1RM updates via EWMA
4. Generate APRE-based load adjustments
5. Return updated session + adjustments + updated exercises

## Files
- `Shared/Services/Progression/SessionExecutionService.swift`
- `Tests/UnitTests/Progression/Services/SessionExecutionServiceTests.swift`

## Consequences
- APRE tables are research-validated (Jovanovic & Flanagan)
- 1RM smoothing prevents single-session anomalies from destabilizing plans
- Workout notes captured for Apple Intelligence signal extraction (future)
