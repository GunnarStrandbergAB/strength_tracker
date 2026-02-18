# Webhook Integration for AI Personal Trainer

## Status: Research / Future Implementation

## Summary

Add a configurable webhook that fires after every completed workout, sending the full structured workout data to an external AI agent (OpenClaw, Claude, GPT, or any HTTP endpoint) that can act as a personal trainer — analyzing performance, suggesting recovery, and adjusting programming.

## Current State

- `Workout` model is fully `Codable` — already serializes to JSON for Watch-to-iPhone sync
- Both iOS and watchOS completion flows converge on iPhone (watch sends via `WCSession.transferUserInfo`)
- Zero network calls exist today — no `URLSession`, no external APIs
- Rich data available: exercises, muscle groups, sets (weight/reps/RPE/type), timestamps, duration, volume, notes, personal records

## Architecture

### Hook Points

1. **iOS workouts:** `WorkoutViewModel.completeWorkout()` — after save + HealthKit steps
2. **Watch workouts:** `StrengthTrackeriOS.swift` `onWorkoutReceived` callback — after saving watch workout to iPhone SwiftData

Both paths should call the same `WebhookService`.

### New Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `WebhookService` | `Shared/Services/WebhookService.swift` | Encodes `Workout` to JSON, POSTs to configured URL |
| Webhook URL setting | `UserPreferencesService` | User-configurable endpoint URL + optional bearer token |
| Settings UI | `iOS/Features/Settings/` | Text field for URL, token, test button |

### WebhookService Design

```swift
final class WebhookService {
    private let session: URLSession  // background configuration

    func sendWorkoutCompleted(_ workout: Workout) async {
        guard let url = webhookURL else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONEncoder().encode(workout)
        // Fire and forget — background session handles app suspension
        let _ = try? await session.data(for: request)
    }
}
```

- Use `URLSessionConfiguration.background(withIdentifier:)` so POST completes even if app suspends
- Fire-and-forget: don't block workout completion on network response
- Log failures but don't surface errors to user (workout is already saved locally)

### JSON Payload Structure

```json
{
  "id": "uuid",
  "name": "Push Day",
  "startedAt": "2026-02-18T08:00:00Z",
  "completedAt": "2026-02-18T09:15:00Z",
  "notes": "Felt strong today",
  "templateId": "uuid-or-null",
  "exercises": [
    {
      "id": "uuid",
      "exercise": {
        "name": "Bench Press",
        "primaryMuscleGroup": "chest",
        "category": "barbell",
        "exerciseType": "weightedReps"
      },
      "order": 1,
      "sets": [
        {
          "order": 1,
          "setType": "normal",
          "weight": 100.0,
          "reps": 8,
          "rpe": 7.5,
          "isCompleted": true,
          "isPersonalRecord": false,
          "completedAt": "2026-02-18T08:05:30Z"
        }
      ]
    }
  ]
}
```

## Compatible External Services

### OpenClaw (Primary Target)

- Webhook endpoint: `POST /hooks/agent`
- Authentication: hook token in header
- Spins up isolated agent turn per webhook
- Config: `hooks.enabled: true`, define `hooks.token`
- Docs: https://docs.openclaw.ai/automation/webhook

Payload format for OpenClaw:
```json
{
  "text": "Workout completed: Push Day - 5 exercises, 20 sets, 4500kg volume",
  "mode": "now",
  "data": { /* full Workout JSON */ }
}
```

### Other Compatible Services

| Service | Integration | Notes |
|---------|-------------|-------|
| Claude / GPT API | Direct POST with system prompt | Requires API key, returns coaching text |
| n8n / Make.com / Zapier | Generic webhook trigger | Visual workflow → AI analysis pipeline |
| Terra API | Fitness data middleware | Normalizes across platforms |
| Trainerize | Trainer-facing platform API | For professional trainer dashboards |
| Custom self-hosted | Any HTTP endpoint | Full control over AI model + prompt |

## iOS Constraints

- **Background URLSession** handles app suspension mid-POST reliably
- watchOS cannot make direct HTTP calls easily — Watch sends to iPhone, iPhone fires webhook (existing data flow)
- `sessionSendsLaunchEvents = true` ensures delivery even if app is terminated
- No need for background modes entitlement beyond what background URLSession provides

## Implementation Scope

### Files to Create
- `Shared/Services/WebhookService.swift`

### Files to Modify
- `Shared/ViewModels/WorkoutViewModel.swift` — call webhook after completion
- `iOS/StrengthTrackeriOS.swift` — call webhook in `onWorkoutReceived`
- `Shared/Services/UserPreferencesService.swift` — add webhook URL + token settings
- `Shared/DI/AppContainer.swift` — register WebhookService
- Settings UI view (new or existing)

### Estimated Effort
Small — ~1 day including settings UI and testing.

## Open Questions

1. Should failed webhook deliveries be queued for retry, or just logged?
2. Should there be a way to see webhook delivery history in the app?
3. Should the payload include HealthKit data (calories, heart rate) if available?
4. Should there be preset configurations for popular services (OpenClaw, etc.)?
