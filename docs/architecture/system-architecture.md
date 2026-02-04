# System Architecture -- Strength Tracker (iOS + Apple Watch)

**Version:** 1.0
**Date:** January 2026
**Status:** Approved for implementation

---

## 1. System Overview

Strength Tracker is a native Apple-platform workout logging application targeting iOS 17+ and watchOS 10+. The system comprises an iPhone app, a standalone Apple Watch app, and shared modules, with cloud sync via CloudKit and health data integration via HealthKit. There are zero runtime third-party dependencies.

```mermaid
graph TB
    subgraph "User Devices"
        iPhone["iPhone App<br/>(iOS 17+)"]
        Watch["Apple Watch App<br/>(watchOS 10+)"]
    end

    subgraph "Apple Services"
        CloudKit["CloudKit<br/>Private Database"]
        HealthKit_iOS["HealthKit<br/>(iPhone)"]
        HealthKit_Watch["HealthKit<br/>(Watch)"]
        APNs["APNs<br/>Push Notifications"]
    end

    subgraph "On-Device Storage"
        CoreData_iOS["Core Data<br/>(iPhone SQLite)"]
        CoreData_Watch["Lightweight Codable<br/>(Watch Local Store)"]
    end

    iPhone <-->|"WatchConnectivity<br/>sendMessage / transferUserInfo<br/>applicationContext / transferFile"| Watch
    iPhone <-->|"NSPersistentCloudKitContainer<br/>Automatic Sync"| CloudKit
    iPhone <-->|"HKWorkoutBuilder<br/>Body Measurements"| HealthKit_iOS
    Watch <-->|"HKWorkoutSession<br/>Heart Rate, Calories"| HealthKit_Watch
    iPhone --- CoreData_iOS
    Watch --- CoreData_Watch
    CloudKit -.->|"Remote Change<br/>Notifications"| APNs
    APNs -.-> iPhone
```

---

## 2. Layer Architecture

The application follows a strict layered architecture with unidirectional dependencies. Each layer communicates only with the layer directly below it through protocol-defined interfaces.

```mermaid
graph TB
    subgraph "Presentation Layer"
        SwiftUI["SwiftUI Views<br/>NavigationStack, TabView, List<br/>Swift Charts, ActivityKit"]
    end

    subgraph "ViewModel Layer"
        VM["@Observable ViewModels<br/>ActiveWorkoutVM, HistoryVM<br/>ExerciseLibraryVM, ProgressVM<br/>SettingsVM"]
    end

    subgraph "Repository Layer"
        Repos["Protocol-Based Repositories<br/>WorkoutRepository<br/>ExerciseRepository<br/>TemplateRepository<br/>MeasurementRepository<br/>PersonalRecordRepository"]
    end

    subgraph "Service Layer"
        Services["Platform Services<br/>HealthKitService<br/>ConnectivityManager<br/>RestTimerService<br/>UnitConversionService<br/>CSVImportExportService"]
    end

    subgraph "Persistence Layer"
        Persistence["Core Data Stack<br/>NSPersistentCloudKitContainer<br/>NSManagedObjectContext<br/>Background Contexts"]
    end

    subgraph "Cloud Layer"
        Cloud["CloudKit Private Database<br/>Custom Zone<br/>CKServerChangeToken<br/>Automatic Conflict Resolution"]
    end

    SwiftUI --> VM
    VM --> Repos
    VM --> Services
    Repos --> Persistence
    Persistence --> Cloud
```

### Layer Responsibilities

| Layer | Responsibility | Key Technologies |
|-------|---------------|-----------------|
| **Presentation** | UI rendering, user interaction, layout | SwiftUI, Swift Charts, ActivityKit, WidgetKit |
| **ViewModel** | State management, UI logic, data transformation | @Observable, async/await |
| **Repository** | Data access abstraction, CRUD operations, query composition | Protocol interfaces, Core Data fetch requests |
| **Service** | Platform integration, cross-cutting concerns | HealthKit, WatchConnectivity, UNNotifications |
| **Persistence** | Local storage, schema management, migration | Core Data, NSPersistentCloudKitContainer |
| **Cloud** | Cross-device sync, backup, conflict resolution | CloudKit private database |

