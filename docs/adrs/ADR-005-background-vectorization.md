# ADR-005: Background Vectorization

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Services

## Context

Vectorizing a workout involves extracting 18 features, computing muscle group volume ratios, comparing against 7-day and 30-day historical averages, and performing L2 normalization. This process takes approximately 50ms per workout, which is noticeable if performed synchronously on the main thread during workout completion.

The user's flow when completing a workout is: tap "Finish Workout" -> see a post-workout summary sheet with quality score, highlights, and an option to view similar workouts. Vectorization must complete before "View Similar Workouts" works, but it should not delay the appearance of the completion sheet.

Additionally, when a user upgrades to a version with analytics for the first time, all existing workouts (potentially hundreds) need to be vectorized in a one-time migration batch.

## Decision

Vectorize workouts in background tasks using Swift concurrency:

1. **Post-workout completion** (primary path): After `WorkoutRepository.complete(workoutId)` succeeds, trigger `WorkoutAnalyticsService.ensureVectorized(workout)` in a background `Task`. The post-workout sheet appears immediately; vectorization runs concurrently.

2. **On-demand fallback**: If a user opens the Similar Workouts view before vectorization completes, `ensureVectorized()` is called and awaited at that point. This ensures the feature always works, even if the background task was delayed.

3. **Batch migration**: `WorkoutAnalyticsService.vectorizeAllWorkouts()` runs via `Task.detached(priority: .background)` on first analytics access or app upgrade. A progress indicator is shown to the user during this one-time operation.

## Rationale

- 50ms vectorization time is perceptible if synchronous (blocks the thread that presents the completion sheet)
- Background task allows the UI to remain responsive while vectorization happens concurrently
- On-demand fallback ensures the feature works even if the background task fails or is interrupted
- `Task.detached(priority: .background)` for batch migration prevents the one-time operation from interfering with UI responsiveness
- Swift structured concurrency provides automatic cancellation and error propagation

## Alternatives Considered

- **Synchronous vectorization**: Rejected because 50ms blocks the main thread noticeably, and batch vectorization of 100+ workouts would freeze the UI for 5+ seconds.
- **BGProcessingTask (background app refresh)**: Rejected as overly complex for this use case. Vectorization is fast enough to run during app use; it does not need to run while the app is suspended.
- **Pre-computed at workout save time** (not at completion): Rejected because incomplete workouts would generate misleading vectors. Vectorization should happen only after the workout is finalized.

## Consequences

### Positive
- UI remains responsive during and after workout completion
- Post-workout sheet appears immediately without waiting for vectorization
- Batch migration of existing workouts happens transparently in the background
- On-demand fallback ensures "View Similar" always works regardless of background task state

### Negative / Trade-offs
- Brief window (up to ~50ms) after workout completion where the vector is not yet available. If the user immediately taps "View Similar Workouts," they may see a loading indicator while `ensureVectorized()` completes on demand.
- Batch migration shows a progress sheet that briefly interrupts the first-launch experience after upgrade

### Neutral
- Performance targets: single vectorization under 50ms, batch of 100 workouts under 5 seconds
- The `UserDefaults` flag `analytics_migration_complete` prevents re-running the batch migration

## Implementation Notes

- **Post-workout hook**: In `WorkoutViewModel.completeWorkout()`, after saving, spawn a `Task { await analyticsService.ensureVectorized(workout) }`
- **On-demand**: `WorkoutAnalyticsService.findSimilarWorkouts(to:)` calls `ensureVectorized()` before fetching vectors
- **Batch migration**: Triggered in `StrengthTrackeriOS.swift` via `.task { await performAnalyticsMigration() }`, guarded by `UserDefaults.standard.bool(forKey: "analytics_migration_complete")`
- **Batch processing**: Iterates over workouts sequentially (not parallel) to avoid overwhelming the ModelContext with concurrent writes

## References

- [ADR-001: Pure On-Device Vector Analytics](ADR-001-pure-on-device-vector-analytics.md)
- [ADR-004: SwiftData for Vector Storage](ADR-004-swiftdata-vector-storage.md)
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 4.1, 7.3, 8.3, 10.2
