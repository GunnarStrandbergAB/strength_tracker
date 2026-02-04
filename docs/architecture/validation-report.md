# Architecture Validation Report -- Strength Tracker

**Date:** January 2026
**Validated Against:** Research documents in `docs/research/`
**Architecture Document:** `docs/architecture/system-architecture.md`

---

## 1. Feature Coverage Matrix

The following table maps every feature identified in `docs/research/strong-app-features.md` to its coverage in the architecture and data model.

### 1.1 Exercise Library Features

| Feature | Status | Notes |
|---------|--------|-------|
| 300+ pre-loaded exercises | Covered | `ExerciseLibrary.json` resource with 200+ exercises defined in data model; expandable |
| Exercise name, primary/secondary muscles | Covered | `Exercise` entity has `primaryMuscleGroup` and `secondaryMuscleGroups` fields |
| Equipment categorization | Covered | `ExerciseCategory` enum covers barbell, dumbbell, machine, cable, bodyweight, kettlebell, resistance band, and more |
| Exercise type / tracking type | Covered | `ExerciseType` enum: weightedReps, bodyweightReps, duration, cardio, weightedCardio |
| Exercise instructions (text) | Covered | `instructions` field on `Exercise` entity |
| Static illustration images | Not Covered | No field for exercise images exists in the data model. Strong provides start/end position illustrations per exercise. If images are desired, an `imageName` or asset reference field would be needed on the Exercise entity. However, exercise video descriptions are explicitly not required per project scope. |
| Custom exercise creation | Covered | `isCustom` boolean on `Exercise`; `CreateExerciseView` in iOS app |
| Custom exercises: name, muscle group, equipment, category | Covered | All fields present on `Exercise` entity |
| Exercise search (instant, partial matching) | Covered | `ExerciseListView` with search; index on `name` field |
| Filter by muscle group | Covered | Index on `primaryMuscleGroup`; filter chips implied by `ExerciseListView` |
| Filter by equipment type | Covered | Index on `category` field |
| Recent exercises section | Partially Covered | No explicit "recently used" tracking field on `Exercise`. Can be derived by querying `WorkoutExercise` by date, but a `lastUsedAt` field on `Exercise` would improve performance |
| Favorites mechanism | Not Covered | No `isFavorite` boolean on the `Exercise` entity. This is a commonly-used Strong feature for quick access. Recommend adding `isFavorite: Bool` to `Exercise` |
| Exercise archived state | Covered | `isArchived` field on `Exercise` |

### 1.2 Workout Logging Features

