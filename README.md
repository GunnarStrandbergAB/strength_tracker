# StrengthTracker

A native strength training app for iPhone and Apple Watch, built with SwiftUI and SwiftData.

Track workouts, follow templates, log sets with weight and reps, monitor rest timers, and view personal records — all synced between your phone and wrist.

## Features

### iPhone

- **Dashboard** — overview of recent workouts, quick-start buttons, and active Watch workout banner
- **Workout Templates** — create, edit, and delete reusable workout plans with target sets, reps, and weight per exercise
- **Active Workout** — log sets with weight/reps, RPE tracking, automatic rest timer, exercise navigation
- **Exercise Library** — built-in exercise database with custom exercise support
- **Workout History** — browse past workouts with detailed set logs
- **Progress Tracking** — personal records and progress over time
- **Settings** — weight unit (kg/lbs), rest timer duration, and preferences
- **Widgets** — home screen widgets via WidgetKit

### Apple Watch

- **Quick Start** — pick exercises and start a workout directly from the wrist
- **Template Workouts** — start workouts from templates synced from iPhone
- **Set Logging** — weight and reps input with +/- buttons and Digital Crown rotation
- **Unit-Aware Steps** — 1.25 kg or 2.5 lbs increments based on user preference
- **Live Metrics** — real-time heart rate, active calories, and duration via HealthKit
- **Rest Timer** — automatic rest countdown between sets with dedicated timer view
- **Exercise Navigation** — swipe between exercises, view logged sets as chips
- **Background Workouts** — workouts continue running when wrist drops (workout-processing mode)

### iPhone + Watch Sync

- **Template Sync** — templates created on iPhone automatically sync to Watch via WatchConnectivity
- **Exercise Sync** — custom exercises sync from iPhone to Watch
- **Live Workout Mirror** — iPhone shows a read-only banner of the active Watch workout in real-time
- **Workout History Sync** — completed Watch workouts transfer to iPhone for unified history
- **HealthKit Integration** — workouts saved to Apple Health with heart rate and calorie data
- **Session Recovery** — orphaned HealthKit sessions are recovered after app crash or termination

## Architecture

```
StrengthTracker/
├── Shared/                  # Shared module (StrengthTrackerShared)
│   ├── Models/Domain/       # Domain models (Exercise, Workout, WorkoutTemplate, etc.)
│   ├── Persistence/         # SwiftData entities, mappers, repository implementations
│   ├── Repositories/        # Repository protocol definitions
│   ├── Services/            # ConnectivityManager, HealthKit, RestTimer, UserPreferences
│   ├── ViewModels/          # Shared ViewModels (WorkoutVM, TemplateVM, WatchWorkoutVM)
│   └── DI/                  # AppContainer (dependency injection)
├── iOS/                     # iPhone app (StrengthTrackeriOS)
│   ├── App/                 # App entry point, ContentView
│   └── Features/            # Dashboard, Workout, Templates, History, Progress, Settings
├── WatchApp/                # Watch app (StrengthTrackerWatch)
│   ├── App/                 # Watch app entry point
│   ├── Features/            # WorkoutList, ActiveWorkout, Summary
│   └── Services/            # WatchHealthKitManager
├── Tests/                   # Unit tests
├── Package.swift            # SPM package definition
└── project.yml              # XcodeGen project configuration
```

**Key patterns:**
- **MVVM** — `@Observable` ViewModels with SwiftUI views
- **Repository** — protocol-based data access with SwiftData implementations
- **Mapper** — domain model ↔ SwiftData entity conversion
- **DI Container** — `AppContainer` creates and caches all dependencies as singletons
- **WatchConnectivity** — `applicationContext` for persistent sync, `sendMessage` for real-time updates, `transferUserInfo` for queued delivery

## Requirements

- iOS 17.0+
- watchOS 10.0+
- Xcode 15.0+
- Swift 6.0

## Building

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

```bash
# Generate Xcode project (after changes to project.yml)
cd StrengthTracker && xcodegen generate

# Build iPhone app
xcodebuild -project StrengthTracker.xcodeproj \
  -target "StrengthTracker" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -configuration Debug clean build

# Build Watch app
xcodebuild -project StrengthTracker.xcodeproj \
  -target "StrengthTrackerWatch" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  -sdk watchsimulator -configuration Debug clean build

# Run tests
xcodebuild test -project StrengthTracker.xcodeproj \
  -target "StrengthTrackerTests" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

## License

Private project.
