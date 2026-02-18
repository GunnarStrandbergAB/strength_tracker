# HellBentIron

A no-nonsense strength training tracker for iPhone and Apple Watch. Built with SwiftUI and SwiftData.

Built for lifters who want to log their workouts quickly and get back to the bar. No accounts, no subscriptions, no cloud — your data stays on your device.

## Features

### iPhone

- **Dashboard** — overview of recent workouts, quick-start buttons, and active Watch workout banner
- **Workout Templates** — create templates for your favorite routines. Start a workout from a template and adjust on the fly — add exercises, skip exercises, change the weight. Templates save time without locking you in.
- **Quick Start** — no template? Start an empty workout and add exercises as you go. The full exercise library is always one tap away.
- **Active Workout** — log sets with weight/reps, RPE tracking, automatic rest timer, exercise navigation
- **Exercise Library** — 326 built-in exercises covering barbell, dumbbell, kettlebell, cable, machine, bodyweight, calisthenics, and more. Custom exercise support included.
- **Workout History** — review past workouts with full exercise and set detail
- **Progress Tracking** — automatic personal record detection. Hit a new PR and you'll know it.
- **Workout Analytics** — on-device vector analytics with plateau detection, muscle balance tracking, exercise recommendations, and workout quality scoring. No cloud, no AI API calls — pure math on your device.
- **Webhook Integration** — POST workout JSON to any external endpoint after every completed workout (openClaw PT, AI trainers, n8n, Zapier, etc.)
- **Settings** — weight unit (kg/lbs), rest timer duration, webhook configuration, and preferences
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

### Workout Analytics

All analytics run entirely on-device — no cloud, no AI API calls, no data leaves your phone. Every workout is converted into an 18-dimensional feature vector that captures volume, intensity, muscle targeting, and training patterns. As you log more workouts, the app progressively unlocks deeper insights.

#### Progressive Unlocks

Analytics features are hidden until there's enough training data for them to be meaningful. The insights card doesn't appear on the dashboard until you're close to the first unlock. Each feature tells you how many more workouts you need.

| Workouts | What Unlocks | What It Does |
|---|---|---|
| 5 | **Quality Score** | Rates each workout 0-100 across volume, intensity, balance, and consistency |
| 5 | **Similar Workouts** | Finds past sessions that match your current training pattern |
| 10 | **Plateau Detection** | Spots exercises where progress has stalled for 2+ weeks |
| 20 | **Muscle Balance** | Checks if opposing muscle groups (chest/back, quads/hamstrings) are trained evenly |
| 20 | **Recommendations** | Suggests exercises based on training gaps, plateaus, and muscle imbalances |
| 50 | **Advanced Insights** | Deep analysis across your full training history |

#### Under the Hood

**Vectorization** — each workout is encoded as an 18-dimensional vector capturing total volume, exercise count, intensity distribution, muscle group coverage, rest patterns, and more. Vectors are stored locally and searched using cosine similarity via Apple Accelerate/vDSP.

**Plateau Detection** — sliding-window coefficient of variation analysis on per-exercise volume. When volume flatlines, the app identifies the stall and suggests variations.

**Muscle Balance** — tracks antagonist muscle pair ratios and flags imbalances at three severity levels (mild/moderate/severe) with corrective exercise suggestions.

**Quality Score** — post-workout score across four dimensions: volume consistency, intensity (RPE), rest time pacing, and muscle balance.

### Calorie Estimation

Every completed workout is saved to Apple Health with research-based calorie estimates. The model combines three components:

