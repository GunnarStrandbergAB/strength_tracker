# Technology Stack Decisions -- Strength Tracker (iOS + Apple Watch)

**Version:** 1.0
**Date:** January 2026
**Status:** Approved for implementation

---

## 1. Summary

| Category | Choice | Alternatives Considered |
|----------|--------|------------------------|
| UI Framework | SwiftUI | UIKit |
| Architecture | MVVM + Repository Pattern | TCA (The Composable Architecture) |
| Persistence | Core Data + NSPersistentCloudKitContainer | SwiftData |
| Cloud Sync | CloudKit (private database) | Firebase, custom server, Supabase |
| Device Sync | WatchConnectivity (WCSession) | CloudKit only |
| Health Integration | HealthKit | -- |
| Observation | @Observable (iOS 17+) | ObservableObject / Combine |
| Concurrency | Swift Concurrency (async/await, actors) | GCD, Combine |
| Charts | Swift Charts | Charts (third-party), custom drawing |
| Live Activity | ActivityKit | -- |
| Widgets | WidgetKit | -- |
| DI Approach | Protocol-based + SwiftUI Environment | Swinject, TCA Dependencies |
| Min iOS | 17.0 | 16.0 |
| Min watchOS | 10.0 | 9.0 |
| Swift Version | 6.0 | 5.9 |
| Xcode | 16+ | -- |
| Third-Party Dependencies | Zero runtime | -- |

---

## 2. UI Framework: SwiftUI

### Decision

SwiftUI is the UI framework for both the iOS and watchOS targets.

### Rationale

**SwiftUI over UIKit** is clear for a new project starting in 2026:

1. **Shared codebase with watchOS.** SwiftUI is the only option for watchOS 10+. Using SwiftUI on iOS means view components, view models, and data models can be shared across targets. UIKit would require maintaining two entirely separate UI layers.

2. **Declarative and state-driven.** Workout UIs (exercise lists, set rows, rest timers) map naturally to declarative lists and state-driven views. A workout log screen that would require 300+ lines in UIKit is approximately 80 lines in SwiftUI.

3. **Native widget and Live Activity support.** WidgetKit and ActivityKit are SwiftUI-only. The rest timer Live Activity on the lock screen / Dynamic Island requires SwiftUI.

4. **Built-in Swift Charts.** The Swift Charts framework integrates directly with SwiftUI for progress graphs, volume charts, and muscle distribution visualizations.

5. **Future-proof.** Apple invests in SwiftUI as its primary framework. UIKit receives maintenance updates only. All new Apple platform features ship SwiftUI-first.

6. **Less boilerplate.** No storyboards, no autolayout constraints, no delegate patterns for table views.

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Complex list interactions (swipe, reorder, multi-select) | All supported as of iOS 16+ via `onMove`, `swipeActions`, `editMode` |
| Custom numeric input for weight/reps | `TextField` with `.keyboardType(.decimalPad)` or custom SwiftUI overlay |
| Performance with very long lists | `LazyVStack` inside `ScrollView` or `List`; `UIViewRepresentable` escape hatch if needed |
| Navigation complexity | `NavigationStack` with `navigationDestination(for:)` (iOS 16+) handles programmatic navigation |

**UIKit interop:** `UIViewRepresentable` and `UIViewControllerRepresentable` are available for any edge cases. In practice, a workout tracker is unlikely to need this.

---

## 3. Architecture: MVVM + Repository Pattern

### Decision

MVVM (Model-View-ViewModel) with a Repository layer for data access abstraction.

### Rationale

**MVVM over TCA (The Composable Architecture):**

