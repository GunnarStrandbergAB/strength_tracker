# ADR-004: SwiftData for Vector Storage

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Persistence

## Context

The 18-dimensional feature vectors extracted from workouts need to be stored persistently so they survive app restarts and do not need to be recomputed on every launch. Storage options include:
- Adding vector data to the existing SwiftData persistence layer
- Using a separate SQLite database
- Using a dedicated vector database (e.g., FAISS, Hnswlib)
- Storing in flat files or UserDefaults

The existing app uses SwiftData exclusively for persistence, with entities for workouts, exercises, sets, templates, and personal records. All entities are managed through a single `ModelContext` obtained from `AppContainer`.

## Decision

Store vectors as a new `WorkoutVectorEntity` in SwiftData, linked to `WorkoutEntity` via a 1:1 `@Relationship(deleteRule: .cascade)`. The vector data is stored as a packed `Data` blob (72 bytes of Float32 values) with `@Attribute(.externalStorage)`.

The entity includes denormalized fields (`totalVolume`, `workoutDate`, `primaryMuscleGroups`) for faster querying without needing to join back to `WorkoutEntity`.

## Rationale

- Leverages the existing persistence layer with no new database dependencies
- `@Relationship(deleteRule: .cascade)` ensures vectors are automatically deleted when their parent workout is deleted
- ACID guarantees from SwiftData prevent orphaned or corrupt vector data
- SwiftData's lightweight migration handles schema additions automatically (the new entity and relationship are additive)
- Denormalized fields enable efficient filtering (by date range, muscle group) without joining across entities
- Fetch performance of less than 5ms for 2,000 vectors is well within acceptable limits

## Alternatives Considered

- **Separate SQLite database**: Rejected because it introduces a second persistence layer that must be kept in sync with SwiftData. Cascade deletes, transactions, and schema versioning become the developer's responsibility.
- **Dedicated vector database (FAISS, Hnswlib)**: Rejected as overkill for the expected data volume (under 5,000 vectors). These libraries add native binary dependencies and deployment complexity. Can be revisited if the dataset grows beyond 5,000 workouts (see future HNSW extension in architecture doc).
- **In-memory only**: Rejected because vectors would need to be recomputed on every app launch, taking 5+ seconds for 100 workouts.
- **UserDefaults or flat files**: Rejected due to lack of indexing, query capability, and relationship management.

## Consequences

### Positive
- Single persistence layer (SwiftData) for the entire app
- Automatic cascade delete when workouts are removed
- Lightweight schema migration (SwiftData handles additive changes)
- ACID transaction guarantees
- Denormalized fields enable fast filtered queries without joins

### Negative / Trade-offs
- Slightly slower than pure in-memory storage for bulk similarity search (must fetch from disk on cold start), but less than 5ms for full fetch is acceptable
- `@Attribute(.externalStorage)` means the 72-byte vector blob may be stored in a separate file by SwiftData, adding minor I/O overhead
- SwiftData's `#Predicate` cannot query inside the packed `Data` blob; all vector math must happen after fetching into memory

### Neutral
- The `WorkoutVectorEntity` adds approximately 150-200 bytes per workout to the database (including denormalized fields and metadata)
- The `workoutVector` relationship on `WorkoutEntity` is optional (`WorkoutVectorEntity?`), so existing workouts without vectors remain valid

## Implementation Notes

- **WorkoutVectorEntity** (`Shared/Persistence/SwiftData/Entities/WorkoutVectorEntity.swift`): `@Model` class with `id`, `workoutId`, `createdAt`, `vectorData: Data`, `totalVolume`, `workoutDate`, `primaryMuscleGroups`
- **WorkoutEntity extension**: Add `@Relationship(deleteRule: .cascade) public var workoutVector: WorkoutVectorEntity?`
- **Schema registration**: Add `WorkoutVectorEntity.self` to the `Schema([...])` array in `AppContainer.init()`
- **SwiftDataAnalyticsRepository** (`Shared/Persistence/SwiftData/Repositories/SwiftDataAnalyticsRepository.swift`): CRUD operations using `FetchDescriptor` with predicates on `workoutId`, `workoutDate`

## References

- [ADR-002: Double Computation, Float32 Storage](ADR-002-double-computation-float32-storage.md)
- [ADR-011: Repository Single Responsibility](ADR-011-repository-single-responsibility.md)
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 2.3, 4.4, 5.2