| Feature | Status | Notes |
|---------|--------|-------|
| Full-screen active workout view | Covered | `ActiveWorkoutView` in iOS feature module |
| Editable workout title | Covered | `name` field on `Workout` entity |
| Elapsed timer always visible | Covered | `startedAt` field enables duration computation; architecture includes timer in active workout view |
| Exercise cards with set table | Covered | `WorkoutExercise` -> `ExerciseSet` hierarchy; `ExerciseSetRowView` component |
| Set columns: number, previous, weight, reps, check | Covered | `order`, `weight`, `reps`, `isCompleted` on `ExerciseSet`; previous performance derivable from history queries |
| Numeric keypad for weight entry | Covered | `NumericInputField` component listed in project structure |
| Set completion highlights row | Covered | `isCompleted` boolean enables styling; `completedAt` timestamp |
| Auto-start rest timer on set completion | Covered | `RestTimerService` + `autoStartRestTimer` in `UserSettings` |
| Swipe to delete sets | Covered | SwiftUI `swipeActions` modifier; supported in iOS 16+ |
| Long-press / drag to reorder sets | Covered | SwiftUI `onMove` modifier; `order` field on `ExerciseSet` |
| Set types: Normal, Warm-up, Drop, Failure | Covered | `SetType` enum includes normal, warmup, dropset, failure, plus restPause |
| Set type toggle by tapping indicator | Covered | `SetTypeIndicator` component in project structure |
| Supersets (grouped exercises) | Covered | `supersetGroup` integer on `WorkoutExercise` and `TemplateExercise` |
| Superset visual bracket | Partially Covered | Data model supports it; UI implementation detail not explicitly called out but implied |
| Rest timer per-exercise configurable | Covered | `restTimerSeconds` on `WorkoutExercise` |
| Global default rest timer fallback | Covered | `defaultRestTimerSeconds` in `UserSettings` |
| Rest timer push notification | Covered | `RestTimerService` + notification architecture; APNs shown in system diagram |
| Rest timer Watch haptic | Covered | `WatchRestTimerView` with haptic feedback |
| Rest timer skip / +30s / -30s | Partially Covered | `RestTimerService` exists but specific skip/adjust controls are implementation detail; should be ensured in UI spec |
| Workout templates | Covered | `WorkoutTemplate` and `TemplateExercise` entities; `WorkoutListView` is template-first |
| Template stores: name, exercises, target sets/reps/weight, supersets, rest times | Covered | All fields present on `TemplateExercise` including `supersetGroup`, `restTimerSeconds`, `targetSets`, `targetReps`, `targetWeight` |
| Template-first home screen | Covered | `WorkoutListView` described as "Templates + Quick Start" |
| Quick Start (empty workout) | Covered | Listed in both iPhone and Watch feature tables |
| Template folders | Covered | `TemplateFolder` entity with `sortOrder` |
| Notes per exercise | Covered | `notes` field on `WorkoutExercise` |
| Notes per workout | Covered | `notes` field on `Workout` |
| Auto-fill from previous session | Covered | Previous performance query pattern in data model appendix; `targetWeight` from template |
| Drag-and-drop exercise reorder | Covered | `order` field on `WorkoutExercise`; SwiftUI `onMove` |
| Replace exercise mid-workout | Partially Covered | Can be implemented by updating `exerciseId` on `WorkoutExercise`; no explicit view/flow defined |
| Cancel/discard workout | Partially Covered | `isInProgress` flag supports this; explicit discard flow should be in UI spec |
| Add exercise mid-workout | Covered | `AddExerciseView` component |
| RPE tracking per set | Covered | `rpe` field on `ExerciseSet`; `showRPE` toggle in `UserSettings` |

### 1.3 Workout Summary Features

| Feature | Status | Notes |
|---------|--------|-------|
| Total duration | Covered | Computed from `startedAt` / `completedAt` |
| Total volume | Covered | Computed property defined in data model (weight x reps for working sets) |
| Sets completed count | Covered | Countable from `ExerciseSet` where `isCompleted == true` |
| PRs broken (highlighted) | Covered | `isPersonalRecord` flag on `ExerciseSet`; `PRDetectionService` |
| Muscle group body map | Partially Covered | `muscleGroupsWorked` computed property exists in data model; visual body map rendering is an implementation detail not in architecture but derivable |
| Share as image | Not Covered | No `WorkoutSummaryShareService` or sharing mechanism defined in architecture. Strong allows sharing post-workout summaries as images to social/messages. Recommend adding a share component. |

### 1.4 History and Progression Features

| Feature | Status | Notes |
|---------|--------|-------|
| Reverse chronological workout list | Covered | `WorkoutHistoryView`; index on `startedAt DESC` |
| Calendar view with workout dots | Covered | `CalendarView` in History feature |
| Search/filter by exercise name and date | Covered | Query patterns defined in data model appendix |
| Estimated 1RM tracking (Epley/Brzycki) | Covered | `OneRepMaxCalculator` utility; `estimatedOneRepMax` RecordType |
| Max weight PR | Covered | `maxWeight` RecordType in `PersonalRecord` |
| Max volume (single set) PR | Covered | `maxVolume` RecordType |
| Max reps at weight PR | Covered | `maxReps` RecordType |
| PR trophy/medal display | Covered | `isPersonalRecord` flag; `MuscleGroupBadge` component (could also handle PR badges) |
| Exercise detail PR history | Covered | `PersonalRecord` entity with `achievedAt`; `ExerciseDetailView` |
| Per-exercise line charts (1RM, weight, volume) | Covered | `ExerciseProgressChart` view; Swift Charts |
| Time range filters (1mo, 3mo, 6mo, 1yr, all) | Partially Covered | Implied by `ProgressViewModel`; no explicit range filter defined but straightforward to implement |
| Workout-level stats (count, avg duration, frequency, streaks) | Partially Covered | `WorkoutStats` struct covers some; streaks and frequency not explicitly modeled but derivable |
| Muscle group volume distribution | Partially Covered | `muscleGroupsWorked` computed; chart/visualization not explicitly called out |
| Body measurements (weight, body fat, circumferences) | Covered | `BodyMeasurement` entity with `MeasurementType` enum covering all 15 measurement types |
| Body measurement trend charts | Covered | `BodyWeightChart` view in Progress feature |
| Apple Health body weight sync | Covered | HealthKit reads `bodyMass`; writes `bodyMass` from manual entry |
| CSV export | Covered | `CSVImportExportService` in Services |
| CSV import (Strong, Hevy, FitNotes) | Covered | Import format defined in data model appendix C |

