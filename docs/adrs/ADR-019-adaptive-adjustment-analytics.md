# ADR-019: Plan Analytics & Adaptive Adjustment

**Status:** Accepted
**Date:** 2026-02-20
**Context:** Progression Planning Module — CORRECT Layer

## Decision

Two services: `PlanAnalyticsService` tracks adherence and progress; `AdaptiveAdjustmentService` generates corrective proposals via InsightReport + AdjustmentArbiter.

## PlanAnalyticsService
- Session-linkage attribution (Review Fix #1): attributes workouts to planned sessions via templateId and date proximity
- Generates PlanProgress with exercise-level 1RM tracking, block adherence, volume history
- Integrates with existing PlateauDetectionService and MuscleBalanceService

## AdaptiveAdjustmentService
### InsightReport Signal Collection
- Detraining detection: 10-21 days → 5% reduction, 21-42 → 10%, 42+ → 15% + repeat week (Review Fix #9)
- Beginner regression: 2 consecutive misses → 5% TM reduction, 3+ → 10% + repeat (Review Fix #10)
- Multi-signal deload: triggers when ≥2 deload signals (Review Fix #12)
- Plateau integration: existing PlateauDetectionService signals
- Subjective signals: pain/fatigue from workout notes (future Apple Intelligence)

### AdjustmentArbiter
- Priority ranking of proposals
- Mutual exclusion (no contradictory adjustments)
- Max 3 proposals at a time (Review Fix #11)
- Each ProposedAdjustment carries: adjustment, priority, reasoning

## Files
- `Shared/Services/Progression/PlanAnalyticsService.swift`
- `Shared/Services/Progression/AdaptiveAdjustmentService.swift`
- `Tests/UnitTests/Progression/Services/PlanAnalyticsServiceTests.swift`
- `Tests/UnitTests/Progression/Services/AdaptiveAdjustmentServiceTests.swift`

## Consequences
- Multi-signal approach prevents premature deloads from single bad sessions
- Arbiter ensures user sees at most 3 actionable proposals
- Extensible for future subjective signal inputs
