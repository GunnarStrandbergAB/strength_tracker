# ADR-009: WorkoutInsights as Read-Side Aggregate Root

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Domain Modeling

## Context

The analytics dashboard displays multiple types of computed insights simultaneously: plateau analyses, muscle balance, exercise recommendations, recovery patterns, and optimal volume ranges. Each insight type is produced by a different service (`PlateauDetectionService`, `MuscleBalanceService`, `ExerciseRecommendationService`).

Without an aggregate, the ViewModel would hold 5-6 independent arrays/optionals (`plateaus: [PlateauAnalysis]`, `muscleBalance: MuscleBalance?`, `recommendations: [ExerciseRecommendation]`, etc.). This creates several problems:

- No consistency guarantee: loading plateaus and muscle balance in separate calls means they may reflect different workout data snapshots
- Complex loading state management: each array needs its own `isLoading` flag
- No clear boundary for what constitutes a "complete" analytics load

In DDD terms, these insight models are read projections -- they are computed from workout data, not independently persisted entities. They need a consistency boundary to ensure all projections in a single dashboard load come from the same data snapshot.

## Decision

Introduce `WorkoutInsights` as a read-side aggregate root that groups all computed analytics results for a single dashboard load. The struct contains:

```swift
public struct WorkoutInsights: Sendable {
    public let generatedAt: Date
    public let workoutCount: Int
    public let plateaus: [PlateauAnalysis]
    public let muscleBalance: MuscleBalance?
    public let recommendations: [ExerciseRecommendation]
    public let recoveryPatterns: [RecoveryPattern]
    public let optimalVolumes: [OptimalVolumeRange]
}
```

The ViewModel holds a single `insights: WorkoutInsights` property instead of multiple independent arrays. `WorkoutAnalyticsService.generateInsights()` produces the entire aggregate in one call, using structured concurrency to run sub-analyses concurrently from the same workout data snapshot.

`SimilarWorkout` and `WorkoutQualityScore` are scoped to a specific workout (not the dashboard), so they live outside this aggregate and are loaded on demand.

## Rationale

- **Consistency boundary**: All insights in a single `WorkoutInsights` are computed from the same workout data snapshot, preventing stale-data inconsistencies (e.g., plateaus from today's data mixed with muscle balance from yesterday's data)
- **Simplified ViewModel state**: One `insights` property with one `isInsightsLoading` flag replaces 5-6 independent arrays with individual loading states
- **Atomic refresh**: Pull-to-refresh regenerates the entire aggregate, ensuring all insights update together
- **DDD alignment**: Read-side aggregates are an established pattern for grouping related projections with a consistency boundary
- **Static `.empty` factory**: Provides a clean initial state (`WorkoutInsights.empty`) with empty arrays and nil optionals, avoiding force-unwraps

## Alternatives Considered

- **Independent arrays in ViewModel**: Rejected because it creates 5-6 loading states, no consistency guarantee across insight types, and bloated ViewModel code for managing each array independently.
- **Single service method returning a tuple**: Rejected because tuples are not Sendable in Swift 6, cannot have computed properties or factory methods, and are harder to evolve than a named struct.
- **Nested ViewModel per insight type**: Rejected because it fragments the analytics state and makes it harder to reason about what is loaded vs. pending. The aggregate pattern keeps all analytics state in one place.
- **Persist the aggregate in SwiftData**: Rejected because these are read projections that should be recomputed from source data, not persisted independently. Persisting them would create cache invalidation complexity.

## Consequences

### Positive
- Single loading state (`isInsightsLoading`) instead of 5-6 independent loading flags
- All insights reflect the same data snapshot (consistency guarantee)
- Clean initial state via `WorkoutInsights.empty`
- ViewModel is simpler and easier to test (assert on one `insights` property)
- Easy to extend: adding a new insight type means adding one property to `WorkoutInsights`

### Negative / Trade-offs
- All insights are recomputed together, even if only one changed. This is acceptable because the total computation time is under 500ms and the alternative (incremental updates) adds significant complexity.
- Per-workout insights (`SimilarWorkout`, `WorkoutQualityScore`) live outside the aggregate, which means the ViewModel still has some independent state for those features.

### Neutral
- `WorkoutInsights` is a value type (`struct`), not a reference type. This ensures immutability and thread safety with `Sendable` conformance.
- The `workoutCount` property enables the UI to display how many workouts contributed to the analysis

## Implementation Notes

- **WorkoutInsights** (`Shared/Models/Domain/Analytics/WorkoutInsights.swift`): `struct` with `Sendable` conformance, static `.empty` factory
- **WorkoutAnalyticsService.generateInsights()** (`Shared/Services/Analytics/WorkoutAnalyticsService.swift`): Fetches all workouts once, runs plateau and muscle balance analysis concurrently via `async let`, returns a single `WorkoutInsights` struct
- **WorkoutAnalyticsViewModel** (`Shared/ViewModels/WorkoutAnalyticsViewModel.swift`): `insights: WorkoutInsights = .empty`, `isInsightsLoading: Bool`, loaded via `loadDashboardInsights()`
- **Per-workout state** (outside aggregate): `similarWorkouts: [SimilarWorkout]` and `qualityScore: WorkoutQualityScore?` are separate properties loaded on demand

## References

- [ADR-011: Repository Single Responsibility](ADR-011-repository-single-responsibility.md)
- [ADR-013: Computed Domain Recommendations](ADR-013-computed-domain-recommendations.md)
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 2.2, 4.3, 6.1
