# ADR-017: Program Design Engine (Periodization)

**Status:** Accepted
**Date:** 2026-02-20
**Context:** Progression Planning Module — Program Design Service

## Decision

`ProgramDesignService` generates periodized training blocks from a `ProgressionPlan`. Four models supported: Linear, DUP, WUP, Block. Stateless service, pure function from plan → blocks.

## Periodization Models
1. **Linear**: Volume ↓, intensity ↑ across mesocycle. Status-dependent intensityStep with escalation clamp.
2. **DUP**: Hypertrophy/Strength/Power rotate within week. %-based overload per week.
3. **WUP**: Weekly rep-scheme rotation. %-based overload.
4. **Block**: Accumulation (4wk) → Transmutation (3wk) → Realization (2wk) → Deload (1wk).

## Key Rules
- Deload weeks inserted every 4th week for beginners/intermediates
- Fixed day-spread templates per frequency (Review Fix #4)
- Intensity clamped to ceiling per program type (Review Fix #6)
- %-based overload, not absolute weight increments (Review Fix #5)
- Block periodization uses fixed intra-phase templates (Review Fix #7)

## Files
- `Shared/Services/Progression/ProgramDesignService.swift`
- `Tests/UnitTests/Progression/Services/ProgramDesignServiceTests.swift`

## Consequences
- Pure function: no side effects, no repository access needed
- Generates complete block/week/session structure from plan configuration
- Each session includes PlannedExerciseSet with target weight, reps, RPE