### 1.5 Apple Watch Features

| Feature | Status | Notes |
|---------|--------|-------|
| Start workout from templates | Covered | `WatchWorkoutListView` |
| Quick start empty workout | Covered | Listed in Watch features table |
| Log sets: weight/reps with Digital Crown | Covered | `WatchWeightInput` component; `DigitalCrownRotation` in tech stack |
| See previous/target values | Covered | Watch data subset includes recent PR data and template targets |
| Rest timer with countdown | Covered | `WatchRestTimerView` |
| Haptic feedback on set completion and timer | Covered | Watch HKWorkoutSession provides haptics |
| Pause/resume/finish workout | Covered | Watch Page 2: "Workout Controls - Pause / End / Next" |
| Scroll between exercises | Covered | Vertical TabView navigation on watchOS 10+ |
| Companion mode (real-time sync) | Covered | `sendMessage` for real-time; sync sequence diagram shows this |
| Standalone mode (works without iPhone) | Covered | Architecture explicitly states "Standalone + companion features" |
| Sync back when reconnected | Covered | `transferUserInfo` queued delivery; offline scenario in sync diagram |
| Heart rate collection | Covered | `HKWorkoutSession` auto-collects; `WatchMetricsView` for display |
| Active workout complication | Covered | `Complications/` directory in Watch app structure |
| No template creation on Watch | Covered | Correctly excluded from Watch features |
| No history/charts on Watch | Covered | Correctly excluded from Watch features |
| No exercise instructions on Watch | Covered | Correctly excluded from Watch features |
| Double-tap gesture for set logging | Partially Covered | `.handGestureShortcut` mentioned in tech stack research but not explicitly in architecture |

### 1.6 Widget and Notification Features

| Feature | Status | Notes |
|---------|--------|-------|
| Small widget (workouts this week) | Covered | `Widgets/` directory in project structure; WidgetKit in tech stack |
| Medium widget (recent workout) | Covered | Same |
| Large widget (detailed stats) | Covered | Same |
| Lock screen widget (iOS 16+) | Covered | Same |
| Live Activity during workout | Covered | `LiveActivity/` directory; ActivityKit in architecture |
| Dynamic Island rest timer | Covered | ActivityKit supports Dynamic Island |
| Rest timer expiry notification | Covered | APNs in system diagram; `RestTimerService` |
| Workout reminders (scheduled) | Not Covered | No scheduled notification service or reminder settings in architecture. Strong allows users to set workout reminder notifications for specific days/times. |
| PR celebration (in-app) | Covered | `isPersonalRecord` flag triggers display |
| Watch complications (quick launch, stats) | Covered | `Complications/` directory in Watch app |

### 1.7 Settings and Preferences Features

| Feature | Status | Notes |
|---------|--------|-------|
| Global metric/imperial toggle | Covered | `weightUnit` and `distanceUnit` in `UserSettings` |
| Per-exercise unit override | Not Covered | No per-exercise unit preference field on `Exercise` or `WorkoutExercise`. Strong allows overriding units per exercise (e.g., kg for Olympic lifts, lbs for everything else). Recommend adding `weightUnitOverride: WeightUnit?` to `Exercise` |
| Unit switching converts historical data | Partially Covered | `UnitConversionService` exists; whether it handles historical conversion needs implementation attention |
| Dark mode / system theme | Covered | `theme` field in `UserSettings` |
| Default rest timer setting | Covered | `defaultRestTimerSeconds` in `UserSettings` |
| Auto-start rest timer toggle | Covered | `autoStartRestTimer` in `UserSettings` |
| RPE visibility toggle | Covered | `showRPE` in `UserSettings` |
| Plate calculator | Not Covered | No plate calculator component or service in architecture. Strong includes a plate calculator showing plates per side for barbell exercises. This is a quality-of-life feature that could be deferred but is notable. |
| Configurable bar weight | Not Covered | Related to plate calculator; no bar weight setting |
| Configurable plate inventory | Not Covered | Related to plate calculator |

