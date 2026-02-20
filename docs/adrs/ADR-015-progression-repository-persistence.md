# ADR-015: Progression Repository & SwiftData Persistence

**Status:** Accepted
**Date:** 2026-02-20
**Context:** Progression Planning Module — Persistence Layer

## Decision

Single `ProgressionPlanRepository` protocol in `Shared/Repositories/Protocols/`. SwiftData implementation stores `ProgressionPlan` as a single entity with JSON-serialized blocks/exercises/adjustments (matching the analytics module pattern from ADR-004). Tolerant decoding handles optional v3 fields.

## Files
- `Shared/Repositories/Protocols/ProgressionPlanRepository.swift` — Protocol (10 methods)
- `Shared/Persistence/SwiftData/Entities/ProgressionPlanEntity.swift` — `@Model` with JSON Data columns
- `Shared/Persistence/Mappers/ProgressionPlanMapper.swift` — Bidirectional mapping with tolerant decoding
- `Shared/Persistence/SwiftData/Repositories/SwiftDataProgressionPlanRepository.swift` — Implementation
- `Tests/UnitTests/Progression/Mocks/InMemoryProgressionPlanRepository.swift` — Test mock

## Key Decisions
- JSON serialization for nested structures (blocks, weeks, sessions) — matches ADR-004
- Optimistic concurrency via `updatedAt` timestamp check before save
- Deferred writes: batch updates, save on session completion not per-set
- `#if canImport(SwiftData)` guards for Linux test compatibility
- Schema versioning field for future migrations

## Consequences
- No schema migration needed for v2→v3 (new Optional fields with nil defaults)
- InMemoryRepository enables full service testing on Linux
