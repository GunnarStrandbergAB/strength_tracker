# ADR-006: Data-Driven Progressive Disclosure

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Analytics

## Context

Analytics features require minimum amounts of historical data to produce meaningful, accurate insights. Showing an empty plateau detection screen to a user with 3 workouts is confusing and erodes trust. Conversely, hiding all analytics until a user has 50+ workouts means beginners get no value from the feature for weeks.

Three user personas drive the design:
- **Sarah (beginner, 3 months)**: Needs simple guidance, not data overload
- **Marcus (intermediate, 2 years)**: Wants plateau detection and volume optimization
- **Jasmine (advanced, 5+ years)**: Wants granular data, cycle comparisons, predictions

The challenge is to provide value at every stage of the user's journey while ensuring insights are statistically meaningful.

## Decision

Use `AnalyticsFeatureGate` with workout-count thresholds to automatically unlock features in four progressive phases:

| Phase | Workouts | Features Unlocked |
|-------|----------|-------------------|
| 1: Onboarding | 1-4 | Basic stats, PR tracking only |
| 2: Basic Insights | 5-19 | Quality score, strength trends, exercise recommendations, similar workouts (10+) |
| 3: Full Analytics | 20-49 | Plateau detection, muscle balance, recovery timeline |
| 4: Advanced | 50+ | Volume optimization, cycle comparisons, predictive analytics |

No manual feature flags or server-side configuration. The gate queries `WorkoutRepository.fetchCompletedCount()` and compares against static thresholds.

The UI shows a progress indicator for locked features: "Complete 3 more workouts to unlock Muscle Balance" with a progress bar.

## Rationale

- Workout count directly correlates with data sufficiency (more workouts = more reliable statistics)
- Automatic unlocking requires no admin intervention, no backend, and no feature flag service
- Progressive disclosure prevents information overload for beginners (Sarah persona)
- The "X more workouts to unlock..." messaging gamifies consistency and encourages regular use
- Thresholds are aligned with statistical minimums: plateau detection needs at least 8 weeks of per-exercise data (~20 workouts); cycle comparisons need multiple training blocks (~50 workouts)
- Empty states with progress indicators are better UX than empty charts with "No data" labels

## Alternatives Considered

- **Boolean feature flags** (manual toggle per feature): Rejected because they require developer intervention to enable features for each user, and they do not adapt to the user's data volume.
- **Server-side feature flags** (LaunchDarkly, Firebase Remote Config): Rejected as overkill for a fully on-device app. Adds network dependency and third-party service cost.
- **Time-based unlocking** (unlock after 4 weeks): Rejected because time does not correlate with data availability. A user who trains once a week for 4 weeks has only 4 data points.
- **All features available immediately** (with "insufficient data" warnings): Rejected because showing empty or inaccurate analytics hurts user trust and creates a poor first impression.

## Consequences

### Positive
- Users see value at every stage of their journey
- Beginners are not overwhelmed; advanced users get full access
- Gamification element ("3 more workouts to unlock...") encourages consistency
- No backend or service dependency for feature management
- Insights are only shown when they have enough data to be statistically meaningful

### Negative / Trade-offs
- Static thresholds may not be optimal for all training patterns (e.g., a user who does high-frequency full-body training may reach 50 workouts faster than a 3-day split user but with less per-exercise data)
- Users cannot manually unlock features early, even if they understand the limitations

### Neutral
- The threshold values (5/10/20/50) are initial estimates that can be tuned based on user feedback without changing the architecture
- The `AnalyticsFeatureGate` is queried at analytics load time, so threshold changes take effect on the next app session

## Implementation Notes

- **AnalyticsFeatureGate** (`Shared/Services/Analytics/AnalyticsFeatureGate.swift`): Holds a `[Feature: Int]` dictionary of thresholds. Methods: `isUnlocked(_:)`, `unlockedFeatures()`, `nextUnlock()`
- **Integration**: `WorkoutAnalyticsService.generateInsights()` respects the gate internally, returning empty arrays for locked features
- **ViewModel**: `WorkoutAnalyticsViewModel.nextFeatureUnlock` exposes the next unlock milestone to the UI for progress indicator display
- **Empty state views**: Show illustration, progress bar, and "Complete X more workouts to unlock Y" copy (see UX doc Phase 1 wireframe)

## References

- [ADR-007: Local Notifications for Critical Insights](ADR-007-local-notifications-critical-insights.md)
- UX doc: `/workspaces/strength_tracker/docs/architecture/analytics-ux-user-journeys.md` Section "Progressive Disclosure" (Phases 1-4)
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 10.3