---

## 2. Data Model Completeness

### 2.1 Entity Coverage

| Required Entity | Present | Notes |
|----------------|---------|-------|
| Exercise | Yes | All needed fields present |
| Workout | Yes | `startedAt`/`completedAt` pattern is good |
| WorkoutExercise | Yes | Join entity with ordering and superset support |
| ExerciseSet | Yes | All measurement types covered |
| WorkoutTemplate | Yes | Includes folder reference and usage tracking |
| TemplateExercise | Yes | Full target fields for all exercise types |
| TemplateFolder | Yes | Simple organizational entity |
| BodyMeasurement | Yes | Covers all 15 measurement types from Strong |
| PersonalRecord | Yes | Cached PR table with set reference |
| UserSettings | Yes | Single-row settings entity |

### 2.2 Relationship Coverage

| Relationship | Status | Notes |
|-------------|--------|-------|
| Workout -> WorkoutExercise (1:N, cascade) | Covered | Correctly defined |
| WorkoutExercise -> ExerciseSet (1:N, cascade) | Covered | Correctly defined |
| Exercise -> WorkoutExercise (1:N, deny delete) | Covered | Prevents orphan history; archive instead |
| Exercise -> TemplateExercise (1:N, cascade) | Covered | Correctly defined |
| Exercise -> PersonalRecord (1:N, cascade) | Covered | Correctly defined |
| WorkoutTemplate -> TemplateExercise (1:N, cascade) | Covered | Correctly defined |
| TemplateFolder -> WorkoutTemplate (1:N, nullify) | Covered | Correctly moves to "unfiled" |
| Workout -> WorkoutTemplate (N:1, loose ref) | Covered | `templateId` as UUID, not hard FK -- good design |

### 2.3 Enum Completeness

| Enum | Status | Notes |
|------|--------|-------|
| MuscleGroup | Covered | 18 values including traps, lats, adductors, abductors. Exceeds Strong's categories. |
| ExerciseCategory | Covered | 16 equipment types. Exceeds Strong's list (adds smith machine, trap bar, EZ bar, etc.) |
| ExerciseType | Covered | 5 types covering all tracking patterns from Strong |
| SetType | Covered | 5 types. Adds `restPause` beyond Strong's 4 types |
| MeasurementType | Covered | 15 body measurement sites matching Strong |
| RecordType | Covered | 8 record types. Exceeds Strong (adds maxTotalVolume, bestPace, longestDuration, longestDistance) |
| WeightUnit | Covered | kg and lbs |
| DistanceUnit | Covered | km and miles |

### 2.4 Sync Requirements

| Requirement | Status | Notes |
|------------|--------|-------|
| UUID primary keys | Covered | All entities use `UUID` primary key |
| Soft deletes (`isDeleted`) | Covered | Present on all entities |
| `createdAt` timestamps | Covered | Present on all entities |
| `modifiedAt` timestamps | Covered | Present on all entities |
| CloudKit zone mapping | Covered | All 10 entities mapped to private database custom zone |
| Conflict resolution strategy | Covered | Last-writer-wins with field-level merge defined |
| 30-day tombstone cleanup | Covered | Defined in sync documentation |
| Batch sync for workout completion | Covered | `CKModifyRecordsOperation` grouping described |

### 2.5 Watch Data Subset Adequacy

| Watch Need | Covered | Notes |
|-----------|---------|-------|
| Exercise library (filtered) | Yes | Non-archived, non-deleted subset via `WatchExercise` |
| Templates + exercises | Yes | `WatchTemplate` and `WatchTemplateExercise` structs |
| Active workout state | Yes | `WatchActiveWorkout` with exercises and sets |
| User settings | Yes | Full settings sync via `applicationContext` |
| Recent PR data | Yes | Last 5 PRs per exercise via `userInfo` transfer |
| Estimated size < 100KB | Yes | Calculations show ~64KB total |

### 2.6 Query Pattern Coverage