---

## 3. Component Architecture -- iOS App

The iPhone app is organized into five feature modules, each containing its own views and view models. Shared modules provide cross-cutting data access and services.

```mermaid
graph TB
    subgraph "iOS App"
        TabBar["Root TabView"]

        subgraph "Workout Feature"
            WL["WorkoutListView<br/>(Templates + Quick Start)"]
            AW["ActiveWorkoutView<br/>(Set Logging)"]
            RT["RestTimerView<br/>(+ Live Activity)"]
            AE["AddExerciseView<br/>(Exercise Picker)"]
        end

        subgraph "History Feature"
            HL["WorkoutHistoryView<br/>(Reverse Chronological)"]
            CV["CalendarView<br/>(Monthly Dot View)"]
            WD["WorkoutDetailView<br/>(Full Workout Review)"]
        end

        subgraph "Exercises Feature"
            EL["ExerciseListView<br/>(Search + Filter)"]
            ED["ExerciseDetailView<br/>(Stats, PR History)"]
            CE["CreateExerciseView<br/>(Custom Exercises)"]
        end

        subgraph "Progress Feature"
            PD["ProgressDashboardView<br/>(Overview Stats)"]
            EC["ExerciseProgressChart<br/>(1RM, Volume, Weight)"]
            BW["BodyWeightChart<br/>(Measurements)"]
        end

        subgraph "Settings Feature"
            SV["SettingsView"]
            US["UnitsSettingView"]
            TS["TimerSettingView"]
        end

        TabBar --> WL
        TabBar --> HL
        TabBar --> EL
        TabBar --> PD
        TabBar --> SV
        WL --> AW
        AW --> RT
        AW --> AE
        HL --> WD
        HL --> CV
        EL --> ED
        EL --> CE
    end

    subgraph "Shared Modules"
        Repositories
        Services
        DomainModels["Domain Models"]
        CoreDataStack["Core Data Stack"]
    end

    AW --> Repositories
    AW --> Services
    HL --> Repositories
    EL --> Repositories
    PD --> Repositories
    SV --> Repositories
```

### iOS Tab Structure

| Tab | View | Primary ViewModel | Description |
|-----|------|-------------------|-------------|
| **Workout** | WorkoutListView | WorkoutListViewModel | Template grid, quick start, active workout |
| **History** | WorkoutHistoryView | WorkoutHistoryViewModel | Past workouts, calendar, search |
| **Exercises** | ExerciseListView | ExerciseLibraryViewModel | Browse, search, filter, favorites |
| **Progress** | ProgressDashboardView | ProgressViewModel | Charts, PRs, body measurements |
| **Profile** | SettingsView | SettingsViewModel | Units, timer, data export, HealthKit |

---

## 4. Component Architecture -- Watch App

The Watch app is a standalone SwiftUI application with its own entry point. It uses a vertical TabView for primary navigation during active workouts and communicates with the iPhone via WatchConnectivity.

```mermaid
graph TB
    subgraph "Watch App"
        WatchEntry["@main<br/>StrengthTrackerWatchApp"]

        subgraph "Workout List"
            WatchWL["WatchWorkoutListView<br/>(Templates + Quick Start)"]
        end

        subgraph "Active Workout (Vertical TabView)"
            Page1["Page 1: Current Exercise<br/>Set Entry View"]
            Page2["Page 2: Workout Controls<br/>Pause / End / Next"]
            Page3["Page 3: Metrics<br/>Heart Rate / Calories / Duration"]
        end

        subgraph "Supporting Views"
            WatchRT["WatchRestTimerView<br/>(Full-screen Countdown)"]
            WatchSummary["WatchWorkoutSummaryView<br/>(Post-workout Stats)"]
        end

        WatchEntry --> WatchWL
        WatchWL --> Page1
        Page1 --- Page2
        Page2 --- Page3
        Page1 -->|"Set Complete"| WatchRT
        Page2 -->|"End Workout"| WatchSummary
    end

    subgraph "Watch Services"
        SessionMgr["WatchWorkoutSessionManager<br/>(HKWorkoutSession lifecycle)"]
        SyncMgr["WatchSyncManager<br/>(WatchConnectivity)"]
    end

    Page1 --> SessionMgr
    Page1 --> SyncMgr
    SessionMgr -->|"Heart Rate<br/>Calories"| HealthKit_W["HealthKit (Watch)"]
    SyncMgr <-->|"WatchConnectivity"| iPhone_Remote["iPhone App"]
```

