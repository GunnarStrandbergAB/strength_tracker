# ADR-010: WorkoutVectorMapper for Entity-Domain Conversion at Float32-Double Boundary

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Persistence

## Context

The architecture uses `Double` (64-bit) for all domain-layer computation and `Float32` (32-bit) for SwiftData persistence (ADR-002). This means every vector crossing the repository boundary must be converted between `[Double]` (domain) and `Data` (packed Float32 bytes, persistence).

The existing codebase follows a consistent mapper pattern: `WorkoutMapper`, `ExerciseMapper`, `TemplateMapper`, and `PersonalRecordMapper` are all `enum` types with static methods (`toDomain(_:)`, `toEntity(_:)`) that handle bidirectional conversion between SwiftData entities and domain models.

The vector conversion is more involved than typical mappers because it includes a numeric precision conversion (Float32 to Double and back) in addition to the standard field mapping.

## Decision

Create `WorkoutVectorMapper` as a caseless `enum` with static methods, following the existing mapper pattern. The mapper handles:

1. **Entity to Domain** (`toDomain(_:)`): Converts `WorkoutVectorEntity` to `WorkoutVector`, including `dataToDoubles()` which unpacks the Float32 `Data` blob into `[Double]`
2. **Domain to Entity** (`toEntity(_:totalVolume:workoutDate:primaryMuscleGroups:)`): Converts `WorkoutVector` to `WorkoutVectorEntity`, including `doublesToData()` which packs `[Double]` into Float32 `Data`
3. **Standalone conversion helpers**: `doublesToData(_:)` and `dataToDoubles(_:)` are public static methods, usable by the repository for partial updates without full entity reconstruction

The mapper is the single location where Float32-to-Double conversion happens. No other code in the system performs this conversion.

## Rationale

- **Consistency**: Follows the existing `WorkoutMapper`, `ExerciseMapper`, `TemplateMapper`, `PersonalRecordMapper` pattern. Developers know where to find conversion logic.
- **Single conversion point**: All Float32-to-Double and Double-to-Float32 conversions happen in exactly one file. This makes the precision boundary auditable and testable.
- **Caseless enum**: Using `enum` (not `struct` or `class`) prevents accidental instantiation. The mapper is a namespace for static functions, not a stateful object.
- **Public conversion helpers**: `doublesToData` and `dataToDoubles` are exposed publicly because the repository needs them for partial updates (e.g., updating just the vector data on an existing entity without reconstructing the full domain model).

## Alternatives Considered

- **Conversion inside the repository**: Rejected because it mixes persistence mechanics (CRUD) with data transformation (Float32-to-Double). The mapper pattern keeps these concerns separate.
- **Conversion inside the domain model**: Rejected because `WorkoutVector` should not know about persistence formats. Domain models should be persistence-ignorant.
- **Extension methods on WorkoutVectorEntity**: Rejected because it couples the entity to the domain model. The mapper serves as a decoupling layer between the two.
- **Protocol-based mapper**: Rejected as unnecessary abstraction. The mapper has no polymorphism needs; it is a simple collection of static functions.

## Consequences

### Positive
- Consistent with existing codebase mapper pattern (developers know where to look)
- Single file contains all Float32-to-Double conversion logic (auditable, testable)
- Repository code stays clean (delegates conversion to mapper)
- Domain model (`WorkoutVector`) remains persistence-ignorant

### Negative / Trade-offs
- One additional file in the codebase (`WorkoutVectorMapper.swift`)
- Developers must remember to use the mapper rather than performing inline conversion

### Neutral
- The mapper uses `Data(bytes:count:)` and `withUnsafeBytes { bindMemory(to:) }` for efficient zero-copy conversion between `[Float]` and `Data`
- The mapper does not validate vector dimensionality (18 elements); that constraint is enforced by `WorkoutVector.init` via `precondition`

## Implementation Notes

- **File**: `Shared/Persistence/Mappers/WorkoutVectorMapper.swift`
- **toDomain**: Maps all entity fields to domain fields, calls `dataToDoubles(entity.vectorData)` for the dimensions array
- **toEntity**: Maps all domain fields to entity fields, calls `doublesToData(domain.dimensions)` for the vectorData blob. Requires additional parameters (`totalVolume`, `workoutDate`, `primaryMuscleGroups`) that come from the workout, not the vector.
- **doublesToData**: `dimensions.map { Float($0) }` then `Data(bytes: floats, count: floats.count * MemoryLayout<Float>.stride)`
- **dataToDoubles**: `data.withUnsafeBytes { Array(buffer.bindMemory(to: Float.self)) }.map { Double($0) }`

## References

- [ADR-002: Double Computation, Float32 Storage](ADR-002-double-computation-float32-storage.md)
- [ADR-004: SwiftData for Vector Storage](ADR-004-swiftdata-vector-storage.md)
- Existing mappers: `Shared/Persistence/Mappers/WorkoutMapper.swift`, `ExerciseMapper.swift`, `TemplateMapper.swift`, `PersonalRecordMapper.swift`
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 2.4