| Query | Index Support | Notes |
|-------|-------------|-------|
| Workout history (newest first) | Yes | Index on `startedAt DESC` |
| Find active workout | Yes | Index on `isInProgress` |
| Exercises in a workout (ordered) | Yes | Index on `workoutId, order` |
| Sets for a workout exercise | Yes | Index on `workoutExerciseId, order` |
| Exercise search by name | Yes | Index on `name` |
| Filter by muscle group | Yes | Index on `primaryMuscleGroup` |
| Filter by equipment | Yes | Index on `category` |
| PRs for an exercise | Yes | Index on `exerciseId, recordType` |
| Body measurements over time | Yes | Index on `date DESC, measurementType` |
| Most recent weight for exercise | Yes | Derivable from `exerciseId` index on `WorkoutExercise` + `completedAt` on sets |
| Templates by folder | Partially | No explicit index on `folderId` for `WorkoutTemplate`. Recommend adding one. |
| Custom vs default exercises | Yes | Index on `isCustom` |

---

## 3. Technical Stack Validation

### 3.1 SwiftUI UI Pattern Support

| Required UI Pattern | SwiftUI Support | Risk Level |
|--------------------|----------------|------------|
| Swipe actions on set rows | `.swipeActions` modifier (iOS 15+) | Low |
| Drag-to-reorder exercises | `.onMove` modifier in `List` / `ForEach` | Low |
| Numeric keypad input | `.keyboardType(.decimalPad)` on `TextField` | Low |
| Inline editing (weight/reps in-row) | `TextField` within `List` rows | Low |
| Tab bar navigation | `TabView` with `.tabItem` | Low |
| Drill-down navigation | `NavigationStack` with `navigationDestination` (iOS 16+) | Low |
| Progress charts | Swift Charts (iOS 16+) | Low |
| Calendar view with dots | Custom SwiftUI view or `DatePicker` as base | Medium -- requires custom implementation |
| Superset visual bracket | Custom view with drawing/overlay | Medium -- no built-in component |
| Rest timer Live Activity | ActivityKit (iOS 16.1+) | Low |
| Long lists (thousands of workouts) | `LazyVStack` / `List` with batch fetching | Low |
| Color-coded completed rows | Conditional view modifiers | Low |
| Body map / muscle diagram | Custom drawn view or image overlay | Medium -- requires asset creation |
| Share as image | `ImageRenderer` (iOS 16+) | Low |

### 3.2 Core Data + CloudKit Sync Adequacy

| Requirement | Assessment |
|------------|------------|
| Automatic background sync | NSPersistentCloudKitContainer handles this |
| Offline-first operation | Core Data is local-first; CloudKit syncs when available |
| Conflict resolution | `NSMergeByPropertyObjectTrumpMergePolicy` is appropriate for append-heavy workout data |
| New device restore | CloudKit pulls full history on first launch |
| Schema migration | Core Data lightweight migration covers most cases |
| Large datasets (50K+ sets) | Core Data is proven at this scale with proper indexing and batch fetching |
| Private database only (MVP) | Correct -- shared/public databases not needed for MVP |

### 3.3 WatchConnectivity Coverage

| Sync Scenario | Method | Covered |
|--------------|--------|---------|
| Real-time set sync during workout | `sendMessage` | Yes |
| Completed workout delivery | `transferUserInfo` | Yes |
| Exercise library to Watch | `updateApplicationContext` | Yes |
| Settings to Watch | `updateApplicationContext` | Yes |
| Template list to Watch | `updateApplicationContext` | Yes |
| Full database recovery | `transferFile` | Yes |
| Complication updates | `transferCurrentComplicationUserInfo` | Yes |
| Offline fallback (sendMessage fails) | Falls back to `transferUserInfo` | Yes |
| PR notification to Watch | `sendMessage` | Yes |

### 3.4 Minimum Version Targets

| Target | Version | Justification | Assessment |
|--------|---------|---------------|------------|
| iOS | 17.0 | `@Observable` macro, modern SwiftUI | Appropriate -- ~85% adoption rate |
| watchOS | 10.0 | Vertical `TabView`, `containerBackground`, new design | Appropriate -- ~80% adoption rate |
| Xcode | 16.0+ | iOS 18 SDK, Swift 6.0 | Appropriate for 2026 development |
| Swift | 6.0 | Full concurrency checking, typed throws | Appropriate -- enables safer async code |

---

## 4. Risk Assessment

### 4.1 Features Harder to Implement Than Expected