| Criteria | MVVM | TCA |
|----------|------|-----|
| Learning curve | Low -- native SwiftUI patterns | High -- reducers, effects, dependencies |
| SwiftUI alignment | `@Observable` + `@State` is idiomatic | Works but adds significant abstraction |
| watchOS fit | Lightweight, fits Watch memory constraints | Noticeable overhead on Watch |
| Team scalability | Easy for new iOS developers | Requires team training |
| Testing | Testable with protocol-based DI | Excellent (TCA's strongest point) |
| Boilerplate | Moderate | High (reducer, actions, state, effects per feature) |
| Complexity match | Right-sized for a workout tracker | Over-engineered for this scope |

A workout tracker has relatively simple state management: current active workout, exercise library, user settings, and historical data. The state flows are straightforward. TCA's power (composable state, comprehensive side-effect management, time-travel debugging) is not needed here and would add significant complexity.

### Pattern Details

```
View (SwiftUI) --> ViewModel (@Observable, @MainActor)
    --> Repository (protocol) --> Core Data (implementation)
    --> Service (protocol) --> Platform API (implementation)
```

- **Views** are pure SwiftUI declarations with no business logic.
- **ViewModels** are `@Observable @MainActor` classes that own UI state and call repositories/services.
- **Repositories** are protocols abstracting CRUD operations; concrete implementations use Core Data.
- **Services** are protocols for platform integrations (HealthKit, WatchConnectivity, rest timer).

---

## 4. Persistence: Core Data + NSPersistentCloudKitContainer

### Decision

Core Data with `NSPersistentCloudKitContainer` for local persistence and cloud sync.

### Rationale

**Core Data over SwiftData:**

| Aspect | Core Data | SwiftData |
|--------|-----------|-----------|
| CloudKit sync maturity | Production-proven via `NSPersistentCloudKitContainer` | Partially supported; less control, fewer features |
| Background operations | `performBackgroundTask` is robust and battle-tested | `ModelActor` improved in iOS 18 but less proven |
| Complex migrations | Mapping models, custom migration policies | `SchemaMigrationPlan` only; less flexible |
| Scale | Proven with millions of records | Good but less real-world validation at scale |
| Community knowledge | 15+ years of documentation, Stack Overflow, tutorials | Newer; less troubleshooting resources |
| History tracking | `NSPersistentHistoryTracking` fully supported | Added in iOS 18; less mature |

SwiftData, introduced at WWDC 2023, builds on Core Data but its CloudKit integration is not yet as mature. For an app where reliable cross-device sync is a key differentiator, Core Data's proven CloudKit path is the safer choice.

**However**, the app uses modern SwiftUI observation patterns on top of Core Data:

- `@Observable` ViewModels (not `@FetchRequest` directly in views)
- Repository pattern abstracts Core Data from the rest of the app
- Domain model structs (not managed objects) flow to views
- If SwiftData matures sufficiently, the repository layer can be swapped without changing views or view models

---

## 5. Cloud Sync: CloudKit (Private Database)

### Decision

CloudKit private database via `NSPersistentCloudKitContainer`. No custom server.

### Rationale

| Factor | CloudKit | Custom Server (Firebase, Supabase) |
|--------|----------|-----------------------------------|
| Cost | Free (100 MB assets, 500 MB DB, 2 GB transfer per user) | Paid, scales with users |
| Server maintenance | None (Apple manages) | Required |
| User authentication | Implicit via iCloud (no signup flow) | Requires account creation |
| iOS integration | Native (`NSPersistentCloudKitContainer`) | SDK dependency |
| Offline support | Built-in (Core Data is source of truth) | Varies; often requires additional work |
| Conflict resolution | Automatic with Core Data merge policies | Manual implementation |
| Privacy | Data in user's own iCloud account | Data on third-party server |

CloudKit is the natural choice for an Apple-only app. The user does not need to create an account, sign in, or manage credentials. Sync happens automatically via their existing iCloud account. There is no server to build, maintain, or pay for.

**Trade-off:** No Android sync, no web dashboard. This is acceptable for an iOS+watchOS-only app.

---

## 6. Device Sync: WatchConnectivity

### Decision

WatchConnectivity (`WCSession`) for all iPhone <-> Watch communication.

### Rationale

CloudKit sync is not real-time (delays of seconds to minutes) and the Watch does not run `NSPersistentCloudKitContainer`. WatchConnectivity provides:

- **Real-time messaging** (`sendMessage`) during active workouts
- **Guaranteed delivery** (`transferUserInfo`) for completed workout data
- **Latest-state transfer** (`updateApplicationContext`) for exercise library and settings
- **File transfer** for initial sync or recovery

This is the standard Apple-recommended approach for Watch companion apps. See `/workspaces/strength_tracker/docs/architecture/sync-strategy.md` for the full sync design.

---

## 7. Health Integration: HealthKit

### Decision

HealthKit for workout recording, heart rate, calories, and body measurements.

### Rationale

HealthKit is not optional for a strength training app -- it is required for:

- Contributing to Activity Rings (Move/Exercise/Stand goals)
- Recording workout sessions (`HKWorkout`)
- Reading heart rate data during Watch workouts (`HKWorkoutSession`)
- Syncing body weight measurements with Apple Health
- Sharing workout summaries with other health apps

**Key design point:** HealthKit stores workout-level summaries only (duration, calories, activity type). It does NOT store set/rep/weight detail. The app's Core Data database is the source of truth for detailed workout data.

**Privacy:** HealthKit authorization is per-type. The app must function fully without HealthKit access (user can deny). This is handled by making all HealthKit interactions optional with graceful degradation.

---

## 8. Observation: @Observable (iOS 17+)

### Decision

`@Observable` macro (Observation framework) for all view models.

### Rationale

**@Observable over ObservableObject:**

| @Observable (iOS 17+) | ObservableObject (iOS 13+) |
|----------------------|---------------------------|
| Fine-grained property tracking (only re-renders views that read changed properties) | Whole-object observation (`objectWillChange` fires for any property) |
| No `@Published` wrapper needed | Every observed property needs `@Published` |
| Less boilerplate | More boilerplate |
| Works with `@State` in views | Requires `@StateObject` or `@ObservedObject` |
| Modern, forward-looking | Legacy approach |

Since the minimum target is iOS 17, `@Observable` is available on all supported devices.

---

## 9. Concurrency: Swift Concurrency

### Decision

Swift 6.0 structured concurrency throughout (async/await, actors, Sendable).

### Rationale

| Context | Pattern |
|---------|---------|
| ViewModels | `@MainActor @Observable` -- UI state on main thread |
| Repository reads | `async throws` methods -- non-blocking |
| Repository writes | `performBackgroundTask` -- off-main-thread |
| HealthKit queries | `async` wrappers over HK callbacks |
| WatchConnectivity | `@MainActor` delegate dispatch |
| CloudKit sync | Automatic (managed by NSPersistentCloudKitContainer) |
| Rest timer | `AsyncTimerSequence` or `Timer.publish` |
| CSV import | Background `Task` with progress reporting |

Swift 6.0's strict concurrency checking (`Sendable`, data race safety) provides compile-time guarantees that prevent threading bugs.

---

## 10. Charts: Swift Charts

### Decision

Apple's Swift Charts framework for all data visualization.

### Rationale

- Native SwiftUI integration (charts are SwiftUI views)
- No third-party dependency
- Supports line, bar, area, and point marks needed for exercise progression, volume distribution, and body measurement trends
- Available on iOS 16+ (well within our iOS 17 minimum)
- Automatic accessibility support
- Dark mode support out of the box

---

## 11. Live Activity: ActivityKit

### Decision

ActivityKit for the rest timer Live Activity on lock screen and Dynamic Island.

### Rationale

The rest timer is the primary use case for Live Activities in a workout app:

- Countdown visible on lock screen without unlocking
- Dynamic Island compact and expanded views during active timer
- No third-party dependency
- SwiftUI-based presentation
- Available on iOS 16.1+ (within iOS 17 minimum)

---

## 12. Dependency Injection: Protocol + Environment

### Decision

Protocol-based DI with SwiftUI Environment injection. No DI framework.

### Rationale

| Approach | Pros | Cons |
|----------|------|------|
| Protocol + Environment (chosen) | Lightweight, testable, idiomatic SwiftUI, no dependency | Manual wiring |
| Swinject | Powerful, annotation-based | Heavy dependency, not SwiftUI-native |
| TCA Dependencies | Comprehensive | Requires TCA adoption |

The `AppDependencies` container holds all repository and service instances, injected at the root of the view hierarchy via `.environment()`. ViewModels receive dependencies through their initializer. Test targets inject mock implementations.

---

## 13. Minimum Version Targets

| Platform | Minimum | Rationale |
|----------|---------|-----------|
| iOS | 17.0 | Required for `@Observable`, modern `NavigationStack`, `ScrollView` improvements, interactive widgets |
| watchOS | 10.0 | Required for new navigation model, vertical `TabView`, `containerBackground`, `DigitalCrownRotation` |
| Xcode | 16.0+ | Required for iOS 18 SDK, Swift 6.0 |
| Swift | 6.0 | Full concurrency checking, typed throws, improved macros |

**Adoption rates (early 2025 data):**
- iOS 17+: ~85% of active iPhones
- watchOS 10+: ~80% of active Apple Watches

These minimums provide access to all modern APIs while covering the vast majority of the user base.

---

## 14. Zero Third-Party Dependency Strategy

### Decision

Zero runtime third-party dependencies. Development-only tools permitted.

### Runtime (zero dependencies)

Every runtime need is covered by Apple frameworks:

| Need | Apple Solution |
|------|---------------|
| UI | SwiftUI |
| Charts | Swift Charts |
| Persistence | Core Data |
| Cloud sync | CloudKit |
| Health data | HealthKit |
| Device sync | WatchConnectivity |
| Live Activities | ActivityKit |
| Widgets | WidgetKit |
| Networking | None needed (CloudKit handles it) |
| JSON | Foundation (JSONEncoder/Decoder) |
| Logging | os.Logger |
| Keychain | Security framework |

### Development-Only (optional)

| Tool | Purpose | Phase |
|------|---------|-------|
| SwiftLint | Code style enforcement | From Phase 1 |
| swift-snapshot-testing (Point-Free) | UI snapshot regression tests | Post-MVP |

### Rationale

- **No supply chain risk.** No third-party code to audit, no CVEs from transitive dependencies.
- **No maintenance burden.** No dependency updates, no breaking changes from upstream.
- **Smaller binary size.** No bundled frameworks.
- **App review safety.** No third-party SDKs that might trigger App Store review flags.
- **Longevity.** Apple frameworks are maintained as long as iOS is maintained.

---

## 15. Development Environment

| Tool | Version | Purpose |
|------|---------|---------|
| Xcode | 16.0+ | IDE, Interface Builder (Core Data model), Instruments |
| macOS | Sequoia 15.0+ | Required for Xcode 16 |
| Simulator | iOS 17+ / watchOS 10+ | Primary development target |
| Physical devices | iPhone + Apple Watch | Required for HealthKit, WatchConnectivity, and performance testing |
| Git | 2.x | Version control |
| Swift Package Manager | Built into Xcode | Dependency management (dev tools only) |