### Watch Features vs iPhone Features

| Feature | iPhone | Watch |
|---------|--------|-------|
| Start workout from template | Yes | Yes |
| Quick start empty workout | Yes | Yes |
| Log sets (weight/reps) | Yes | Yes (Digital Crown) |
| Rest timer with haptics | Yes (+ Live Activity) | Yes (haptic tap) |
| View workout history | Yes | No |
| Exercise library / search | Yes | No (receive from iPhone) |
| Create custom exercises | Yes | No |
| Progress charts | Yes | No |
| Body measurements | Yes | No |
| Template creation/editing | Yes | No |
| PR detection and display | Yes | Yes (receive notification) |
| HealthKit workout recording | Yes (HKWorkoutBuilder) | Yes (HKWorkoutSession) |
| Heart rate monitoring | No (reads from Watch) | Yes (auto during session) |
| Settings | Yes | No (receive from iPhone) |

---

## 5. Sync Architecture

Data flows between three systems: iPhone, Apple Watch, and CloudKit. Each uses a different sync mechanism optimized for its use case.

```mermaid
sequenceDiagram
    participant Watch as Apple Watch
    participant iPhone as iPhone
    participant CloudKit as CloudKit

    Note over iPhone,CloudKit: App Launch / Background Sync
    iPhone->>CloudKit: Fetch changes (CKServerChangeToken)
    CloudKit-->>iPhone: New/modified records
    iPhone->>iPhone: Merge into Core Data

    Note over Watch,iPhone: Exercise Library Sync
    iPhone->>Watch: updateApplicationContext<br/>(exercise library, settings)
    Watch->>Watch: Store lightweight Codable models

    Note over Watch,iPhone: Workout Started on Watch
    Watch->>Watch: Start HKWorkoutSession
    Watch->>iPhone: sendMessage<br/>(workout started)

    Note over Watch,iPhone: During Workout (Real-time)
    loop Each Set Completed
        Watch->>iPhone: sendMessage<br/>(set data)
        iPhone->>iPhone: Save to Core Data
        iPhone-->>Watch: Reply (PR detected?)
    end

    Note over Watch,iPhone: Workout Completed
    Watch->>Watch: End HKWorkoutSession
    Watch->>iPhone: transferUserInfo<br/>(completed workout)
    iPhone->>iPhone: Save to Core Data
    iPhone->>CloudKit: Automatic sync via<br/>NSPersistentCloudKitContainer

    Note over Watch,iPhone: Offline Scenario
    Watch->>Watch: Store workout locally
    Watch--xiPhone: sendMessage fails (not reachable)
    Watch->>Watch: Queue via transferUserInfo
    Note over Watch,iPhone: When reconnected...
    Watch->>iPhone: Queued transferUserInfo delivered
    iPhone->>iPhone: Process and save
    iPhone->>CloudKit: Sync to cloud
```

### Sync Method Selection Matrix

