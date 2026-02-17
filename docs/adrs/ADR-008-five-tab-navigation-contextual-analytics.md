# ADR-008: Five-Tab Navigation with Contextual Analytics Entry Points

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Navigation

## Context

The existing StrengthTracker app uses a 5-tab `TabView` for its primary navigation: Dashboard (0), Workout (1), Templates (2), Exercises (3), and History (4). These tabs serve core transactional workflows: starting workouts, logging sets, managing templates, browsing exercises, and viewing history.

Adding vector-based analytics introduces a significant new feature surface. The question is how to integrate analytics into the navigation structure. Options include adding a 6th tab, replacing an existing tab, or embedding analytics as contextual screens accessible from existing tabs.

Apple's Human Interface Guidelines recommend a maximum of 5 tabs on iPhone. A 6th tab forces the system to display a "More" overflow menu on smaller devices, which buries content behind an extra tap.

## Decision

Keep the existing 5-tab `TabView` unchanged. Analytics is accessed via contextual entry points using push navigation (`NavigationLink`) and modal presentation (`.sheet`), not a dedicated tab.

Entry points:

| Entry Point | Navigation | Target Screen |
|-------------|------------|---------------|
| Dashboard > Insights Card > "View All" | `NavigationLink` push | `WorkoutAnalyticsView` (full analytics dashboard) |
| Dashboard > Insights Card > tap individual card | `.sheet` | Insight detail (plateau, muscle balance, etc.) |
| Post-Workout Sheet > "View Similar" | `.sheet` | `SimilarWorkoutsView` |
| History > Workout Detail > "Similar" | `NavigationLink` push | `SimilarWorkoutsView` |
| Exercises > Exercise Detail > Insights tab | In-place tab within detail view | Plateau detection, recommendations |

This keeps `ContentView.swift` unchanged (no new tabs) and surfaces insights where they are most relevant to the user's current context.

## Rationale

- Apple HIG recommends max 5 tabs on iPhone; a 6th forces "More" overflow on smaller screens
- The current 5 tabs serve transactional workflows (start workout, log sets, manage templates). Analytics is exploratory, not transactional -- it does not need persistent tab-level presence.
- Contextual entry points surface insights where they are most relevant: plateau alerts on the Dashboard, similar workouts after completing a workout, exercise-specific insights on the Exercise Detail screen.
- The "Insights Card" on the Dashboard acts as a discovery mechanism, drawing users into analytics without requiring them to know where to find it.
- No changes to `ContentView.swift` reduces the risk of regressions in the existing navigation structure.

## Alternatives Considered

- **Add a 6th "Analytics" tab**: Rejected because it violates Apple HIG (max 5 tabs), creates "More" overflow on smaller iPhones, and analytics is exploratory rather than transactional.
- **Replace the History tab with an Analytics tab**: Rejected because History is a core transactional workflow (reviewing past workouts, finding workout details). Removing it would break existing user expectations.
- **Bottom sheet / floating button**: Rejected because it clutters the workout flow and lacks the contextual relevance of entry-point-based navigation.
- **Sidebar navigation** (iPad-style): Rejected because the app targets iPhone primarily, and sidebar navigation is not idiomatic for iPhone apps in this category.

## Consequences

### Positive
- Complies with Apple HIG (max 5 tabs)
- No changes to `ContentView.swift` or existing tab structure
- Analytics surfaces contextually (post-workout, exercise detail, dashboard) where it is most actionable
- The "Insights Card" on Dashboard provides a natural discovery path
- Reduces cognitive load: users encounter analytics in context, not as a separate destination they must remember to visit

### Negative / Trade-offs
- Analytics is not one tap away from any screen (users must navigate through Dashboard or other entry points)
- Discoverability depends on the Dashboard Insights Card being visible; if the user scrolls past it, they may not find analytics
- Multiple entry points to the same analytics screens may cause confusion about navigation hierarchy

### Neutral
- The full Analytics Dashboard screen (`WorkoutAnalyticsView`) is a pushed screen from Dashboard, giving it a clear "back" navigation path
- `ContentView.swift` remains a 5-tab TabView with no modifications

## Implementation Notes

- **Dashboard Insights Card**: New SwiftUI view component added to `DashboardView`, positioned after the Weekly Frequency chart. Contains a swipeable carousel (3-5 insight cards) with priority ordering (plateaus > balance > recovery > milestones > recommendations).
- **NavigationLink push to analytics**: `NavigationLink { WorkoutAnalyticsView(viewModel: ...) } label: { InsightsCardView() }` within the Dashboard's `NavigationStack`
- **Post-workout sheet**: Existing completion sheet gains a "View Similar" button that presents `SimilarWorkoutsView` as a `.sheet`
- **Exercise Detail**: Add an "Insights" tab alongside the existing "Progress" tab, containing per-exercise plateau detection and recommendations
- **History > Workout Detail**: Add a "Similar Workouts" section with a `NavigationLink` push

## References

- [Apple HIG: Tab Bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- UX doc: `/workspaces/strength_tracker/docs/architecture/analytics-ux-user-journeys.md` Section "Entry Points & Navigation", "Navigation Hierarchy"
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 1.3
- Existing file: `/workspaces/strength_tracker/StrengthTracker/iOS/App/ContentView.swift`
