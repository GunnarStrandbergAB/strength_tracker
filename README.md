# HellBentIron

A no-nonsense strength training tracker for iPhone and Apple Watch. Built with SwiftUI and SwiftData.

Built for lifters who want to log their workouts quickly and get back to the bar. No accounts, no subscriptions, no cloud — your data stays on your device.

## Features

### iPhone

- **Dashboard** — overview of recent workouts, quick-start buttons, and active Watch workout banner
- **Workout Templates** — create templates for your favorite routines. Start a workout from a template and adjust on the fly — add exercises, skip exercises, change the weight. Templates save time without locking you in.
- **Quick Start** — no template? Start an empty workout and add exercises as you go. The full exercise library is always one tap away.
- **Active Workout** — log sets with weight/reps, RPE tracking, automatic rest timer, exercise navigation
- **Exercise Library** — built-in database covering barbell, dumbbell, kettlebell, cable, machine, bodyweight, and more. Custom exercise support included.
- **Workout History** — review past workouts with full exercise and set detail
- **Progress Tracking** — automatic personal record detection. Hit a new PR and you'll know it.
- **Settings** — weight unit (kg/lbs), rest timer duration, and preferences
- **Widgets** — home screen widgets via WidgetKit

### Apple Watch

- **Quick Start** — pick exercises and start a workout directly from the wrist
- **Template Workouts** — start workouts from templates synced from iPhone
- **Set Logging** — weight and reps input with +/- buttons and Digital Crown rotation
- **Unit-Aware Steps** — 2.5 kg or 5 lbs increments based on user preference
- **Live Metrics** — real-time heart rate, active calories, and duration via HealthKit
- **Rest Timer** — automatic rest countdown between sets with dedicated timer view
- **Exercise Navigation** — swipe between exercises, view logged sets as chips
- **Background Workouts** — workouts continue running when wrist drops (workout-processing mode)

### iPhone + Watch Sync

- **Template Sync** — templates created on iPhone automatically sync to Watch via WatchConnectivity
- **Exercise Sync** — custom exercises sync from iPhone to Watch
- **Live Workout Mirror** — iPhone shows a read-only banner of the active Watch workout in real-time
- **Workout History Sync** — completed Watch workouts transfer to iPhone for unified history
- **HealthKit Integration** — workouts saved to Apple Health with duration and estimated calories
- **Session Recovery** — orphaned HealthKit sessions are recovered after app crash or termination

### Calorie Estimation

Every completed workout is saved to Apple Health with research-based calorie estimates. The model combines three components:

1. **MET-based session calories** — `MET x bodyWeight(kg) x hours`. MET values are sourced from the [2024 Compendium of Physical Activities (Herrmann et al.)](https://pacompendium.com/) and assigned per exercise category (barbell, kettlebell, machine, bodyweight, etc.) with separate values for compound and isolation movements.

2. **Volume bonus** — based on [Lytle et al. (2019)](https://doi.org/10.1249/MSS.0000000000002111), a regression model (R²=0.75) for resistance exercise energy expenditure. Applies a coefficient of ~2.5 kcal per 1000 kg total volume moved.

3. **EPOC (Excess Post-Exercise Oxygen Consumption)** — 6-15% of session calories, scaled by average RPE when available, or compound exercise ratio as fallback.

The only personal data used is **body weight** (from HealthKit or user preferences). No age, height, or sex data is collected. Warmup sets are excluded. Results are cross-validated against [João et al. (2021)](https://doi.org/10.3390/app11125592) (~6 kcal/min average).

### Privacy

Zero data collection. No analytics. No tracking. No account required. Everything lives on your iPhone and Apple Watch.

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
