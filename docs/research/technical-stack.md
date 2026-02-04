# Technical Stack Research: Strength Tracker for iOS & Apple Watch

**Date:** January 2026
**Scope:** Full-stack technical recommendations for a Strong-like workout tracker
**Minimum Targets:** iOS 17.0+ / watchOS 10.0+ / Xcode 16+

---

## Table of Contents

1. [SwiftUI vs UIKit for iOS](#1-swiftui-vs-uikit-for-ios)
2. [WatchOS App Architecture](#2-watchos-app-architecture)
3. [Data Sync Between iPhone and Watch](#3-data-sync-between-iphone-and-watch)
4. [HealthKit Integration](#4-healthkit-integration)
5. [Core Data vs SwiftData for Local Storage](#5-core-data-vs-swiftdata-for-local-storage)
6. [CloudKit for Cross-Device Sync](#6-cloudkit-for-cross-device-sync)
7. [Recommended Architecture](#7-recommended-architecture)
8. [Final Recommendation Summary](#8-final-recommendation-summary)

---

## 1. SwiftUI vs UIKit for iOS

### Current State of SwiftUI (2024-2025)

SwiftUI has matured significantly since its introduction in iOS 13. As of iOS 17 and iOS 18, SwiftUI is production-ready for the vast majority of app categories, including fitness apps. Key milestones:

- **iOS 17 (2023):** `Observable` macro replacing `ObservableObject`, new `@Bindable`, improved animations, `ScrollView` improvements, `contentMargins`, interactive widgets.
- **iOS 18 (2024):** Mesh gradients, improved `TabView` with sidebar adaptivity, zoom navigation transitions, custom containers with `ForEach(subviewOf:)`, SF Symbol animations v2, and enhanced Charts framework.
- **watchOS 10 (2023):** Complete SwiftUI redesign for Watch apps; NavigationSplitView on Watch, new `TabView` vertical paging, `DigitalCrownRotation`.
- **watchOS 11 (2024):** Live Activities on Watch, improved workout APIs, double-tap gesture support.

SwiftUI is now Apple's stated primary UI framework. All new Apple platform features ship SwiftUI-first, and UIKit receives maintenance updates. Apple's own apps (Fitness, Health, Journal) are built with SwiftUI.

### What Strong and Similar Apps Use

- **Strong:** Originally built with UIKit (pre-SwiftUI era). The iOS app shows UIKit patterns (UITableView-based exercise lists, UIKit navigation controllers). The Watch app was added later. Strong has not publicly confirmed a SwiftUI rewrite, but newer features show SwiftUI integration.
- **Hevy:** Newer competitor that uses SwiftUI more extensively, especially for the Watch app.
- **JEFIT:** UIKit-based legacy app.
- **Fitbod:** Hybrid approach -- UIKit foundation with SwiftUI for newer screens.
- **Apple Fitness:** Full SwiftUI.

### Recommendation: SwiftUI

**For a new project starting in 2026, SwiftUI is the clear choice.** The only reason to choose UIKit would be if you were maintaining an existing UIKit codebase.

#### Pros of SwiftUI for a Workout Tracker

| Advantage | Details |
|-----------|---------|
| **Shared codebase with watchOS** | SwiftUI is the only option for watchOS 10+. Using SwiftUI on iOS means view components, view models, and data models can be shared across iPhone and Watch targets. |
| **Declarative UI** | Workout UIs (exercise lists, set rows, rest timers) map naturally to declarative lists and state-driven views. |
| **Less boilerplate** | No storyboards, no autolayout constraints, no delegate patterns for tables. A workout log screen that would be 300+ lines in UIKit is roughly 80 lines in SwiftUI. |
| **Built-in animations** | `.animation()`, `withAnimation {}`, `matchedGeometryEffect` for smooth transitions between exercises. Phase and keyframe animations in iOS 17+. |
| **Native Charts** | Swift Charts framework (iOS 16+) integrates directly for workout analytics, progress graphs, volume charts. |
| **Widget support** | WidgetKit is SwiftUI-only. Workout summary widgets, rest timer Live Activities. |
| **Live Activities** | For rest timer countdown on lock screen -- SwiftUI only (ActivityKit). |
| **Future-proof** | Apple invests in SwiftUI. UIKit is in maintenance mode. |

#### Cons and Considerations

| Concern | Mitigation |
|---------|------------|
| **Complex list interactions** | Swipe actions, drag-to-reorder, multi-selection are all supported as of iOS 16+. `onMove`, `swipeActions`, `editMode` cover workout tracker needs. |
| **Custom text input** | For weight/rep entry, `TextField` with `.keyboardType(.decimalPad)` works. For truly custom numeric pads, a SwiftUI overlay is straightforward. |
| **Navigation complexity** | `NavigationStack` with `navigationDestination(for:)` (iOS 16+) handles programmatic navigation well. For tab + drill-down patterns in a workout app, this is sufficient. |
| **Performance with very long lists** | `LazyVStack` inside `ScrollView` or `List` handles workout histories with thousands of entries. For extreme cases, `UIViewRepresentable` wrapping `UICollectionView` with diffable data source is available as an escape hatch. |
| **Third-party library support** | Most popular Swift libraries now support SwiftUI natively. |

#### UIKit Interop

SwiftUI provides `UIViewRepresentable` and `UIViewControllerRepresentable` for any edge cases. This means you are never blocked by SwiftUI limitations -- you can drop down to UIKit for specific screens if needed. In practice, a workout tracker is unlikely to need this.

---

## 2. WatchOS App Architecture

### Standalone vs Companion App

**Recommendation: Standalone Watch app with iPhone companion.**

Starting with watchOS 6, Apple supports fully independent Watch apps. With watchOS 10+, the standalone model is strongly preferred:

| Approach | Description | Recommendation |
|----------|-------------|----------------|
| **Standalone** | Watch app works independently. Does not require iPhone app to be installed. Has its own App Store listing. | **Recommended.** Users can start workouts from Watch without iPhone. Essential for gym use. |
| **Dependent companion** | Watch app requires iPhone app. Legacy pattern. | **Avoid.** Apple is phasing this out. |
| **Standalone + companion features** | Watch app is standalone but gains extra features when iPhone app is present (e.g., browsing exercise library, detailed analytics). | **Best of both worlds. This is the target architecture.** |

In Xcode, create a "watchOS App" target (not "WatchKit App" which is deprecated). The Watch app is a standalone SwiftUI `App` with its own `@main` entry point.

### watchOS 10+ Capabilities and UI Patterns

watchOS 10 introduced a major design overhaul.

#### Navigation Patterns

```
TabView (vertical paging) -- PRIMARY navigation
  |-- Page 1: Active Workout / Current Exercise
  |-- Page 2: Workout Controls (pause, end, next exercise)
  |-- Page 3: Heart Rate / Metrics
  |-- Page 4: Workout Summary (if completed)

NavigationStack -- SECONDARY (drill-down within a page)
  |-- Exercise list -> Exercise detail -> Set entry

.sheet / .fullScreenCover -- for modals (rest timer, exercise picker)
```

Key watchOS 10+ UI elements for a workout tracker:

| Element | Usage |
|---------|-------|
| **Vertical `TabView`** | Primary navigation between workout screens. Replaces side-swipe pages. |
| **`NavigationStack`** | Drill-down from exercise list to set entry. |
| **`.containerBackground()`** | Full-screen gradient backgrounds per page (watchOS 10+). |
| **`DigitalCrownRotation`** | Scroll through weight values or rep counts using the Digital Crown. |
| **`.toolbar` with `.bottomBar`** | Bottom action buttons (log set, next exercise). |
| **`DatePicker`, `Stepper`** | For weight/rep input on Watch. Stepper maps well to Digital Crown. |
| **Large titles** | watchOS 10 design language uses prominent titles at top of each view. |
| **`.handGestureShortcut(.primaryAction)`** | Double-tap gesture (watchOS 10.1+ / Apple Watch Ultra, Series 9+) to log a set hands-free. |

#### Watch App Lifecycle and Background Execution

For a workout tracker, background execution is critical:

```swift
// HKWorkoutSession keeps the app alive in the background
let configuration = HKWorkoutConfiguration()
configuration.activityType = .traditionalStrengthTraining
configuration.locationType = .indoor

let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
let builder = session.associatedWorkoutBuilder()

session.startActivity(with: Date())
builder.beginCollection(withStart: Date())
```

**Key lifecycle facts:**

- **Active workout session:** When an `HKWorkoutSession` is running, the Watch app remains active in the background. The green workout indicator appears at the top of the watch face. This is essential.
- **Extended runtime sessions:** `WKExtendedRuntimeSession` provides up to 30 minutes of background execution for non-workout scenarios (e.g., rest timer alerts). However, `HKWorkoutSession` is preferred for workout tracking.
- **Always-on display:** With `TimelineView(.everyMinute)` or a `LiveActivity`, the always-on display shows workout status even when the wrist is lowered.
- **Background app refresh:** `WKApplicationRefreshBackgroundTask` for periodic data sync. Limited to roughly 15 minutes of background time.
- **Complications:** Update via `CLKComplicationServer` or WidgetKit (watchOS 10+) to show last workout, streak, etc.

### Recommended Watch App Structure

```
WatchApp/
  StrengthTrackerWatchApp.swift       // @main entry point
  Views/
    WorkoutListView.swift              // Start new / resume workout
    ActiveWorkoutView.swift            // TabView with pages
    ExerciseSetEntryView.swift         // Weight + reps input
    RestTimerView.swift                // Countdown timer
    WorkoutSummaryView.swift           // Post-workout summary
  ViewModels/
    WorkoutSessionManager.swift        // HKWorkoutSession lifecycle
    WatchSyncManager.swift             // WatchConnectivity
  Models/
    (Shared with iOS target)
```

---

## 3. Data Sync Between iPhone and Watch

### WatchConnectivity Framework

`WCSession` is the primary mechanism for iPhone <-> Watch communication. It provides several transfer methods, each suited to different data types:

| Method | Delivery | Size Limit | Use Case |
|--------|----------|------------|----------|
| `sendMessage(_:replyHandler:)` | **Real-time** (both apps must be reachable) | ~64KB practical | Send a completed set to iPhone for immediate UI update |
| `updateApplicationContext(_:)` | **Latest-only** (overwrites previous) | ~64KB practical | Current workout state, user preferences, exercise library version |
| `transferUserInfo(_:)` | **Queued FIFO** (guaranteed delivery) | ~64KB per transfer | Completed workout data, exercise history |
| `transferFile(_:metadata:)` | **Background file transfer** | Up to ~100MB | Large exercise library database, workout export files |
| `transferCurrentComplicationUserInfo(_:)` | **High priority** (limited to 50/day) | Small | Update complication with latest workout data |

### Recommended Sync Strategy

```
[Watch] ---(workout in progress)---> sendMessage() ---> [iPhone]
   |                                                        |
   |  (workout completed)                                   |
   +---(transferUserInfo)---> queued delivery -----------> [iPhone]
   |                                                        |
   |  (exercise library updated on iPhone)                  |
   +<--(updateApplicationContext)--- latest library ----< [iPhone]
   |                                                        |
   |  (full database sync needed)                           |
   +<--(transferFile)--- database snapshot -------------< [iPhone]
```

### Implementation Pattern

```swift
// Shared WatchConnectivity manager
class ConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = ConnectivityManager()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // Send completed set in real-time
    func sendCompletedSet(_ set: WorkoutSet) {
        guard WCSession.default.isReachable else {
            // Fall back to transferUserInfo for guaranteed delivery
            let data = try? JSONEncoder().encode(set)
            WCSession.default.transferUserInfo(["completedSet": data as Any])
            return
        }
        let data = try? JSONEncoder().encode(set)
        WCSession.default.sendMessage(
            ["completedSet": data as Any],
            replyHandler: nil
        )
    }

    // Send exercise library to Watch
    func syncExerciseLibrary(_ library: ExerciseLibrary) {
        let data = try? JSONEncoder().encode(library)
        try? WCSession.default.updateApplicationContext(
            ["exerciseLibrary": data as Any]
        )
    }
}
```

### Shared App Groups and UserDefaults

For data that both the iOS app and its extensions need access to on the same device, use App Groups:

```swift
// In both iOS app and widget/intent extension targets, add the same App Group:
// group.com.yourcompany.strengthtracker

let sharedDefaults = UserDefaults(suiteName: "group.com.yourcompany.strengthtracker")
sharedDefaults?.set(true, forKey: "hasActiveWorkout")
```

**Important:** App Groups work between an iOS app and its extensions (widgets, intents) on the same device. They do NOT work between iPhone and Apple Watch -- those are separate devices requiring WatchConnectivity or CloudKit.

### Handling Offline Scenarios

The workout tracker must work fully offline on both devices:

1. **Watch starts workout without iPhone nearby:** All workout data stored locally on Watch using Core Data. Synced to iPhone when connectivity resumes via `transferUserInfo`.
2. **iPhone has no network:** Workouts stored locally. CloudKit sync happens when network returns (handled automatically by NSPersistentCloudKitContainer).
3. **Both devices offline:** Each stores data locally. When they reconnect, WatchConnectivity delivers queued transfers. CloudKit eventually syncs everything.
4. **Conflict resolution:** Workout data is append-only (new workouts, new sets). Conflicts are rare. For exercise library edits, use last-writer-wins with timestamps. CloudKit handles merge conflicts for the cloud layer.

---

## 4. HealthKit Integration

### Workout Types and Metadata

HealthKit is essential for a strength training app. It provides the workout recording infrastructure and integrates with Apple's Fitness app and rings.

#### Key Workout Type

```swift
// Primary workout type for strength training
HKWorkoutActivityType.traditionalStrengthTraining  // .code = 13

// Also relevant:
HKWorkoutActivityType.functionalStrengthTraining   // .code = 20
HKWorkoutActivityType.highIntensityIntervalTraining // .code = 63
HKWorkoutActivityType.coreTraining                  // .code = 74
```

#### Recording a Workout with HKWorkoutBuilder (iOS 17+ / watchOS 10+)

```swift
let healthStore = HKHealthStore()

// 1. Configure workout
let config = HKWorkoutConfiguration()
config.activityType = .traditionalStrengthTraining
config.locationType = .indoor

// 2. Create session (Watch) or builder (iPhone)
// On Watch:
let session = try HKWorkoutSession(
    healthStore: healthStore,
    configuration: config
)
let builder = session.associatedWorkoutBuilder()

// On iPhone (no HKWorkoutSession, use builder directly):
let builder = HKWorkoutBuilder(
    healthStore: healthStore,
    configuration: config,
    device: .local()
)

// 3. Start
builder.beginCollection(withStart: startDate) { success, error in }

// 4. Add workout events (rest periods, segments)
let pauseEvent = HKWorkoutEvent(
    type: .pause,
    dateInterval: DateInterval(start: restStart, duration: 0),
    metadata: nil
)
builder.addWorkoutEvents([pauseEvent]) { success, error in }

// 5. End and save
builder.endCollection(withEnd: endDate) { success, error in
    builder.finishWorkout { workout, error in
        // workout is now saved to HealthKit
    }
}
```

#### Workout Metadata

```swift
// Standard HealthKit metadata keys
HKMetadataKeyIndoorWorkout: true
HKMetadataKeyWorkoutBrandName: "StrengthTracker"
```

**Critical design point:** HealthKit stores workout-level summaries (total duration, total calories, total distance). It does NOT store exercise-by-exercise set/rep/weight data. Your app's local database (Core Data) is the source of truth for detailed workout data. HealthKit is for:
- Contributing to Activity Rings (Move/Exercise/Stand)
- Sharing workout summaries with other health apps
- Reading heart rate data during workouts
- Reading/writing body measurements (weight, body fat %)

### Heart Rate Monitoring from Watch

```swift
// On Watch, during an active HKWorkoutSession:
let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

let query = HKAnchoredObjectQuery(
    type: heartRateType,
    predicate: HKQuery.predicateForSamples(withStart: workoutStartDate, end: nil),
    anchor: nil,
    limit: HKObjectQueryNoLimit
) { query, samples, deletedObjects, anchor, error in
    // Process heart rate samples
}

query.updateHandler = { query, samples, deletedObjects, anchor, error in
    guard let samples = samples as? [HKQuantitySample] else { return }
    for sample in samples {
        let bpm = sample.quantity.doubleValue(
            for: HKUnit.count().unitDivided(by: .minute())
        )
        // Update UI with current heart rate
    }
}

healthStore.execute(query)
```

Heart rate is sampled automatically during an active `HKWorkoutSession`. No additional sensor configuration is needed.

### Calories and Active Energy

```swift
// Active energy burned during workout (auto-collected during HKWorkoutSession)
let activeEnergyType = HKQuantityType.quantityType(
    forIdentifier: .activeEnergyBurned
)!

// After workout ends, the HKWorkout object contains:
let totalCalories = workout.totalEnergyBurned  // HKQuantity in kilocalories

// For real-time calorie updates during workout, use HKLiveWorkoutBuilder (Watch):
builder.dataSource = HKLiveWorkoutDataSource(
    healthStore: healthStore,
    workoutConfiguration: config
)
// This auto-collects heart rate, active energy, and basal energy
```

### Privacy and Permissions

```swift
// Request authorization
let typesToShare: Set<HKSampleType> = [
    HKObjectType.workoutType(),
    HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
    HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
]

let typesToRead: Set<HKObjectType> = [
    HKObjectType.workoutType(),
    HKQuantityType.quantityType(forIdentifier: .heartRate)!,
    HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
    HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
    HKObjectType.activitySummaryType(),
]

healthStore.requestAuthorization(
    toShare: typesToShare,
    read: typesToRead
) { success, error in }
```

**Important privacy notes:**
- HealthKit authorization is per-type. Users can deny individual data types.
- You cannot check if a user denied read access (privacy by design). Queries simply return no results.
- Add `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` to Info.plist.
- HealthKit data is encrypted at rest and excluded from iCloud backup.
- For App Store review: clearly explain why each HealthKit data type is needed.

---

## 5. Core Data vs SwiftData for Local Storage

### SwiftData Overview (iOS 17+ / watchOS 10+)

SwiftData, introduced at WWDC 2023, is Apple's modern persistence framework built on top of Core Data. It uses Swift macros (`@Model`) instead of `.xcdatamodeld` files.

#### SwiftData Maturity Assessment (as of early 2025)

| Aspect | Status | Notes |
|--------|--------|-------|
| **Basic CRUD** | Stable | Insert, fetch, update, delete work reliably |
| **Relationships** | Stable | One-to-many, many-to-many. Cascade delete rules supported. |
| **Predicates** | Stable | `#Predicate` macro with type-safe filtering |
| **Sorting** | Stable | `SortDescriptor` with key paths |
| **SwiftUI integration** | Excellent | `@Query` property wrapper, `@Environment(\.modelContext)` |
| **Background contexts** | Improved in iOS 18 | `ModelActor` for background operations. Was buggy in iOS 17.0-17.2. |
| **CloudKit sync** | Partially supported | Basic sync works. Less control than NSPersistentCloudKitContainer. Improved in iOS 18. |
| **Migration** | Basic | Lightweight migration is automatic. Complex migrations require `SchemaMigrationPlan`. Less flexible than Core Data mapping models. |
| **watchOS support** | Supported | Works on watchOS 10+. Same API as iOS. |
| **Performance** | Good | Comparable to Core Data for most operations. |
| **Unique constraints** | iOS 17+ | `#Unique` macro for uniqueness constraints |
| **Index** | iOS 17+ | `#Index` macro for query optimization |
| **History tracking** | iOS 18+ | `PersistentHistoryTransaction` equivalent added |
| **Composite predicates** | iOS 18+ | Complex predicate composition improved |

#### Known SwiftData Limitations (as of iOS 18.x)

1. **CloudKit sync is less mature** than Core Data + CloudKit. No public/shared database support. No subscription notifications. No fine-grained conflict resolution.
2. **Background operations** were unreliable in iOS 17.0-17.2. The `ModelActor` API improved this in iOS 17.4+ and iOS 18, but Core Data's `performBackgroundTask` is still more battle-tested.
3. **Complex migrations** are harder. No visual mapping model editor. `SchemaMigrationPlan` requires manual code for non-trivial schema changes.
4. **No `NSFetchedResultsController` equivalent.** SwiftUI's `@Query` is the intended replacement, but for UIKit interop or complex observation patterns, Core Data still has an edge.
5. **Thread safety** requires care. `@Model` objects are not Sendable. Must use `ModelActor` for cross-thread access.

### Core Data Overview

Core Data is battle-tested (15+ years) and remains fully supported. Key advantages for this project:

| Advantage | Details |
|-----------|---------|
| **NSPersistentCloudKitContainer** | Mature, reliable CloudKit sync with automatic conflict resolution. Supports private and shared databases. |
| **Background contexts** | `performBackgroundTask` is robust and well-understood. |
| **Complex migrations** | Mapping models, custom migration policies, progressive migration. |
| **NSFetchedResultsController** | Efficient, batched data loading for large lists (though less relevant in pure SwiftUI). |
| **Proven at scale** | Used by apps with millions of records. Well-understood performance characteristics. |
| **Community knowledge** | Extensive documentation, Stack Overflow answers, tutorials. |

### Recommendation: Core Data with NSPersistentCloudKitContainer

**For this project, Core Data is the safer and more capable choice.** The primary reasons:

1. **CloudKit sync maturity:** `NSPersistentCloudKitContainer` with Core Data is production-proven for cross-device sync. SwiftData's CloudKit story is still catching up.
2. **Workout data can grow large:** Users with years of workout history may have tens of thousands of sets. Core Data's performance characteristics are well-understood at this scale.
3. **Complex relationships:** Workout -> ExerciseGroup -> Set is a 3-level hierarchy. Core Data handles this with explicit relationship management and cascade rules.
4. **Migration confidence:** As the data model evolves (adding new exercise types, tracking features), Core Data's migration tooling is more reliable.

**However, use SwiftUI's observation patterns on top of Core Data:**

```swift
// Use @FetchRequest in SwiftUI views
@FetchRequest(
    sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
    animation: .default
)
private var workouts: FetchedResults<CDWorkout>

// Or wrap Core Data objects in Observable view models
@Observable
class WorkoutDetailViewModel {
    var workout: CDWorkout
    var sets: [CDWorkoutSet] {
        workout.sets?.allObjects as? [CDWorkoutSet] ?? []
    }
}
```

### Data Model for Workout Tracking

```
CDExercise (Exercise Library)
  - id: UUID
  - name: String
  - category: String (chest, back, legs, shoulders, arms, core, cardio)
  - equipment: String (barbell, dumbbell, machine, cable, bodyweight)
  - isCustom: Bool
  - muscleGroups: [String] (primary, secondary)

CDWorkout
  - id: UUID
  - name: String (e.g., "Push Day", "Leg Day")
  - date: Date
  - duration: TimeInterval
  - notes: String?
  - isCompleted: Bool
  - healthKitWorkoutID: UUID?  // Link to HKWorkout
  --> exerciseGroups: [CDExerciseGroup] (ordered, one-to-many)

CDExerciseGroup (an exercise within a workout)
  - id: UUID
  - order: Int16
  - restTimerSeconds: Int16
  - notes: String?
  --> exercise: CDExercise (many-to-one)
  --> workout: CDWorkout (many-to-one)
  --> sets: [CDWorkoutSet] (ordered, one-to-many)

CDWorkoutSet
  - id: UUID
  - order: Int16
  - weight: Double (in user's preferred unit)
  - reps: Int16
  - duration: TimeInterval? (for timed exercises)
  - distance: Double? (for cardio)
  - isCompleted: Bool
  - isWarmup: Bool
  - isDropSet: Bool
  - isFailure: Bool
  - rpe: Double? (Rate of Perceived Exertion, 1-10)
  - timestamp: Date? (when the set was completed)
  --> exerciseGroup: CDExerciseGroup (many-to-one)

CDWorkoutTemplate
  - id: UUID
  - name: String
  - exerciseOrder: [UUID] (exercise IDs in order)
  - lastUsed: Date?
  --> exercises: [CDExercise] (many-to-many)

CDBodyMeasurement
  - id: UUID
  - date: Date
  - bodyWeight: Double?
  - bodyFatPercentage: Double?
  - unit: String
```

### Performance Considerations

For large workout histories (5+ years of data, 50,000+ sets):

1. **Batch fetching:** Use `fetchBatchSize` on fetch requests (default 0 fetches all). Set to 20-50 for list views.
2. **Faulting:** Core Data's faulting mechanism loads related objects on demand. Do not access `.sets` on all workouts in a list view.
3. **Prefetching:** Use `relationshipKeyPathsForPrefetching` for detail views that need related objects.
4. **Background imports:** When syncing large datasets from Watch, use `performBackgroundTask` to avoid blocking the main thread.
5. **Indexing:** Add indexes on frequently queried attributes: `date`, `exerciseID`, `isCompleted`.

---

## 6. CloudKit for Cross-Device Sync

### Why CloudKit

CloudKit is the natural choice for Apple-platform apps:
- Free tier is generous (100MB asset storage, 500MB database, 2GB transfer per user)
- No server to maintain
- Built into iOS/macOS/watchOS
- Handles authentication via iCloud account (no signup flow needed)
- Automatic conflict resolution with Core Data integration

### NSPersistentCloudKitContainer

This is the recommended approach -- it wraps Core Data with automatic CloudKit sync:

```swift
class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    init() {
        container = NSPersistentCloudKitContainer(name: "StrengthTracker")

        // Configure for CloudKit sync
        guard let description = container.persistentStoreDescriptions.first
        else { return }

        description.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.yourcompany.strengthtracker"
            )

        // Enable remote change notifications
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        // Enable history tracking (required for CloudKit sync)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey
        )

        container.loadPersistentStores { description, error in
            if let error {
                fatalError("Core Data store failed: \(error)")
            }
        }

        // Auto-merge remote changes
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy =
            NSMergeByPropertyObjectTrumpMergePolicy
    }
}
```

### Private vs Shared Databases

| Database | Use Case | Recommendation |
|----------|----------|----------------|
| **Private** | User's own workout data, exercise library, templates | **Primary store.** All workout data lives here. Automatically synced across user's devices. |
| **Shared** | Sharing workout templates with friends, coach-athlete relationships | **Future feature.** Not needed for MVP. CloudKit sharing zones enable this later. |
| **Public** | Global exercise library, community templates | **Optional.** Could host a curated exercise database. Read-only for most users. |

For the initial version, use only the **private database**. This is the default for `NSPersistentCloudKitContainer`.

### Conflict Resolution

`NSPersistentCloudKitContainer` handles conflicts automatically:

- **Default policy:** `NSMergeByPropertyObjectTrumpMergePolicy` -- in-memory changes win over stored changes. This is correct for workout data where the latest edit should win.
- **Workout data is largely append-only:** New workouts, new sets. Conflicts are rare.
- **Exercise library edits:** If a user renames an exercise on iPhone and Watch simultaneously (unlikely), last-write-wins is acceptable.
- **For true conflict scenarios:** You can observe `NSPersistentStoreRemoteChange` notifications and implement custom resolution logic.

### Offline Support

CloudKit sync is inherently offline-capable:

1. All data is stored locally in Core Data first.
2. Changes are queued and synced when network is available.
3. `NSPersistentCloudKitContainer` manages the sync queue automatically.
4. No user action needed -- sync happens transparently.
5. First launch on a new device pulls all data from CloudKit.

### Sync Timing and Notifications

```swift
// Observe remote changes
NotificationCenter.default.addObserver(
    self,
    selector: #selector(remoteStoreChanged),
    name: .NSPersistentStoreRemoteChange,
    object: container.persistentStoreCoordinator
)

@objc func remoteStoreChanged(_ notification: Notification) {
    // Refresh UI -- viewContext.automaticallyMergesChangesFromParent
    // handles this automatically.
    // Use this for custom logic (e.g., showing "new workout synced" badge)
}
```

CloudKit sync is not instant -- there can be a delay of seconds to minutes. For real-time iPhone <-> Watch sync during a workout, use WatchConnectivity (Section 3). CloudKit handles the longer-term cross-device sync (e.g., iPhone to iPad, or restoring on a new device).

---

## 7. Recommended Architecture

### Architecture Pattern: MVVM with Repository Pattern

For a workout tracker with iOS + watchOS targets, MVVM provides the right balance of testability, simplicity, and SwiftUI compatibility.

**Why MVVM over TCA (The Composable Architecture):**

| Criteria | MVVM | TCA |
|----------|------|-----|
| **Learning curve** | Low -- native to SwiftUI patterns | High -- requires understanding reducers, effects, dependencies |
| **SwiftUI alignment** | `@Observable` + `@State` is idiomatic SwiftUI | Works with SwiftUI but adds significant abstraction |
| **watchOS** | Lightweight, fits Watch memory constraints | TCA's overhead is noticeable on Watch |
| **Team scalability** | Easy for new iOS developers to understand | Requires team buy-in and training |
| **Testing** | Testable with protocol-based DI | Excellent testability (TCA's strongest point) |
| **Boilerplate** | Moderate | High (reducers, actions, state, effects for every feature) |
| **Performance** | Minimal overhead | Slight overhead from store observation |

**TCA is excellent but over-engineered for this app's scope.** A workout tracker has relatively simple state management (current workout, exercise library, settings). MVVM with `@Observable` (iOS 17+) is sufficient.

### Dependency Injection

Use a lightweight DI approach with Swift protocols and an environment-based container:

```swift
// 1. Define protocols for all services
protocol WorkoutRepository {
    func fetchWorkouts(limit: Int) async throws -> [Workout]
    func saveWorkout(_ workout: Workout) async throws
    func deleteWorkout(_ workout: Workout) async throws
}

protocol HealthKitService {
    func requestAuthorization() async throws -> Bool
    func startWorkoutSession(
        type: HKWorkoutActivityType
    ) async throws -> WorkoutSession
    func saveWorkout(_ workout: Workout) async throws
}

protocol ExerciseRepository {
    func fetchExercises(
        category: ExerciseCategory?
    ) async throws -> [Exercise]
    func searchExercises(query: String) async throws -> [Exercise]
}

// 2. Create concrete implementations
class CoreDataWorkoutRepository: WorkoutRepository {
    private let context: NSManagedObjectContext
    // ...
}

// 3. DI Container
@Observable
class AppDependencies {
    let workoutRepository: WorkoutRepository
    let exerciseRepository: ExerciseRepository
    let healthKitService: HealthKitService
    let connectivityManager: ConnectivityManager
    let persistence: PersistenceController

    init(
        workoutRepository: WorkoutRepository? = nil,
        exerciseRepository: ExerciseRepository? = nil
        // ... allow injection for testing
    ) {
        let persistence = PersistenceController.shared
        self.persistence = persistence
        self.workoutRepository = workoutRepository
            ?? CoreDataWorkoutRepository(
                context: persistence.container.viewContext
            )
        self.exerciseRepository = exerciseRepository
            ?? CoreDataExerciseRepository(
                context: persistence.container.viewContext
            )
        self.healthKitService = DefaultHealthKitService()
        self.connectivityManager = ConnectivityManager.shared
    }
}

// 4. Inject via SwiftUI Environment
@main
struct StrengthTrackerApp: App {
    let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dependencies)
        }
    }
}
```

### Testing Strategy

| Layer | Testing Approach | Tools |
|-------|------------------|-------|
| **View Models** | Unit tests with mock repositories | XCTest, Swift Testing (iOS 18+) |
| **Repositories** | Integration tests with in-memory Core Data store | XCTest, in-memory `NSPersistentContainer` |
| **HealthKit** | Mock `HKHealthStore` via protocol | XCTest with mock implementations |
| **WatchConnectivity** | Mock `WCSession` via protocol | XCTest |
| **Views** | Snapshot tests for key screens | Swift Snapshot Testing (Point-Free) |
| **End-to-end** | UI tests for critical flows | XCUITest |

```swift
// Example: Testing with in-memory Core Data
class WorkoutRepositoryTests: XCTestCase {
    var container: NSPersistentContainer!
    var repository: CoreDataWorkoutRepository!

    override func setUp() {
        container = NSPersistentContainer(name: "StrengthTracker")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, _ in }
        repository = CoreDataWorkoutRepository(
            context: container.viewContext
        )
    }

    func testSaveAndFetchWorkout() async throws {
        let workout = Workout(name: "Push Day", date: .now)
        try await repository.saveWorkout(workout)
        let fetched = try await repository.fetchWorkouts(limit: 10)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].name, "Push Day")
    }
}
```

### Project Structure

```
StrengthTracker/
|
|-- StrengthTracker.xcodeproj
|
|-- Shared/                              # Shared between iOS and watchOS
|   |-- Models/
|   |   |-- Domain/
|   |   |   |-- Exercise.swift           # Domain model (not Core Data)
|   |   |   |-- Workout.swift
|   |   |   |-- WorkoutSet.swift
|   |   |   |-- WorkoutTemplate.swift
|   |   |   |-- BodyMeasurement.swift
|   |   |   |-- ExerciseCategory.swift
|   |   |   |-- MuscleGroup.swift
|   |   |-- CoreData/
|   |   |   |-- StrengthTracker.xcdatamodeld
|   |   |   |-- CDExercise+Extensions.swift
|   |   |   |-- CDWorkout+Extensions.swift
|   |   |   |-- CDWorkoutSet+Extensions.swift
|   |   |   |-- CDExerciseGroup+Extensions.swift
|   |   |-- Mappers/
|   |       |-- WorkoutMapper.swift       # Core Data <-> Domain mapping
|   |       |-- ExerciseMapper.swift
|   |
|   |-- Repositories/
|   |   |-- WorkoutRepository.swift       # Protocol
|   |   |-- ExerciseRepository.swift      # Protocol
|   |   |-- CoreDataWorkoutRepository.swift
|   |   |-- CoreDataExerciseRepository.swift
|   |
|   |-- Services/
|   |   |-- HealthKitService.swift        # Protocol + implementation
|   |   |-- ConnectivityManager.swift     # WatchConnectivity
|   |   |-- PersistenceController.swift   # Core Data stack
|   |   |-- RestTimerService.swift
|   |   |-- UnitConversionService.swift   # kg <-> lbs
|   |
|   |-- Utilities/
|       |-- DateFormatters.swift
|       |-- Constants.swift
|       |-- Extensions/
|           |-- Date+Extensions.swift
|           |-- Double+Extensions.swift
|
|-- iOS/                                  # iPhone app target
|   |-- App/
|   |   |-- StrengthTrackerApp.swift      # @main
|   |   |-- AppDependencies.swift
|   |   |-- ContentView.swift             # Root TabView
|   |
|   |-- Features/
|   |   |-- Workout/
|   |   |   |-- Views/
|   |   |   |   |-- WorkoutListView.swift
|   |   |   |   |-- ActiveWorkoutView.swift
|   |   |   |   |-- ExerciseSetRowView.swift
|   |   |   |   |-- AddExerciseView.swift
|   |   |   |   |-- RestTimerView.swift
|   |   |   |-- ViewModels/
|   |   |       |-- WorkoutListViewModel.swift
|   |   |       |-- ActiveWorkoutViewModel.swift
|   |   |
|   |   |-- ExerciseLibrary/
|   |   |   |-- Views/
|   |   |   |   |-- ExerciseListView.swift
|   |   |   |   |-- ExerciseDetailView.swift
|   |   |   |   |-- CreateExerciseView.swift
|   |   |   |-- ViewModels/
|   |   |       |-- ExerciseLibraryViewModel.swift
|   |   |
|   |   |-- History/
|   |   |   |-- Views/
|   |   |   |   |-- WorkoutHistoryView.swift
|   |   |   |   |-- WorkoutDetailView.swift
|   |   |   |   |-- CalendarView.swift
|   |   |   |-- ViewModels/
|   |   |       |-- WorkoutHistoryViewModel.swift
|   |   |
|   |   |-- Progress/
|   |   |   |-- Views/
|   |   |   |   |-- ProgressDashboardView.swift
|   |   |   |   |-- ExerciseProgressChart.swift
|   |   |   |   |-- BodyWeightChart.swift
|   |   |   |-- ViewModels/
|   |   |       |-- ProgressViewModel.swift
|   |   |
|   |   |-- Settings/
|   |       |-- Views/
|   |       |   |-- SettingsView.swift
|   |       |   |-- UnitsSettingView.swift
|   |       |   |-- TimerSettingView.swift
|   |       |-- ViewModels/
|   |           |-- SettingsViewModel.swift
|   |
|   |-- Components/                       # Reusable iOS-specific UI
|       |-- NumericInputField.swift
|       |-- SetTypeIndicator.swift
|       |-- MuscleGroupBadge.swift
|       |-- WorkoutSummaryCard.swift
|
|-- WatchApp/                             # watchOS app target
|   |-- App/
|   |   |-- StrengthTrackerWatchApp.swift # @main
|   |   |-- WatchAppDependencies.swift
|   |
|   |-- Features/
|   |   |-- WorkoutList/
|   |   |   |-- WatchWorkoutListView.swift
|   |   |-- ActiveWorkout/
|   |   |   |-- WatchActiveWorkoutView.swift  # TabView pages
|   |   |   |-- WatchExerciseSetEntry.swift
|   |   |   |-- WatchRestTimerView.swift
|   |   |   |-- WatchMetricsView.swift        # Heart rate, cals
|   |   |-- Summary/
|   |       |-- WatchWorkoutSummaryView.swift
|   |
|   |-- ViewModels/
|   |   |-- WatchWorkoutSessionManager.swift  # HKWorkoutSession
|   |
|   |-- Components/
|       |-- WatchSetRow.swift
|       |-- WatchWeightInput.swift            # Digital Crown
|
|-- Tests/
|   |-- UnitTests/
|   |   |-- Repositories/
|   |   |   |-- WorkoutRepositoryTests.swift
|   |   |   |-- ExerciseRepositoryTests.swift
|   |   |-- ViewModels/
|   |   |   |-- ActiveWorkoutViewModelTests.swift
|   |   |   |-- WorkoutHistoryViewModelTests.swift
|   |   |-- Services/
|   |       |-- HealthKitServiceTests.swift
|   |       |-- ConnectivityManagerTests.swift
|   |
|   |-- IntegrationTests/
|   |   |-- CoreDataIntegrationTests.swift
|   |   |-- CloudKitSyncTests.swift
|   |
|   |-- UITests/
|       |-- WorkoutFlowUITests.swift
|       |-- ExerciseLibraryUITests.swift
|
|-- Resources/
    |-- ExerciseLibrary.json              # Default exercise database
    |-- Assets.xcassets
    |-- Localizable.strings
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **UI Framework** | SwiftUI | Shared across iOS + watchOS, modern, declarative |
| **Architecture** | MVVM + Repository | Right complexity for the app, SwiftUI-native |
| **Persistence** | Core Data + NSPersistentCloudKitContainer | Mature CloudKit sync, proven at scale |
| **Cloud sync** | CloudKit (via Core Data) | Free, serverless, automatic |
| **Device sync** | WatchConnectivity | Real-time during workouts, queued for completed data |
| **Health data** | HealthKit | Required for workout recording, activity rings, heart rate |
| **DI approach** | Protocol-based with Environment injection | Testable, lightweight, SwiftUI-idiomatic |
| **Observation** | `@Observable` (iOS 17+) | Modern, less boilerplate than `ObservableObject` |
| **Concurrency** | Swift Concurrency (async/await, actors) | Modern, safe, replaces completion handlers |
| **Charts** | Swift Charts | Native, no third-party dependency |
| **Live Activity** | ActivityKit | Rest timer on lock screen |
| **Minimum iOS** | 17.0 | Required for `@Observable`, latest SwiftUI features |
| **Minimum watchOS** | 10.0 | Required for new navigation model, vertical TabView |
| **Xcode** | 16.0+ | Required for iOS 18 SDK, latest Swift (6.0) |
| **Swift version** | 6.0 | Full concurrency checking, typed throws |

---

## 8. Final Recommendation Summary

### The Stack

```
+---------------------------------------------------+
|                   PRESENTATION                     |
|  SwiftUI (iOS 17+)     |    SwiftUI (watchOS 10+) |
|  @Observable ViewModels |    Vertical TabView      |
|  NavigationStack        |    Digital Crown input   |
|  Swift Charts           |    HK Live Workout UI   |
+---------------------------------------------------+
|                  BUSINESS LOGIC                     |
|  MVVM ViewModels                                   |
|  Repository Protocol Layer                         |
|  Domain Models (value types)                       |
|  Unit Conversion, Rest Timer, Workout Logic        |
+---------------------------------------------------+
|                    SERVICES                         |
|  HealthKitService    |  ConnectivityManager        |
|  (HKWorkoutSession,  |  (WCSession, real-time      |
|   HKWorkoutBuilder)  |   + queued transfers)       |
+---------------------------------------------------+
|                   PERSISTENCE                      |
|  Core Data + NSPersistentCloudKitContainer         |
|  Local SQLite store (iPhone + Watch each have own) |
|  CloudKit private database (automatic sync)        |
+---------------------------------------------------+
|                   PLATFORM                         |
|  iOS 17+ / watchOS 10+ / Xcode 16+ / Swift 6.0    |
|  ActivityKit (Live Activities for rest timer)      |
|  WidgetKit (workout summary widgets)               |
+---------------------------------------------------+
```

### Development Phases

**Phase 1 - Foundation (Weeks 1-3):**
- Xcode project setup with iOS + watchOS targets
- Core Data model and persistence controller
- Exercise library (bundled JSON + Core Data)
- Basic MVVM structure

**Phase 2 - iOS Workout Flow (Weeks 4-6):**
- Active workout view (add exercises, log sets)
- Rest timer with Live Activity
- Workout history list and detail views
- HealthKit integration (save workouts)

**Phase 3 - Watch App (Weeks 7-9):**
- Watch workout flow (start, log sets, end)
- HKWorkoutSession integration (heart rate, calories)
- Digital Crown weight/rep input
- WatchConnectivity sync with iPhone

**Phase 4 - Cloud and Polish (Weeks 10-12):**
- CloudKit sync via NSPersistentCloudKitContainer
- Progress charts with Swift Charts
- Workout templates
- Settings (units, timer defaults)
- Widget for workout summary

### Key Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **CloudKit sync delays** | User sees stale data across devices | Use WatchConnectivity for iPhone<->Watch real-time sync. Show sync status indicator. CloudKit handles background sync. |
| **Core Data migration failures** | Data loss on app update | Test all migrations thoroughly. Keep migration paths simple. Use lightweight migration when possible. Implement export/backup feature early. |
| **HealthKit permission denied** | App works but no health data | App must function fully without HealthKit. Treat it as an enhancement. Show clear permission rationale. |
| **watchOS memory pressure** | Watch app crashes during long workouts | Keep Watch views lightweight. Minimize data loaded on Watch. Test with Instruments on real device. |
| **Swift 6 concurrency strictness** | Compilation issues with Sendable checks | Adopt incrementally. Use `@MainActor` for view models. Use `ModelActor` for Core Data background work. |

---

## Appendix A: Package Dependencies

Minimize third-party dependencies. The Apple ecosystem provides most of what is needed:

| Need | Solution | Third-Party Alternative |
|------|----------|------------------------|
| UI Framework | SwiftUI | -- |
| Charts | Swift Charts | -- |
| Persistence | Core Data | -- |
| Cloud Sync | CloudKit | -- |
| Health Data | HealthKit | -- |
| Device Sync | WatchConnectivity | -- |
| Live Activity | ActivityKit | -- |
| Widgets | WidgetKit | -- |
| Snapshot Tests | -- | swift-snapshot-testing (Point-Free) |
| Linting | -- | SwiftLint |
| Logging | os.Logger | -- |
| Networking | -- | None needed (CloudKit handles it) |

The goal is zero runtime third-party dependencies. Only development/testing tools as needed.

## Appendix B: iOS/watchOS Version Adoption Rates

As of early 2025:
- **iOS 17+:** ~85% of active iPhones (safe minimum target)
- **iOS 18+:** ~55-60% (too early to require)
- **watchOS 10+:** ~80% of active Apple Watches
- **Recommendation:** Target iOS 17.0 / watchOS 10.0 as minimums. Use iOS 18 features with `if #available` checks where beneficial.

## Appendix C: Competitor Feature Matrix

| Feature | Strong | Hevy | Fitbod | Our Target (MVP) |
|---------|--------|------|--------|-------------------|
| Custom exercises | Yes | Yes | Limited | Yes |
| Workout templates | Yes | Yes | Auto-generated | Yes |
| Rest timer | Yes | Yes | Yes | Yes (+ Live Activity) |
| Apple Watch app | Yes | Yes | Yes | Yes (standalone) |
| HealthKit sync | Yes | Yes | Yes | Yes |
| CloudKit sync | No (own server) | No (own server) | No (own server) | Yes (free, no account) |
| Progress charts | Yes (Pro) | Yes | Yes | Yes (free) |
| Offline support | Yes | Yes | Yes | Yes |
| Supersets | Yes | Yes | No | Phase 2 |
| Body measurements | Yes | Limited | No | Yes |
| Export data | CSV (Pro) | CSV | No | CSV (free) |

The key differentiator for this app: **CloudKit-based sync with no account creation, no subscription required for core features, and a standalone Watch app with full workout logging capability.**