| Data Type | Direction | Method | Rationale |
|-----------|-----------|--------|-----------|
| Active set completion | Watch to iPhone | `sendMessage` | Real-time UI update on iPhone; falls back to `transferUserInfo` if unreachable |
| Completed workout | Watch to iPhone | `transferUserInfo` | Guaranteed delivery even if iPhone app is not running |
| Exercise library | iPhone to Watch | `updateApplicationContext` | Latest-only; Watch needs current version, not history |
| User settings | iPhone to Watch | `updateApplicationContext` | Latest-only; small payload |
| Template list | iPhone to Watch | `updateApplicationContext` | Latest-only; replaced entirely on each update |
| Full database sync | iPhone to Watch | `transferFile` | Initial setup or recovery; up to 100MB |
| PR notification | iPhone to Watch | `sendMessage` | Real-time celebration on Watch |
| Complication data | iPhone to Watch | `transferCurrentComplicationUserInfo` | High-priority, limited to 50/day |
| All entities | iPhone to CloudKit | NSPersistentCloudKitContainer | Automatic, background, conflict-resolved |

---

## 6. Data Flow Diagrams

### 6.1 Workout Logging Data Flow (iPhone)

```mermaid
flowchart LR
    User["User Input<br/>(Weight, Reps, Complete)"]
    View["ActiveWorkoutView<br/>(SwiftUI)"]
    VM["ActiveWorkoutViewModel<br/>(@Observable)"]
    Repo["WorkoutRepository<br/>(Protocol)"]
    CD["Core Data<br/>(NSManagedObjectContext)"]
    CK["CloudKit<br/>(Automatic)"]
    HK["HealthKit<br/>(HKWorkoutBuilder)"]
    Timer["RestTimerService<br/>(+ ActivityKit)"]
    PR["PR Detection<br/>(PersonalRecordRepository)"]

    User --> View
    View --> VM
    VM -->|"saveSet()"| Repo
    Repo --> CD
    CD -->|"Auto sync"| CK
    VM -->|"completeSet()"| Timer
    VM -->|"checkPR()"| PR
    VM -->|"endWorkout()"| HK
    Timer -->|"Live Activity<br/>Notification"| User
    PR -->|"Trophy badge"| View
```

### 6.2 HealthKit Integration Data Flow

```mermaid
flowchart TB
    subgraph "Write to HealthKit"
        App_W["App writes"]
        HK_Workout["HKWorkout<br/>(duration, type, calories)"]
        HK_Energy["Active Energy Burned<br/>(HKQuantity)"]
        HK_Weight["Body Mass<br/>(from measurements)"]
    end

    subgraph "Read from HealthKit"
        HK_HR["Heart Rate<br/>(Watch auto-collects)"]
        HK_BW["Body Weight<br/>(from Apple Health)"]
        HK_Activity["Activity Summary<br/>(rings data)"]
        App_R["App reads"]
    end

    App_W --> HK_Workout
    App_W --> HK_Energy
    App_W --> HK_Weight
    HK_HR --> App_R
    HK_BW --> App_R
    HK_Activity --> App_R
```

| HealthKit Type | Direction | When | Description |
|---------------|-----------|------|-------------|
| `HKWorkout` | Write | Workout ends | Workout session with duration, calories, activity type |
| `activeEnergyBurned` | Write | Workout ends | Calories burned during workout |
| `bodyMass` | Write | User enters measurement | Body weight from manual entry |
| `heartRate` | Read | During Watch workout | Auto-collected by HKWorkoutSession |
| `bodyMass` | Read | On demand | Sync body weight from Apple Health |
| `activitySummary` | Read | Dashboard view | Move/Exercise/Stand ring progress |

---

## 7. Project Structure

