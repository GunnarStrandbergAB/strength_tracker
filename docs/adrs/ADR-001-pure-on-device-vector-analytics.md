# ADR-001: Pure On-Device Vector Analytics

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Analytics

## Context

StrengthTracker needs workout similarity search, plateau detection, muscle balance analysis, and exercise recommendations. These analytics features require comparing workouts to find patterns across a user's training history. The question is whether to use cloud-based ML/embedding services, on-device ML models, or a simpler feature-engineering approach.

Workout data is inherently numeric (weights, reps, sets, durations, muscle group volumes), which means the raw data is already well-structured for vector-based comparison without needing semantic embedding from an LLM.

The app targets privacy-conscious fitness users who expect their data to stay on their device. Adding cloud dependencies introduces latency, cost per API call, and a network requirement that conflicts with the gym environment (poor connectivity).

## Decision

Use hand-crafted 18-dimensional feature vectors extracted from workout data, combined with Apple's Accelerate framework (vDSP) for cosine similarity computation. All analytics run entirely on-device with no cloud services or network calls.

The 18 dimensions capture: volume (normalized), average weight, average reps, set count, exercise diversity, duration, muscle group ratios (chest, back, legs, shoulders, arms, core), compound exercise ratio, average RPE, volume change vs 7-day and 30-day moving averages, PR count, and time-of-day encoding.

## Rationale

- Workout data is already numeric; no natural language processing or semantic understanding is needed
- Linear scan with vDSP-optimized dot products completes in less than 5ms for 2,000 workouts (sufficient for years of training history)
- Zero marginal cost per computation (no API fees)
- Works offline (critical for gym environments with poor connectivity)
- Complete user privacy (no data leaves the device)
- No dependency on external services or API key management
- Feature engineering is transparent and debuggable (each dimension has a clear meaning)

## Alternatives Considered

- **OpenAI/cloud embeddings**: Rejected due to per-request cost, network latency (200-500ms per call), offline unavailability, and privacy concerns. Workout data does not benefit from semantic understanding.
- **Core ML on-device models**: Rejected as overkill for structured numeric data. Core ML adds framework complexity, model management, and versioning overhead without meaningful benefit over direct vector math.
- **Pure heuristic matching** (no vectors, just rule-based similarity): Rejected because it lacks the multi-dimensional distance comparison that makes vector search powerful. Rules become brittle as more features are added.

## Consequences

### Positive
- Zero cloud costs, zero network dependency
- Sub-5ms similarity search across full workout history
- Complete offline functionality
- Full user privacy (no data transmission)
- Transparent, debuggable feature vectors (each dimension is interpretable)
- Leverages Apple silicon hardware acceleration via Accelerate/vDSP

### Negative / Trade-offs
- Feature engineering requires domain expertise (choosing the right 18 dimensions)
- Adding new features requires code changes and re-vectorization of existing workouts
- Cannot capture semantic relationships (e.g., "bench press is similar to dumbbell press") without explicit encoding

### Neutral
- The 18-dimension vector schema is a reasonable starting point but may evolve as usage patterns emerge
- Performance will remain excellent up to approximately 5,000 workouts; HNSW indexing can be added later if needed (see ADR-001 future extension)

## Implementation Notes

- **WorkoutVectorizer** (`Shared/Services/Analytics/WorkoutVectorizer.swift`): Stateless service that extracts 18-dimensional feature vectors from `Workout` domain models
- **VectorSearchService** (`Shared/Services/Analytics/VectorSearchService.swift`): Uses `Accelerate.vDSP_dotprD` for batch dot product computation
- **Fallback path**: `#if canImport(Accelerate)` guard with pure-Swift fallback for Linux test builds
- **Normalization**: L2 normalization applied post-extraction (see ADR-003)

## References

- [ADR-003: L2 Normalization for Cosine Similarity](ADR-003-l2-normalization-cosine-similarity.md)
- [ADR-002: Double Computation, Float32 Storage](ADR-002-double-computation-float32-storage.md)
- [Apple Accelerate vDSP documentation](https://developer.apple.com/documentation/accelerate/vdsp)
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 1.1, 3.1, 3.2