| Feature | Risk | Details |
|---------|------|---------|
| **Calendar view with workout dots** | Medium | No built-in SwiftUI calendar component that supports custom dot annotations. Requires building a custom month grid or wrapping `UICalendarView` via `UIViewRepresentable`. |
| **Body map / muscle diagram** | Medium | Requires custom graphical assets (SVG or drawn views) with region-based highlighting. Not a stock component. |
| **Superset visual brackets** | Low-Medium | Custom drawing alongside list items. May require `GeometryReader` for alignment. |
| **Post-workout share as image** | Low | `ImageRenderer` in iOS 16+ handles this, but layout for a shareable card needs design attention. |
| **CSV import from multiple formats** | Medium | Parsing Strong, Hevy, and FitNotes formats with different column layouts requires robust parsing and exercise name matching/deduplication. |
| **Live Activity rest timer** | Low-Medium | ActivityKit API has specific lifecycle constraints; timer must handle app termination and background transitions. |

### 4.2 Sync Edge Cases

| Edge Case | Risk | Recommendation |
|-----------|------|----------------|
| **Simultaneous workout on iPhone and Watch** | High | The architecture does not explicitly address preventing two concurrent active workouts. Recommend adding a guard: only one `isInProgress == true` workout allowed system-wide. |
| **Template edited while workout in progress** | Low | Since workouts copy template data at start, edits to templates do not affect active workouts. Correctly handled by loose `templateId` reference. |
| **Exercise deleted while referenced in history** | Low | Deny delete rule prevents this. Archive instead. Correctly handled. |
| **Watch workout completed while iPhone offline for days** | Medium | `transferUserInfo` queues reliably, but large backlogs (multiple workouts) should be tested. Ensure ordering by timestamp on receipt. |
| **CloudKit quota exceeded** | Low | Free tier is generous (100MB assets, 500MB database). Workout data is small (~1.5MB/year). |
| **iCloud account change / sign-out** | Medium | `NSPersistentCloudKitContainer` handles this, but local data remains. Need to test and potentially show user a warning. |
| **First launch with large CloudKit dataset** | Medium | Importing years of data from CloudKit on first launch could be slow. Consider showing a sync progress indicator. |

### 4.3 Performance Concerns

| Concern | Risk | Mitigation |
|---------|------|------------|
| **Large workout history (5+ years)** | Low | Batch fetching (`fetchBatchSize: 20-50`), proper indexing, and Core Data faulting handle this. Defined in tech stack research. |
| **PR detection on set completion** | Medium | Full-table scan of historical sets for an exercise could be slow for frequently-performed exercises. The cached `PersonalRecord` table mitigates this -- compare against cached values, not full history. |
| **Exercise library search performance** | Low | 200-300 exercises is trivial for in-memory filtering. Index on `name` helps. |
| **Swift Charts with large datasets** | Low-Medium | Charts with thousands of data points may need downsampling. Use aggregated data (weekly/monthly) for long time ranges. |
| **Workout summary volume calculation** | Low | Computed at workout completion, not real-time. Minimal impact. |

### 4.4 Watch Memory and Storage Constraints

| Concern | Assessment |
|---------|------------|
| Watch app memory limit (~30MB) | Lightweight Codable models (not Core Data on Watch) keep memory low. Exercise library is ~40KB. Active workout data ~8KB. Well within limits. |
| Watch storage | Total Watch data < 100KB. No concern. |
| Long workout sessions (2+ hours) | `HKWorkoutSession` keeps app alive. Memory should not grow significantly since sets are sent to iPhone in real-time and not accumulated. |
| Watch app launch time | No Core Data stack initialization on Watch. Codable deserialization of small payloads is fast. |

### 4.5 HealthKit Permission Edge Cases

| Edge Case | Recommendation |
|-----------|----------------|
| User denies all HealthKit permissions | App must function fully without HealthKit. Architecture correctly notes this. Ensure no crash paths when HealthKit returns empty results. |
| User denies write but allows read | Workout recording to HealthKit silently fails; app's local data is unaffected. |
| Cannot determine if read permission denied | By design, `HKHealthStore` returns empty results. Show "no data" states gracefully. |
| HealthKit not available (iPod touch, iPad) | Guard with `HKHealthStore.isHealthDataAvailable()`. iPad does not support HealthKit -- if iPad is a future target, this needs handling. |
| Watch heart rate permission denied | Heart rate display shows "--" or similar. Workout session still records duration/calories. |

---

## 5. MVP Scope Validation

### 5.1 Implied MVP Scope (from Architecture Phase Breakdown)

