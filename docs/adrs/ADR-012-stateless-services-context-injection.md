# ADR-012: Stateless Services with Context Injection

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Services

## Context

The analytics services (`WorkoutVectorizer`, `PlateauDetectionService`, `MuscleBalanceService`, `ExerciseRecommendationService`) need access to historical workout data to produce their results. For example:

- `WorkoutVectorizer.vectorize()` needs 7-day and 30-day historical averages to compute relative volume features (dimensions 14 and 15)
- `PlateauDetectionService.analyzePlateaus()` needs recent workouts to detect stagnation patterns
- `MuscleBalanceService.analyze()` needs workouts within a time window to compute volume distributions

The question is whether these services should fetch historical data themselves (holding a reference to `WorkoutRepository`) or receive it as parameters from the calling orchestrator.

## Decision

Domain-specific analytics services (`WorkoutVectorizer`, `PlateauDetectionService`, `MuscleBalanceService`, `ExerciseRecommendationService`) hold no mutable state and do not depend on repositories. Historical context is passed as parameters to their methods.

For example:
- `vectorizer.vectorize(workout, historicalWorkouts: allWorkouts)` -- caller passes historical context
- `plateauService.analyzePlateaus(workouts: recentWorkouts, timeWindow: timeWindow)` -- caller passes filtered workouts
- `muscleBalanceService.analyze(workouts: workouts, timeWindow: timeWindow)` -- caller passes workout list

The `WorkoutAnalyticsService` orchestrator is the only analytics component that holds repository references and fetches data. It passes the fetched data to the stateless services.

Exception: `WorkoutAnalyticsService` itself and `WorkoutQualityScoreService` hold repository references because they are orchestrators, not pure computation services.

## Rationale

- **Testability**: Stateless services with parameter injection are trivially testable. Pass in test workouts, assert on output. No mocking of repositories needed.
- **DDD alignment**: In DDD, domain services should contain business logic without infrastructure concerns. Repository access is an infrastructure concern that belongs in the application/orchestration layer.
- **Composability**: Services can be reused in different contexts. `MuscleBalanceService.analyze()` works equally well whether called from the dashboard orchestrator, a unit test, or a future Watch app.
- **Consistency guarantee**: The orchestrator fetches data once and passes the same snapshot to all services. If services fetched independently, they might get different data snapshots due to concurrent modifications.
- **Simplicity**: Services are plain objects with `init()` and no constructor dependencies (except `WorkoutAnalyticsService` which is explicitly the orchestrator).

## Alternatives Considered

- **Services hold repository references** (each service fetches its own data): Rejected because it makes services harder to test (must mock repositories), creates multiple data fetches for the same data (wasteful), and risks inconsistent data snapshots across services.
- **Shared data context object** (pass a `DataContext` struct with pre-fetched data): Rejected as premature abstraction. Method parameters are simpler and more explicit about what each service needs.
- **Repository injection via protocol** (services depend on repository protocols): Rejected because it adds unnecessary coupling. The services' job is computation, not data access. Let the orchestrator handle data access.
- **Singleton shared state**: Rejected because singletons are untestable, create hidden dependencies, and violate Swift 6 `Sendable` requirements for mutable shared state.

## Consequences

### Positive
- Services are trivially testable (no mocks needed, just pass test data as parameters)
- No hidden dependencies (all inputs are visible in the method signature)
- Services are reusable across different contexts (iOS, Watch, tests)
- Single data fetch in the orchestrator ensures consistent data snapshot across all analyses
- Services have zero constructor dependencies (`init()` with no parameters)

### Negative / Trade-offs
- Method signatures are longer because they include the data parameters (e.g., `vectorize(workout, historicalWorkouts:)` instead of just `vectorize(workout)`)
- The orchestrator (`WorkoutAnalyticsService`) becomes a coordination bottleneck -- all data access goes through it
- Callers must know what data each service needs and provide it

### Neutral
- `WorkoutAnalyticsService` (the orchestrator) holds repository references and is the exception to the "no repository" rule. This is intentional: it is an application service, not a domain service.
- `WorkoutQualityScoreService` also holds a `WorkoutRepository` reference because it needs to fetch historical averages for quality scoring. It is a secondary orchestrator.

## Implementation Notes

- **WorkoutVectorizer** (`Shared/Services/Analytics/WorkoutVectorizer.swift`): `init()` with no parameters. `vectorize(_:historicalWorkouts:)` takes the workout and historical context.
- **PlateauDetectionService** (`Shared/Services/Analytics/PlateauDetectionService.swift`): `init()` with no parameters. `analyzePlateaus(workouts:timeWindow:)` takes pre-fetched workout list.
- **MuscleBalanceService** (`Shared/Services/Analytics/MuscleBalanceService.swift`): `init()` with no parameters. `analyze(workouts:timeWindow:)` takes pre-fetched workout list.
- **ExerciseRecommendationService** (`Shared/Services/Analytics/ExerciseRecommendationService.swift`): `init()` with no parameters. `recommend(for:allWorkouts:availableExercises:muscleBalance:limit:)` takes all context as parameters.
- **WorkoutAnalyticsService** (orchestrator): Holds `analyticsRepository`, `workoutRepository`, `exerciseRepository`, `vectorizer`, `searchService`, `plateauService`, `muscleBalanceService`, `recommendationService`. Fetches data and passes to services.

## References

- [ADR-009: WorkoutInsights Aggregate Root](ADR-009-workout-insights-aggregate-root.md)
- [ADR-011: Repository Single Responsibility](ADR-011-repository-single-responsibility.md)
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 3.1, 3.3, 3.4, 3.5, 3.6
