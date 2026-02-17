# ADR-003: L2 Normalization for Cosine Similarity

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Analytics

## Context

The vector search system needs a distance/similarity metric to compare 18-dimensional workout feature vectors. The metric must be:
- Fast to compute (sub-millisecond for pairwise comparison)
- Interpretable (users see "92% similar" on the UI)
- Scale-invariant (a workout with 2x the volume should not appear dissimilar just because raw values are larger)
- Compatible with Apple Accelerate BLAS operations for hardware acceleration

Common options include cosine similarity, Euclidean distance, and Manhattan distance.

## Decision

L2 normalize all vectors at creation time so that every vector has unit length (`||v|| = 1`). Then use the dot product as the similarity metric, which equals cosine similarity when both vectors are unit-length: `cos(theta) = v1 . v2`.

The normalization is performed in `WorkoutVectorizer.l2Normalize()` using `vDSP_dotprD` and `vDSP_vsdivD` from the Accelerate framework, with a pure-Swift fallback for Linux test builds.

## Rationale

- When vectors are L2 normalized, cosine similarity reduces to a single dot product: `cos(theta) = v1 . v2`. This is a single BLAS call (`vDSP_dotprD`) that completes in under 1 microsecond per pair.
- Cosine similarity is scale-invariant: it measures the angle between vectors, not their magnitude. Two workouts with the same muscle group distribution but different total volumes will have high similarity.
- The output range [-1, 1] maps directly to a percentage for the UI (0.92 = "92% similar"). Typical threshold is 0.7+ for "similar".
- Normalizing at creation time (not query time) means the cost is paid once during vectorization, not on every search query.

## Alternatives Considered

- **Euclidean distance**: Rejected because it is not scale-invariant (magnitude dominates) and produces values in [0, infinity] that are harder to interpret as a similarity percentage. Would require additional normalization for display.
- **Manhattan distance (L1)**: Rejected because it performs poorly in high-dimensional spaces and has no efficient BLAS implementation in Accelerate.
- **Dot product without normalization**: Rejected because raw dot products are not bounded and depend on vector magnitude, making them non-comparable across different workouts.
- **Cosine similarity computed at query time** (without pre-normalization): Rejected because it requires computing the magnitude of both vectors at query time, doubling the computation per comparison.

## Consequences

### Positive
- Single vDSP call per similarity computation (extremely fast)
- Scale-invariant comparison (workout volume magnitude does not skew results)
- Interpretable output range [-1, 1] maps cleanly to UI percentages
- Normalization cost paid once at vectorization time, amortized across all future queries
- Compatible with future HNSW indexing (most HNSW libraries expect normalized vectors for cosine metric)

### Negative / Trade-offs
- Magnitude information is lost after normalization (a 50,000 kg workout and a 5,000 kg workout with the same proportions will appear identical). This is intentional for similarity but means volume comparisons must come from raw data, not vectors.
- If a zero vector is produced (all features are 0), L2 normalization produces NaN. The implementation guards against this by returning the zero vector unchanged.

### Neutral
- The typical similarity threshold of 0.7 for "similar" was chosen empirically and may need tuning as real usage data accumulates

## Implementation Notes

- **L2 normalization in WorkoutVectorizer** (`Shared/Services/Analytics/WorkoutVectorizer.swift`):
  ```swift
  private func l2Normalize(_ vector: [Double]) -> [Double] {
      var magnitude: Double = 0.0
      vDSP_dotprD(vector, 1, vector, 1, &magnitude, vDSP_Length(vector.count))
      magnitude = sqrt(magnitude)
      guard magnitude > 0 else { return vector }
      var divisor = magnitude
      var result = vector
      vDSP_vsdivD(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
      return result
  }
  ```
- **Cosine similarity in VectorSearchService** (`Shared/Services/Analytics/VectorSearchService.swift`): `vDSP_dotprD(a, 1, b, 1, &result, vDSP_Length(a.count))`
- **Linux fallback**: `sqrt(vector.reduce(0) { $0 + $1 * $1 })` for normalization, `zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }` for dot product

## References

- [ADR-001: Pure On-Device Vector Analytics](ADR-001-pure-on-device-vector-analytics.md)
- [Apple Accelerate vDSP documentation](https://developer.apple.com/documentation/accelerate/vdsp)
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 7.2