1. **MET-based session calories** — `MET x bodyWeight(kg) x hours`. MET values are sourced from the [2024 Compendium of Physical Activities (Herrmann et al.)](https://pacompendium.com/) and assigned per exercise category (barbell, kettlebell, machine, bodyweight, etc.) with separate values for compound and isolation movements.

2. **Volume bonus** — based on [Lytle et al. (2019)](https://doi.org/10.1249/MSS.0000000000002111), a regression model (R²=0.75) for resistance exercise energy expenditure. Applies a coefficient of ~2.5 kcal per 1000 kg total volume moved.

3. **EPOC (Excess Post-Exercise Oxygen Consumption)** — 6-15% of session calories, scaled by average RPE when available, or compound exercise ratio as fallback.

The only personal data used is **body weight** (from HealthKit or user preferences). No age, height, or sex data is collected. Warmup sets are excluded. Results are cross-validated against [Joao et al. (2021)](https://doi.org/10.3390/app11125592) (~6 kcal/min average).

### Webhook Integration

After every completed workout (both iPhone and Watch-originated), the app can POST the full workout JSON to an external HTTP endpoint. This enables AI personal trainer integrations and automation workflows.

**Setup:** Settings → Webhook → enter a URL and optional bearer token.

**Compatible with:** OpenClaw, Claude/GPT API, n8n, Make, Zapier, or any HTTP endpoint that accepts JSON.

**Payload:** The full `Workout` JSON object including all exercises, sets, weights, reps, timestamps, and notes.

```json
{
  "id": "...",
  "name": "Push Day",
  "startedAt": "2026-02-18T10:00:00Z",
  "completedAt": "2026-02-18T11:15:00Z",
  "exercises": [
    {
      "exercise": { "name": "Bench Press", "muscleGroup": "chest", ... },
      "sets": [
        { "weight": 100, "reps": 5, "isCompleted": true, ... }
      ]
    }
  ]
}
```

**Behavior:** Fire-and-forget — failures never block workout saving or affect the app. The bearer token is sent as an `Authorization: Bearer <token>` header when configured.

### Privacy

Zero data collection. No analytics. No tracking. No account required. Everything lives on your iPhone and Apple Watch — unless you configure a webhook, in which case workout data is sent to the endpoint you specify.

## Exercise Library — 326 Exercises

The built-in library covers 15 equipment categories and 17 muscle groups. Every exercise includes instructions. Custom exercises can be added on top.

### By Equipment (15 categories)

| Category | Count | Examples |
|---|---|---|
| **Bodyweight** | 77 | Pull-Up, Dips, Pistol Squat, Muscle-Up, Planche, Front Lever |
| **Barbell** | 54 | Bench Press, Squat, Deadlift, Overhead Press, Clean and Press |
| **Dumbbell** | 54 | Arnold Press, Bulgarian Split Squat, Hammer Curl, Incline Press |
| **Cable** | 39 | Face Pull, Lat Pulldown, Cable Crossover, Tricep Pushdown |
| **Machine** | 35 | Leg Press, Hack Squat, Pec Deck, Leg Extension, Seated Row |
| **Resistance Band** | 17 | Band Pull-Apart, Banded Clamshell, Spanish Squat |
| **Kettlebell** | 13 | Kettlebell Swing, Turkish Get-Up, Gorilla Row |
| **Smith Machine** | 10 | Smith Machine Bench, Hip Thrust, Front Squat |
| **Other** | 8 | Sled Push, Battle Ropes, Tire Flip, Yoke Walk |
| **Trap Bar** | 5 | Trap Bar Squat, Trap Bar Romanian Deadlift |
| **EZ Bar** | 5 | Preacher Curl, EZ Bar Spider Curl |
| **Plate** | 4 | Russian Twist, Plate Front Raise, Svend Press |
| **Landmine** | 2 | Landmine Squat, T-Bar Row |
| **Medicine Ball** | 2 | Wall Ball, Rotational Slam |
| **Exercise Ball** | 1 | Stability Ball Stir-the-Pot |

### By Muscle Group (17 groups)

| Muscle Group | Count |
|---|---|
| Chest | 39 |
| Shoulders | 34 |
| Core | 34 |
| Full Body | 28 |
| Quadriceps | 27 |
| Triceps | 24 |
| Back | 24 |
| Biceps | 22 |
| Lats | 17 |
| Glutes | 15 |
| Hamstrings | 13 |
| Calves | 11 |
| Forearms | 10 |
| Traps | 9 |
| Adductors | 7 |
| Hip Flexors | 6 |
| Abductors | 6 |

### Calisthenics & Bodyweight (77 exercises)

Full calisthenics progression support from beginner to advanced:

**Push** — Push-Up, Wide Push-Up, Diamond Push-Up, Decline Push-Up, Archer Push-Up, Pseudo-Planche Push-Up, Hindu Push-Up, Explosive Push-Up, One-Arm Push-Up, Handstand Push-Up, Pike Push-Up

**Dips** — Bench Dip, Dips, Parallel Bar Dip, Ring Dip

**Pull** — Pull-Up, Chin-Up, Wide Grip Pull-Up, Commando Pull-Up, Archer Pull-Up, L-Sit Pull-Up, Towel Pull-Up, Inverted Row

**Muscle-Ups** — Muscle-Up (Bar), Ring Muscle-Up

**Skill & Static Holds** — L-Sit, Tuck Planche, Full Planche, Full Front Lever, Full Back Lever, Human Flag, Iron Cross, Freestanding Handstand, Dead Hang, Towel Hang, Skin the Cat, Hollow Body Hold, Dragon Flag

**Legs** — Bodyweight Squat, Pistol Squat, Cossack Squat, Jump Squat, Sissy Squat, Wall Sit, Single-Leg Glute Bridge, Donkey Kick, Frog Pump, Peterson Step-Up, Poliquin Step-Up, Single-Leg Calf Raise, Nordic Curl, Nordic Hamstring Curl, Reverse Nordic Curl, Sliding Leg Curl, Tibialis Raise

**Core** — Plank, Side Plank, Bicycle Crunch, Dead Bug, Bird Dog, Mountain Climber, V-Up, Hanging Knee Raise, Hanging Leg Raise, Hanging Windshield Wiper, Toes-to-Bar, Superman, Decline Sit-Up, Captain's Chair Knee Raise, Body Saw, Copenhagen Plank, Copenhagen Adductor Exercise, Side-Lying Adductor Raise, Side-Lying Hip Abduction

**Full Body** — Burpee, Bear Crawl

## Architecture

```
StrengthTracker/
├── Shared/                  # Shared module (StrengthTrackerShared)
│   ├── Models/Domain/       # Domain models (Exercise, Workout, WorkoutTemplate, etc.)
│   │   └── Analytics/       # Analytics domain (WorkoutVector, PlateauAnalysis, MuscleBalance)
│   ├── Persistence/         # SwiftData entities, mappers, repository implementations
│   ├── Repositories/        # Repository protocol definitions
│   ├── Services/            # ConnectivityManager, HealthKit, RestTimer, UserPreferences, Webhook
│   │   └── Analytics/       # Vectorizer, VectorSearch, PlateauDetection, MuscleBalance
│   ├── ViewModels/          # Shared ViewModels (WorkoutVM, TemplateVM, AnalyticsVM)
│   └── DI/                  # AppContainer (dependency injection)
├── iOS/                     # iPhone app (StrengthTrackeriOS)
│   ├── App/                 # App entry point, ContentView
│   └── Features/            # Dashboard, Workout, Templates, History, Progress, Settings
├── WatchApp/                # Watch app (StrengthTrackerWatch)
│   ├── App/                 # Watch app entry point
│   ├── Features/            # WorkoutList, ActiveWorkout, Summary
│   └── Services/            # WatchHealthKitManager
├── Tests/                   # Unit tests (248 tests)
├── Package.swift            # SPM package definition
└── project.yml              # XcodeGen project configuration
```

**Key patterns:**

- **DDD** — domain models, mappers, SwiftData entities, repositories, services, ViewModels
- **MVVM** — `@Observable` ViewModels with SwiftUI views
- **Repository** — protocol-based data access with SwiftData implementations
- **Mapper** — domain model <-> SwiftData entity conversion (Float32 storage, Double computation for vectors)
- **DI Container** — `AppContainer` creates and caches all dependencies as singletons
- **Stateless Services** — analytics services take all context as parameters, no mutable state
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