Based on the development phases in `docs/research/technical-stack.md`:

- **Phase 1 (Weeks 1-3):** Project setup, Core Data model, exercise library, MVVM structure
- **Phase 2 (Weeks 4-6):** Active workout logging, rest timer with Live Activity, history, HealthKit
- **Phase 3 (Weeks 7-9):** Watch app, HKWorkoutSession, Digital Crown input, WatchConnectivity
- **Phase 4 (Weeks 10-12):** CloudKit sync, charts, templates, settings, widget

### 5.2 MVP Achievability Assessment

| Phase | Assessment | Risk |
|-------|------------|------|
| Phase 1 | Achievable | Low -- standard project scaffolding and data modeling |
| Phase 2 | Achievable with tight scope | Medium -- Live Activity adds complexity; consider deferring to Phase 4 |
| Phase 3 | Most complex phase | Medium-High -- Watch development requires real hardware testing; WatchConnectivity sync has subtle edge cases |
| Phase 4 | Achievable if CloudKit sync is straightforward | Medium -- CloudKit debugging is notoriously difficult; allocate extra buffer |

**Overall: 12 weeks is tight but achievable for an experienced iOS developer.** The biggest risk is Watch + sync (Phase 3). Consider 14-16 weeks as a more realistic estimate if including polish and testing.

### 5.3 Feature Prioritization Assessment

| Feature | MVP Priority | Current Plan | Assessment |
|---------|-------------|-------------|------------|
| Core workout logging | Critical | Phase 2 | Correct |
| Exercise library | Critical | Phase 1 | Correct |
| Set types (normal, warmup, drop, failure) | High | Phase 2 | Correct |
| Rest timer | High | Phase 2 | Correct |
| Workout history | High | Phase 2 | Correct |
| Templates | High | Phase 4 | Consider moving to Phase 2 -- templates are central to Strong's UX |
| Watch app | High | Phase 3 | Correct |
| CloudKit sync | High | Phase 4 | Correct |
| PR detection | Medium | Not explicitly phased | Should be in Phase 2 with workout logging |
| Charts/progress | Medium | Phase 4 | Correct |
| Body measurements | Medium | Not explicitly phased | Can be Phase 4 or post-MVP |
| Live Activity | Medium | Phase 2 | Consider deferring to Phase 4 to reduce Phase 2 scope |
| Widgets | Low for MVP | Phase 4 | Correct |
| CSV import/export | Low for MVP | Not phased | Post-MVP or Phase 4 |
| Supersets | Deferred | Phase 2 in competitor matrix | Correctly deferred in architecture |
| Plate calculator | Low | Not planned | Acceptable deferral |
| Workout reminders | Low | Not planned | Acceptable deferral |
| Sharing | Low | Not planned | Acceptable deferral |

### 5.4 Critical Features Missing from Explicit MVP Plan

