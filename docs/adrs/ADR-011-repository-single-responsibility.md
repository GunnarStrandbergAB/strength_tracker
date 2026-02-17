# ADR-011: AnalyticsRepository for Vector CRUD Only

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Domain Modeling

## Context

The analytics system needs to persist and retrieve `WorkoutVectorEntity` records. It also needs to query `WorkoutEntity` records (fetch workouts by IDs, by date range, etc.) for analysis.

The existing codebase follows a strict one-repository-per-entity-type pattern:
- `WorkoutRepository`: CRUD for `WorkoutEntity`
- `ExerciseRepository`: CRUD for `ExerciseEntity`
- `PersonalRecordRepository`: CRUD for `PersonalRecordEntity`

The question is whether `AnalyticsRepository` should also handle workout queries (combining vector and workout access in one repository) or whether it should be limited to vector operations only, with workout queries remaining on `WorkoutRepository`.

## Decision

`AnalyticsRepository` handles `WorkoutVectorEntity` CRUD only:
- `storeVector(_:)`
- `fetchVector(for workoutId:)`
- `fetchAllVectors()`
- `fetchVectorsByDateRange(_:_:)`
- `deleteVector(for workoutId:)`

Workout queries (`fetchByIds`, `fetchAll`, `fetchByDateRange`, etc.) stay on `WorkoutRepository`. The `WorkoutAnalyticsService` orchestrator holds references to both repositories and coordinates between them.

## Rationale

- **DDD single-responsibility**: One repository per aggregate/entity type. `AnalyticsRepository` manages `WorkoutVectorEntity`; `WorkoutRepository` manages `WorkoutEntity`. Repositories should not be mixed.
- **Consistency with existing codebase**: The existing services (`WorkoutService`, etc.) already demonstrate the pattern of holding references to multiple repositories and coordinating between them. `WorkoutAnalyticsService` follows the same pattern.
- **Testability**: Mock `AnalyticsRepository` and `WorkoutRepository` independently. A combined repository would require mocking both vector and workout behavior in every test.
- **Separation of concerns**: Vector storage has different access patterns (bulk fetch all vectors, store single vector) than workout storage (fetch by ID, fetch by date range with sorting). Keeping them separate allows each to be optimized independently.
- **Avoids circular dependencies**: If `AnalyticsRepository` depended on `WorkoutRepository` (or vice versa), it would create coupling between two aggregate boundaries.

## Alternatives Considered

- **Combined AnalyticsRepository** (handles both vectors and workout queries): Rejected because it violates the one-repository-per-entity-type pattern, makes the repository harder to mock in tests, and creates a "god repository" that mixes two distinct concerns.
- **Extend WorkoutRepository** with vector methods: Rejected because it bloats the existing repository protocol and implementation. Vector operations are conceptually distinct from workout CRUD.
- **No AnalyticsRepository** (inline SwiftData queries in the service): Rejected because it bypasses the repository abstraction layer, making services untestable without a real SwiftData stack and violating the DDD layering.

## Consequences

### Positive
- Consistent with existing one-repository-per-entity-type pattern
- Each repository is small, focused, and easy to mock
- `WorkoutAnalyticsService` clearly shows its dependencies (both repositories)
- No circular dependencies between repositories
- Can optimize vector fetch and workout fetch independently (e.g., different caching strategies)

### Negative / Trade-offs
- `WorkoutAnalyticsService` must coordinate between two repositories for operations that span both (e.g., finding similar workouts requires fetching vectors AND then fetching the corresponding workouts). This is a minor complexity increase.
- Two repository protocol files and two implementation files instead of one combined file

### Neutral
- The service orchestrator pattern (`WorkoutAnalyticsService` holding both repositories) is identical to how existing services work in the codebase
- Both repositories share the same `ModelContext` from `AppContainer`, so they participate in the same transaction scope

## Implementation Notes

- **Protocol**: `Shared/Repositories/Protocols/AnalyticsRepository.swift` -- 5 methods for vector CRUD
- **Implementation**: `Shared/Persistence/SwiftData/Repositories/SwiftDataAnalyticsRepository.swift` -- uses `FetchDescriptor<WorkoutVectorEntity>` with predicates
- **Orchestrator**: `WorkoutAnalyticsService` holds `analyticsRepository: any AnalyticsRepository` and `workoutRepository: any WorkoutRepository`. Example coordination in `findSimilarWorkouts()`:
  1. Fetch all vectors from `analyticsRepository`
  2. Run similarity search (in-memory)
  3. Fetch matching workouts from `workoutRepository` by IDs
  4. Combine into `[SimilarWorkout]` domain models
- **AppContainer wiring**: `analyticsRepository = SwiftDataAnalyticsRepository(modelContext: modelContext)` -- separate from `workoutRepository`

## References

- [ADR-004: SwiftData for Vector Storage](ADR-004-swiftdata-vector-storage.md)
- [ADR-009: WorkoutInsights Aggregate Root](ADR-009-workout-insights-aggregate-root.md)
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 5.1 (DDD Note), 5.2
- Existing pattern: `Shared/Repositories/Protocols/WorkoutRepository.swift`, `Shared/Repositories/Protocols/ExerciseRepository.swift`
