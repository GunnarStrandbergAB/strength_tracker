# Architecture Decision Records (ADR) Index

**Project:** StrengthTracker iOS App
**Domain:** Vector-Based Workout Analytics
**Last Updated:** 2026-02-17

---

## ADR Registry

| ADR | Status | Domain | Summary |
|-----|--------|--------|---------|
| [ADR-001](ADR-001-pure-on-device-vector-analytics.md) | Accepted | Analytics | Use 18-dim feature vectors + Accelerate vDSP for on-device similarity search (no cloud, no ML models) |
| [ADR-002](ADR-002-double-computation-float32-storage.md) | Accepted | Persistence | Double (64-bit) for computation, Float32 (32-bit) for SwiftData storage, conversion at repository boundary |
| [ADR-003](ADR-003-l2-normalization-cosine-similarity.md) | Accepted | Analytics | L2 normalize all vectors at creation; cosine similarity via dot product for scale-invariant comparison |
| [ADR-004](ADR-004-swiftdata-vector-storage.md) | Accepted | Persistence | Store vectors as WorkoutVectorEntity in SwiftData with cascade delete from WorkoutEntity |
| [ADR-005](ADR-005-background-vectorization.md) | Accepted | Services | Vectorize in background after workout completion; on-demand fallback; batch migration on upgrade |
| [ADR-006](ADR-006-data-driven-progressive-disclosure.md) | Accepted | Analytics | AnalyticsFeatureGate with workout-count thresholds (5/10/20/50) to unlock features progressively |
| [ADR-007](ADR-007-local-notifications-critical-insights.md) | Accepted | Analytics | Local notifications for plateau alerts and recovery warnings only; opt-in per category |
| [ADR-008](ADR-008-five-tab-navigation-contextual-analytics.md) | Accepted | Navigation | Keep 5-tab TabView; analytics accessed via NavigationLink push from Dashboard/Exercise/History |
| [ADR-009](ADR-009-workout-insights-aggregate-root.md) | Accepted | Domain Modeling | WorkoutInsights struct as read-side aggregate root grouping all dashboard analytics into one consistent snapshot |
| [ADR-010](ADR-010-mapper-layer-float-double-boundary.md) | Accepted | Persistence | WorkoutVectorMapper enum for entity-domain conversion with Float32-Double at the repository boundary |
| [ADR-011](ADR-011-repository-single-responsibility.md) | Accepted | Domain Modeling | AnalyticsRepository for vector CRUD only; workout queries stay on WorkoutRepository |
| [ADR-012](ADR-012-stateless-services-context-injection.md) | Accepted | Services | Analytics services hold no mutable state; historical context passed as parameters from orchestrator |
| [ADR-013](ADR-013-computed-domain-recommendations.md) | Accepted | Domain Modeling | Recommendation text as computed properties on domain models (PlateauAnalysis, MuscleImbalance) |

---

## ADRs by Domain

### Analytics
- ADR-001: Pure On-Device Vector Analytics
- ADR-003: L2 Normalization for Cosine Similarity
- ADR-006: Data-Driven Progressive Disclosure
- ADR-007: Local Notifications for Critical Insights

### Persistence
- ADR-002: Double Computation, Float32 Storage
- ADR-004: SwiftData for Vector Storage
- ADR-010: Mapper Layer Float-Double Boundary

### Domain Modeling
- ADR-009: WorkoutInsights Aggregate Root
- ADR-011: Repository Single Responsibility
- ADR-013: Computed Domain Recommendations

### Navigation
- ADR-008: Five-Tab Navigation with Contextual Analytics

### Services
- ADR-005: Background Vectorization
- ADR-012: Stateless Services with Context Injection

---

## Source Documents

These ADRs were extracted from:
1. `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` -- Main architecture specification (ADR-001 through ADR-007 defined explicitly; ADR-009 through ADR-013 extracted from embedded design decisions)
2. `/workspaces/strength_tracker/docs/architecture/analytics-ux-user-journeys.md` -- UX design specification (ADR-008 derived from navigation strategy)