1. **Templates should be earlier.** The architecture correctly has `WorkoutListView` as "Templates + Quick Start" but templates are Phase 4. Since the home screen is template-centric (matching Strong's UX), templates should be Phase 2 or Phase 3.

2. **PR detection is not explicitly phased.** PR badges during workout logging are a key motivational feature in Strong. Should be Phase 2.

3. **Previous performance display** is not explicitly called out as a milestone, yet it is described in research as a "key UX feature." The data model and queries support it, but ensure it is prioritized in the active workout view implementation.

### 5.5 Deferred Feature List Assessment

The following features are correctly deferred for post-MVP:

| Deferred Feature | Reason | Assessment |
|-----------------|--------|------------|
| Supersets | Adds complexity to logging UI | Reasonable -- data model already supports it |
| Plate calculator | Nice-to-have utility | Reasonable |
| Workout reminders / notifications | Non-core | Reasonable |
| Social/sharing | Out of scope for MVP | Correct |
| Auto-progression / programs | Strong does not have this either | Correct |
| Coach mode | Not in scope | Correct |
| iPad optimization | Different layout considerations | Reasonable |
| Exercise images/illustrations | Asset-heavy; not required per project scope | Correct |

---

## 6. Recommendations

### 6.1 Missing Architectural Components

| Component | Priority | Recommendation |
|-----------|----------|----------------|
| **Workout share service** | Medium | Add a service/component for generating shareable workout summary images. Strong's share feature is popular. |
| **Scheduled notification service** | Low | Add a workout reminder notification scheduler for post-MVP. |
| **Concurrent workout guard** | High | Add architectural constraint ensuring only one active workout across iPhone and Watch. |
| **Sync progress indicator** | Medium | Add UI for CloudKit initial sync and ongoing sync status. |
| **Data backup / restore service** | Medium | Beyond CloudKit, consider local backup export (JSON) for user peace of mind. |

### 6.2 Additional Data Model Fields Needed

| Entity | Field | Type | Reason |
|--------|-------|------|--------|
| `Exercise` | `isFavorite` | `Bool` | Strong's favorites filter for quick exercise access |
| `Exercise` | `lastUsedAt` | `Date?` | Efficient "recently used" exercise queries without joining WorkoutExercise |
| `Exercise` | `weightUnitOverride` | `WeightUnit?` | Per-exercise unit override (e.g., kg for Olympic lifts) |
| `Workout` | `healthKitWorkoutId` | `UUID?` | Already in tech stack's data model but absent from data-model.md. Links to HKWorkout for cross-referencing. |
| `UserSettings` | `barWeight` | `Double?` | For future plate calculator feature |
| `WorkoutTemplate` | `colorTag` | `String?` | Visual differentiation of templates on home screen |

### 6.3 Sync Edge Cases to Handle

1. **Concurrent active workout prevention:** When a workout is started on Watch, send a message to iPhone to prevent starting another. If iPhone is unreachable, the Watch workout takes precedence on sync.

2. **Workout started on one device, finished on another:** The architecture supports this via `sendMessage` sync, but explicitly test and document the handoff flow.

3. **Large CSV import during active sync:** Ensure background import does not conflict with CloudKit sync operations. Use separate managed object contexts.

4. **Watch app installed without iPhone app:** Since Watch is standalone, it must handle the case where no exercise library has been synced yet. Bundle a minimal exercise set directly in the Watch app target.

5. **CloudKit account change:** Detect `CKAccountStatus` changes and handle migration (keep local data, re-sync to new account).

### 6.4 Testing Strategy Priorities

| Priority | Test Area | Approach |
|----------|-----------|----------|
| **1 (Critical)** | Core Data CRUD operations | Unit tests with in-memory store |
| **2 (Critical)** | Workout logging flow (start -> log sets -> complete) | Integration test with in-memory Core Data |
| **3 (Critical)** | PR detection accuracy | Unit tests with known historical data |
| **4 (High)** | WatchConnectivity message handling | Unit tests with mock WCSession |
| **5 (High)** | Offline workout sync (queued delivery) | Integration test simulating offline/online transitions |
| **6 (High)** | 1RM calculation correctness | Unit tests for all formulas at edge cases |
| **7 (Medium)** | CSV import parsing (all 3 formats) | Unit tests with sample CSV files |
| **8 (Medium)** | CloudKit conflict resolution | Integration tests (difficult; may require staging environment) |
| **9 (Medium)** | HealthKit permission edge cases | UI tests with mock HealthKit |
| **10 (Low)** | View snapshot tests for key screens | Snapshot tests with Point-Free library |

---

## 7. Summary

### Overall Assessment: STRONG

The architecture is thorough and well-aligned with the research findings. The data model covers the vast majority of features identified in Strong's feature analysis. The technical stack choices (SwiftUI, Core Data + CloudKit, WatchConnectivity, HealthKit) are appropriate and well-justified.

### Key Strengths
- Comprehensive data model with proper sync support (UUIDs, soft deletes, timestamps)
- Clean layered architecture with protocol-based DI
- Watch app correctly scoped (standalone with companion features)
- Sensible technology choices with zero third-party dependencies
- Proper HealthKit integration architecture

### Items Requiring Attention
1. **Add `isFavorite` to Exercise entity** -- missing a commonly-used Strong feature
2. **Add `healthKitWorkoutId` to Workout entity** -- present in tech stack but missing from data model
3. **Add concurrent workout guard** -- critical sync edge case not addressed
4. **Move templates to Phase 2/3** -- they are central to the home screen UX
5. **Explicitly phase PR detection** -- should be Phase 2
6. **Add workout share capability** -- popular Strong feature not in architecture
7. **Add per-exercise unit override** -- a Strong feature users rely on
8. **Bundle minimal exercise data in Watch app** -- for standalone-first-launch scenario
