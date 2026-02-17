# ADR-007: Local Notifications for Critical Insights

**Status:** Accepted
**Date:** 2026-02-17
**Context Domain:** Analytics

## Context

Analytics insights fall into two categories based on the UX push/pull strategy:

- **Push insights** (proactive): Time-sensitive, actionable alerts that the user benefits from even when not actively using the app. Examples: plateau alert after 4 weeks of stagnation, recovery warning when training a muscle group too soon.
- **Pull insights** (user-initiated): Exploratory analytics the user seeks out intentionally. Examples: similar workouts, exercise recommendations, strength trends, volume analysis.

Push insights lose value if the user only sees them when they happen to open the app. A user stuck in a plateau for 6 weeks because they never checked the dashboard represents a missed opportunity to help.

## Decision

Use `UNUserNotificationCenter` for local push notifications on critical insights only. Notifications are opt-in via the app's Settings screen, with per-category toggles:

- **Plateau Alerts** (toggle, default: on): Fired when an exercise has not progressed for 4+ consecutive weeks
- **Recovery Warnings** (toggle, default: on): Fired when a muscle group was trained less than 24 hours ago with high volume and the user starts a new workout targeting the same group

Exploratory/pull insights (similar workouts, recommendations, strength trends, volume analysis) are never sent as notifications.

All notifications are local (scheduled via `UNUserNotificationCenter`); no backend push notification infrastructure is required.

## Rationale

- Local notifications require no backend, work offline, and respect privacy (no data sent to servers)
- Only critical, actionable insights are pushed; exploratory insights remain pull-only, avoiding notification fatigue
- Opt-in with per-category toggles gives users control over what they receive
- Conservative thresholds (4+ weeks for plateaus, less than 24h + high volume for recovery) minimize false positives
- The notification content is actionable: tapping opens the relevant detail screen with recommendations

## Alternatives Considered

- **Remote push notifications via APNs**: Rejected because the app has no backend. Setting up APNs infrastructure solely for analytics notifications is disproportionate to the use case.
- **In-app-only alerts** (no system notifications): Rejected because users who do not open the app daily would miss time-sensitive plateau alerts. A user stuck for 6 weeks should be notified.
- **Notification for all insight types**: Rejected because sending notifications for "similar workouts found" or "muscle balance updated" would cause notification fatigue and lead users to disable notifications entirely.
- **Background app refresh + notification**: Rejected as overly complex. The insights are computed when the app is active (post-workout or dashboard load); scheduling the notification at that point is sufficient.

## Consequences

### Positive
- Users are alerted to plateaus even if they do not check the dashboard regularly
- Recovery warnings prevent overtraining by reaching users before they start their next workout
- No backend infrastructure required (local notifications only)
- Per-category opt-in prevents notification fatigue
- Tapping a notification deep-links to the relevant insight detail screen

### Negative / Trade-offs
- Notification fatigue risk if thresholds are too aggressive. Mitigated by conservative defaults (4+ weeks for plateau, less than 24h + high volume for recovery).
- Local notifications cannot be sent when the app is not running. Insights are computed only during active use (post-workout or dashboard load), so a user who stops using the app entirely will stop receiving notifications.
- Requires `UNUserNotificationCenter` permission request, which adds a system prompt to the onboarding flow.

### Neutral
- Notification categories (`analytics_plateau`, `analytics_recovery`) enable distinct handling in notification center grouping
- Future phases may add a "Weekly Summary" notification (Phase 4), which would be a separate opt-in category

## Implementation Notes

- **AnalyticsNotificationService** (`Shared/Services/Analytics/AnalyticsNotificationService.swift`): Guarded by `#if canImport(UserNotifications)`. Methods: `requestPermission()`, `notifyPlateau(_:)`, `notifyRecoveryWarning(muscleGroup:hoursSinceLastTraining:)`
- **User preferences**: `plateauNotificationsEnabled` and `recoveryNotificationsEnabled` stored in `UserDefaults` via `UserPreferencesService`
- **Trigger point**: After `WorkoutAnalyticsService.generateInsights()` detects a plateau with `consecutiveWeeksStalled >= 4`, call `notifyPlateau(analysis)`
- **Notification identifiers**: Use `plateau-{exerciseId}` and `recovery-{muscleGroup}` to prevent duplicate notifications for the same condition
- **Settings UI**: Two toggles under "Settings > Notifications" (Plateau Alerts: on/off, Recovery Reminders: on/off)

## References

- [ADR-006: Data-Driven Progressive Disclosure](ADR-006-data-driven-progressive-disclosure.md)
- UX doc: `/workspaces/strength_tracker/docs/architecture/analytics-ux-user-journeys.md` Section "Push vs Pull Insights"
- Architecture doc: `/workspaces/strength_tracker/docs/architecture/vector-analytics-architecture.md` Section 11.6