```
StrengthTracker/
|
|-- StrengthTracker.xcodeproj
|
|-- Shared/                              # Shared between iOS and watchOS targets
|   |-- Models/
|   |   |-- Domain/                      # Plain Swift value types
|   |   |   |-- Exercise.swift
|   |   |   |-- Workout.swift
|   |   |   |-- WorkoutSet.swift
|   |   |   |-- WorkoutTemplate.swift
|   |   |   |-- BodyMeasurement.swift
|   |   |   |-- PersonalRecord.swift
|   |   |   |-- Enums.swift             # MuscleGroup, ExerciseCategory, etc.
|   |   |-- CoreData/                    # Managed object subclasses
|   |   |   |-- StrengthTracker.xcdatamodeld
|   |   |   |-- CDExercise+Extensions.swift
|   |   |   |-- CDWorkout+Extensions.swift
|   |   |   |-- CDWorkoutExercise+Extensions.swift
|   |   |   |-- CDExerciseSet+Extensions.swift
|   |   |   |-- CDWorkoutTemplate+Extensions.swift
|   |   |   |-- CDTemplateExercise+Extensions.swift
|   |   |   |-- CDTemplateFolder+Extensions.swift
|   |   |   |-- CDBodyMeasurement+Extensions.swift
|   |   |   |-- CDPersonalRecord+Extensions.swift
|   |   |   |-- CDUserSettings+Extensions.swift
|   |   |-- Mappers/                     # Core Data <-> Domain conversion
|   |       |-- WorkoutMapper.swift
|   |       |-- ExerciseMapper.swift
|   |       |-- TemplateMapper.swift
|   |
|   |-- Repositories/                    # Protocol definitions + Core Data impls
|   |   |-- Protocols/
|   |   |   |-- WorkoutRepository.swift
|   |   |   |-- ExerciseRepository.swift
|   |   |   |-- TemplateRepository.swift
|   |   |   |-- MeasurementRepository.swift
|   |   |   |-- PersonalRecordRepository.swift
|   |   |-- CoreData/
|   |       |-- CoreDataWorkoutRepository.swift
|   |       |-- CoreDataExerciseRepository.swift
|   |       |-- CoreDataTemplateRepository.swift
|   |       |-- CoreDataMeasurementRepository.swift
|   |       |-- CoreDataPersonalRecordRepository.swift
|   |
|   |-- Services/
|   |   |-- HealthKitService.swift
|   |   |-- ConnectivityManager.swift
|   |   |-- PersistenceController.swift
|   |   |-- RestTimerService.swift
|   |   |-- UnitConversionService.swift
|   |   |-- PRDetectionService.swift
|   |   |-- CSVImportExportService.swift
|   |
|   |-- Utilities/
|       |-- Constants.swift
|       |-- DateFormatters.swift
|       |-- OneRepMaxCalculator.swift
|       |-- Extensions/
|
|-- iOS/                                 # iPhone app target
|   |-- App/
|   |   |-- StrengthTrackerApp.swift
|   |   |-- AppDependencies.swift
|   |   |-- ContentView.swift
|   |-- Features/
|   |   |-- Workout/
|   |   |-- History/
|   |   |-- ExerciseLibrary/
|   |   |-- Progress/
|   |   |-- Settings/
|   |-- Components/
|   |-- Widgets/
|   |-- LiveActivity/
|
|-- WatchApp/                            # watchOS app target (standalone)
|   |-- App/
|   |   |-- StrengthTrackerWatchApp.swift
|   |   |-- WatchAppDependencies.swift
|   |-- Features/
|   |   |-- WorkoutList/
|   |   |-- ActiveWorkout/
|   |   |-- Summary/
|   |-- ViewModels/
|   |   |-- WatchWorkoutSessionManager.swift
|   |-- Components/
|   |-- Complications/
|
|-- Tests/
|   |-- UnitTests/
|   |-- IntegrationTests/
|   |-- UITests/
|
|-- Resources/
    |-- ExerciseLibrary.json
    |-- Assets.xcassets
    |-- Localizable.strings
```

---

## 8. Dependency Injection

The app uses protocol-based dependency injection with SwiftUI's Environment system. No DI framework is required.

