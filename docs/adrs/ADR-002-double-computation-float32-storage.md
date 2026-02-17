# ADR-002: Double for Computation, Float32 for Storage

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Persistence

## Context

The analytics system operates on 18-dimensional feature vectors that are computed, normalized, compared via dot products, and stored persistently. Two numeric precisions are available: `Double` (64-bit, 8 bytes per element) and `Float` (32-bit, 4 bytes per element).

Computation accuracy matters because L2 normalization and cosine similarity involve cumulative floating-point operations (square roots, divisions, sums of products) where precision errors can compound. Storage efficiency matters because vectors are persisted in SwiftData and loaded into memory for similarity search.

The question is where to draw the precision boundary.

## Decision

Use `Double` (64-bit) in domain models (`WorkoutVector.dimensions: [Double]`) and all service-layer computation (`WorkoutVectorizer`, `VectorSearchService`, `PlateauDetectionService`). Use `Float32` (32-bit) only for SwiftData persistence via `WorkoutVectorEntity.vectorData: Data` (a packed byte buffer of 18 Float32 values).

The conversion between Float32 and Double happens exclusively at the repository boundary, inside `WorkoutVectorMapper.doublesToData()` and `WorkoutVectorMapper.dataToDoubles()`.

## Rationale

- `Double` precision avoids cumulative floating-point errors in L2 normalization (sqrt of sum of squares) and cosine similarity (dot product of normalized vectors)
- `Float32` storage saves 50% space: 72 bytes per vector (18 x 4) vs 144 bytes (18 x 8)
- At 2,000 workouts, this saves 144 KB of storage and memory during bulk loads
- The precision loss from a Double-to-Float32-to-Double round-trip is less than 0.0001 in similarity scores, which is well within acceptable tolerance
- Conversion overhead is negligible (18 elements, single pass) and happens only at persistence boundaries

## Alternatives Considered

- **Double everywhere (computation and storage)**: Rejected because it doubles storage size for no meaningful accuracy benefit in the final similarity scores. The storage savings are small in absolute terms but meaningful as a design principle.
- **Float32 everywhere (computation and storage)**: Rejected because Float32 precision loss can compound during L2 normalization and repeated dot product operations, especially when vectors have many near-zero dimensions. Using Double for computation avoids this class of bug entirely.
- **Mixed precision at the service level**: Rejected as too complex. Having a single clear boundary (the mapper) is simpler to reason about and test than having different services use different precisions.

## Consequences

### Positive
- Clean separation: domain layer always works with `Double`, persistence layer uses `Float32`
- 50% storage savings on vector data (72 bytes vs 144 bytes per workout)
- Negligible precision loss (less than 0.0001 on similarity scores)
- Single conversion point (`WorkoutVectorMapper`) makes the boundary testable and auditable

### Negative / Trade-offs
- Requires a dedicated mapper with explicit conversion methods (`doublesToData`, `dataToDoubles`)
- Developers must remember that `WorkoutVectorEntity.vectorData` contains Float32, not Double

### Neutral
- The `WorkoutVectorMapper` follows the existing codebase pattern (`WorkoutMapper`, `ExerciseMapper`, `TemplateMapper`, `PersonalRecordMapper`), so the approach is consistent

## Implementation Notes

- **WorkoutVectorMapper** (`Shared/Persistence/Mappers/WorkoutVectorMapper.swift`): `enum` with static methods `toDomain(_:)` and `toEntity(_:totalVolume:workoutDate:primaryMuscleGroups:)`
- **doublesToData**: `dimensions.map { Float($0) }` then pack as `Data(bytes:count:)`
- **dataToDoubles**: `data.withUnsafeBytes { Array(buffer.bindMemory(to: Float.self)) }` then `.map { Double($0) }`
- **WorkoutVectorEntity** (`Shared/Persistence/SwiftData/Entities/WorkoutVectorEntity.swift`): stores `vectorData: Data` with `@Attribute(.externalStorage)`

## References

- [ADR-001: Pure On-Device Vector Analytics](ADR-001-pure-on-device-vector-analytics.md)
- [ADR-010: Mapper Layer Float-Double Boundary](ADR-010-mapper-layer-float-double-boundary.md)
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 2.3, 2.4