```mermaid
graph TB
    subgraph "DI Container"
        AppDeps["AppDependencies<br/>(@Observable)"]
    end

    subgraph "Protocols"
        WR["WorkoutRepository"]
        ER["ExerciseRepository"]
        TR["TemplateRepository"]
        HKS["HealthKitService"]
        CM["ConnectivityManager"]
    end

    subgraph "Concrete Implementations"
        CDWR["CoreDataWorkoutRepository"]
        CDER["CoreDataExerciseRepository"]
        CDTR["CoreDataTemplateRepository"]
        DHKS["DefaultHealthKitService"]
        DCM["DefaultConnectivityManager"]
    end

    subgraph "Test Mocks"
        MWR["MockWorkoutRepository"]
        MER["MockExerciseRepository"]
        MHKS["MockHealthKitService"]
    end

    AppDeps --> WR
    AppDeps --> ER
    AppDeps --> TR
    AppDeps --> HKS
    AppDeps --> CM

    WR -.->|"Production"| CDWR
    ER -.->|"Production"| CDER
    TR -.->|"Production"| CDTR
    HKS -.->|"Production"| DHKS
    CM -.->|"Production"| DCM

    WR -.->|"Testing"| MWR
    ER -.->|"Testing"| MER
    HKS -.->|"Testing"| MHKS
```

The `AppDependencies` container is injected at the root of the SwiftUI view hierarchy via `.environment()` and flows down to all child views that need it.

---

## 9. Concurrency Model

The application uses Swift 6.0 structured concurrency throughout.

| Context | Pattern | Rationale |
|---------|---------|-----------|
| View Models | `@MainActor @Observable` | UI state must update on main thread |
| Repository reads | `async throws` methods | Non-blocking data fetching |
| Repository writes | `performBackgroundTask` | Avoid blocking main context |
| HealthKit queries | `async` wrappers over HK callbacks | Modern API surface |
| WatchConnectivity | `@MainActor` delegate methods | Delegate callbacks arrive on arbitrary queues; dispatch to main |
| CloudKit sync | Automatic (NSPersistentCloudKitContainer) | No manual management needed |
| Rest timer | `AsyncTimerSequence` or `Timer.publish` | Continuous UI updates |
| CSV import | Background task with progress | Large imports must not block UI |

---

## 10. Security and Privacy

| Concern | Approach |
|---------|----------|
| Data at rest | Core Data SQLite encrypted via iOS Data Protection (NSFileProtectionComplete) |
| CloudKit data | Encrypted in transit and at rest by Apple; private database accessible only to the user's iCloud account |
| HealthKit | Encrypted at rest by iOS; per-type authorization; excluded from iCloud backup |
| No user accounts | Authentication is implicit via iCloud/Apple ID; no username/password |
| No server | Zero server infrastructure; no attack surface beyond device and iCloud |
| Export data | CSV export stored temporarily; user controls sharing |
| Watch communication | WatchConnectivity is encrypted by the OS; on-device only |

---

## 11. Key Architectural Decisions Summary

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | UI Framework | SwiftUI | Shared codebase with watchOS; declarative; Widget/LiveActivity support |
| 2 | Architecture Pattern | MVVM + Repository | Right complexity for scope; native to SwiftUI with @Observable |
| 3 | Persistence | Core Data + NSPersistentCloudKitContainer | Mature CloudKit sync; proven at scale; reliable migrations |
| 4 | Cloud Sync | CloudKit private database | Free; serverless; no user account creation needed |
| 5 | Device Sync | WatchConnectivity | Real-time during workouts; queued for reliability |
| 6 | Health Integration | HealthKit | Required for Activity Rings, heart rate, workout recording |
| 7 | Observation | @Observable (iOS 17+) | Less boilerplate than ObservableObject; fine-grained updates |
| 8 | Concurrency | Swift 6.0 async/await | Type-safe concurrency; eliminates callback hell |
| 9 | Charts | Swift Charts | Native; no dependency; deep SwiftUI integration |
| 10 | Live Activity | ActivityKit | Rest timer on lock screen / Dynamic Island |
| 11 | Dependencies | Zero runtime third-party | Reduces maintenance burden; no supply chain risk |
| 12 | Watch Architecture | Standalone + companion features | Works independently at gym; syncs when iPhone available |
| 13 | Minimum Targets | iOS 17.0 / watchOS 10.0 | Required for @Observable, modern navigation, vertical TabView |
| 14 | DI Approach | Protocol + Environment injection | Testable; lightweight; idiomatic SwiftUI |
