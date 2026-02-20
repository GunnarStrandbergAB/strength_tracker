# HellBentIron

A no-nonsense strength training tracker for iPhone and Apple Watch. Built with SwiftUI and SwiftData.

Built for lifters who want to log their workouts quickly and get back to the bar. No accounts, no subscriptions, no cloud — your data stays on your device.

## Features

### iPhone

- **Dashboard** — overview of recent workouts, quick-start buttons, and active Watch workout banner
- **Workout Templates** — create templates for your favorite routines. Start a workout from a template and adjust on the fly — add exercises, skip exercises, change the weight. Templates save time without locking you in.
- **Template Library** — 9 pre-built templates (Push/Pull/Leg Day, Upper/Lower Body, Full Body A & B, Chest & Triceps, Back & Biceps). Browse, preview exercises, and add to your collection as fully editable copies.
- **Quick Start** — no template? Start an empty workout and add exercises as you go. The full exercise library is always one tap away.
- **Active Workout** — log sets with weight/reps, RPE tracking, automatic rest timer, exercise navigation. Tap set number to change type — warm-up, drop set, failure, or rest-pause.
- **Set Types** — five set types (normal, warm-up, drop set, failure, rest-pause). Configure per-set in templates or toggle during workout. Warm-up sets are automatically excluded from personal records, volume totals, and calorie estimates.
- **Exercise Library** — 326 built-in exercises covering barbell, dumbbell, kettlebell, cable, machine, bodyweight, calisthenics, and more. Custom exercise support included.
- **Workout History** — review past workouts with full exercise and set detail
- **Progress Tracking** — automatic personal record detection. Hit a new PR and you'll know it.
- **Workout Analytics** — on-device vector analytics with plateau detection, muscle balance tracking, exercise recommendations, and workout quality scoring. No cloud, no AI API calls — pure math on your device.
- **Progression Planning** — deterministic periodization engine that generates complete 12-week training programs. See [Progression Planning](#progression-planning) below.
- **Webhook Integration** — POST workout JSON to any external endpoint after every completed workout (openClaw PT, AI trainers, n8n, Zapier, etc.)
- **Settings** — weight unit (kg/lbs), rest timer duration, webhook configuration, and preferences
- **Widgets** — home screen widgets and Live Activities via WidgetKit and ActivityKit

### Apple Watch

- **Quick Start** — pick exercises and start a workout directly from the wrist
- **Template Workouts** — start workouts from templates synced from iPhone
- **Today's Plan** — planned sessions from the active progression plan appear on Watch, ready to start with pre-filled weights and reps
- **Set Logging** — weight and reps input with +/- buttons and Digital Crown rotation. Set type badges (warm-up, drop, etc.) shown per set.
- **Unit-Aware Steps** — 2.5 kg or 5 lbs increments based on user preference
- **Live Metrics** — real-time heart rate, active calories, and duration via HealthKit sensors
- **Rest Timer** — automatic rest countdown between sets with dedicated timer view
- **Exercise Navigation** — swipe between exercises, view logged sets as chips
- **Background Workouts** — workouts continue running when wrist drops (workout-processing mode)
- **Session Recovery** — orphaned HealthKit sessions are recovered after app crash or termination

### iPhone + Watch Sync

- **Template Sync** — templates created on iPhone automatically sync to Watch via WatchConnectivity
- **Exercise Sync** — custom exercises sync from iPhone to Watch
- **Planned Session Sync** — the current week's planned sessions (with target weights and reps) sync to Watch from the active progression plan
- **Live Workout Mirror** — iPhone shows a read-only banner of the active Watch workout in real-time
- **Workout History Sync** — completed Watch workouts transfer to iPhone for unified history
- **HealthKit Integration** — workouts saved to Apple Health with duration and calories
- **Plan Completion Sync** — when a planned session is completed on Watch, the progression plan on iPhone is updated automatically

---

## Progression Planning

A deterministic periodization engine that generates complete 12-week mesocycles from a handful of inputs. No randomness, no server calls — given the same inputs, the engine produces the same program every time. The entire plan lives on-device in SwiftData.

### How It Works

A 4-step wizard guides plan creation:

1. **Goal** — select a primary training goal (strength, hypertrophy, power, or general fitness). Each goal defines an intensity range and rep scheme.
2. **Program Type** — choose a periodization model: linear, daily undulating, weekly undulating, or block.
3. **Exercises** — pick exercises from the library. For each exercise, the app estimates your current 1RM from workout history (or you enter it manually).
4. **Schedule** — set training days per week (3–6). The engine assigns sessions to specific weekdays.

The engine then generates all 12 weeks upfront — every session, every exercise, every set, every target weight and rep count — organized into training blocks with structured deload weeks.

### Four Periodization Models

**Linear Periodization** — intensity ramps steadily across 3-week blocks with a deload every 4th week. Progression rate scales by training level: beginners +2.5%/week, intermediate +2.0%, advanced +1.5%. Volume (sets) is inversely proportional to intensity — more sets at lower intensity, fewer at higher. Advanced lifters skip scheduled deloads.

**Daily Undulating (DUP)** — three session types rotate within each week: hypertrophy (3×8–12 @ 65–75% 1RM), strength (4×3–5 @ 80–88%), and power (5×1–3 @ 88–95%). A 2% weekly overload multiplier is applied to midpoint intensity, clamped to each type's ceiling. Overload resets every 4-week block.

**Weekly Undulating (WUP)** — same three session types as DUP, but applied to entire weeks: week 1 is hypertrophy, week 2 strength, week 3 power, cycling. Same overload and deload logic.

**Block Periodization** — four distinct phases: Accumulation (4 weeks, 65–75% 1RM, high volume), Transmutation (3 weeks, 78–88%, moderate volume), Realization (2 weeks, 88–100%, low volume/high intensity), and Deload (1 week, 50%, recovery).

### 1RM Estimation

The engine estimates each exercise's 1RM from workout history:

- **Recent data** (0–6 months): used directly
- **Extended data** (6–12 months): 10% detraining penalty applied
- **Old data** (12+ months): ignored
- **Formulas**: reps = 1 → raw weight; reps 2–5 → Epley (`weight × (1 + reps/30)`); reps 6–15 → Brzycki (`weight × 36 / (37 − reps)`)
- All results rounded to nearest 2.5 kg

If no history exists, the user enters a known or estimated 1RM manually.

### Training Status Detection

The engine classifies lifters into three levels, which affect progression rates and deload scheduling:

| Level | Criteria |
|---|---|
| **Beginner** | < 3 months training AND < 50 workouts, or weekly frequency < 2.0 |
| **Intermediate** | ≥ 3 months or ≥ 50 workouts, weekly frequency ≥ 2.0 |
| **Advanced** | > 18 months AND > 200 workouts AND weekly frequency ≥ 3.0 |

Weekly frequency is calculated over the most recent 3 months using calendar week counts.

### Autoregulatory Progression (APRE)

After each completed session, target weights for the next session are adjusted based on actual performance on the final working set:

| Protocol | Reps vs Target | Adjustment |
|---|---|---|
| **3RM** | ≤1 rep | −5% |
| | 2–3 | 0% |
| | 4–5 | +2.5% |
| | ≥6 | +5% |
| **6RM** | ≤3 | −5% |
| | 4–5 | −2.5% |
| | 6–7 | 0% |
| | 8–9 | +2.5% |
| | ≥10 | +5% |
| **10RM** | ≤6 | −5% |
| | 7–8 | −2.5% |
| | 9–11 | 0% |
| | 12–14 | +2.5% |
| | ≥15 | +5% |

Weight rounding follows exercise type: upper-body compounds → nearest 2.5 kg, lower-body compounds → nearest 5 kg, isolation or < 40 kg → nearest 1 kg.

### Running 1RM Updates

The plan's stored 1RM values are updated after each session using EWMA (Exponential Weighted Moving Average):

- Smoothing: `new_1RM = 0.3 × estimated + 0.7 × current`
- Outlier rejection: skip updates where deviation > 15% from stored value
- Regression guard: downward updates only applied if new estimate < 95% of current (must be a real drop, not noise)

### Adaptive Adjustments

The engine continuously monitors for signals that warrant mid-plan changes:

- **Detraining** — gap since last workout: 10–21 days → 5% intensity reduction; 21–42 days → 10%; 42+ days → 15% + repeat current block
- **Performance decline** — estimated 1RM drops > 5% from stored value → deload signal
- **Beginner regression** — consecutive sessions with all sets below target: 2 misses → 5% load decrease; 3+ → 10% + repeat current week
- **Multi-signal deload** — if 2 or more deload triggers fire simultaneously → automatic 50% volume deload week

Contradictory proposals (increase + decrease on the same exercise) are filtered. Adjustments are prioritized (deload > repeat > regression) and capped at 3 per evaluation.

### Template Linking

Planned sessions can be linked to existing workout templates. When linked, the plan's target weights and reps are merged into the template's exercises — the template provides the exercise order, notes, and structure while the plan provides the progression-driven targets. Matching works by exercise ID with a case-insensitive name fallback for robustness.

### Apple Intelligence Integration

The progression module includes a two-tier coaching layer:

- **iOS 26+** (Apple Intelligence): routes coaching text through Apple's on-device Foundation Models for context-aware explanations tailored to the lifter's plan and performance
- **iOS 17–25**: falls back to structured template strings that adapt coaching tone by training level — encouraging and educational for beginners, data-driven for intermediates, concise and technical for advanced lifters

The AI-ready model layer includes structured inputs for natural language plan creation (goal descriptions, experience, equipment, injury limitations), workout note signal extraction (pain, fatigue, sleep quality), and post-workout narrative summaries. Plan creation source is tracked (structured wizard vs. natural language) for future NL-driven plan generation.

---

## Workout Analytics

All analytics run entirely on-device — no cloud, no AI API calls, no data leaves your phone. Every workout is converted into an 18-dimensional feature vector that captures volume, intensity, muscle targeting, and training patterns. As you log more workouts, the app progressively unlocks deeper insights.

### Progressive Unlocks

Analytics features are hidden until there's enough training data for them to be meaningful. The insights card doesn't appear on the dashboard until you're close to the first unlock. Each feature tells you how many more workouts you need.

| Workouts | What Unlocks | What It Does |
|---|---|---|
| 5 | **Quality Score** | Rates each workout 0-100 across volume, intensity, balance, and consistency |
| 5 | **Similar Workouts** | Finds past sessions that match your current training pattern |
| 10 | **Plateau Detection** | Spots exercises where progress has stalled for 2+ weeks |
| 20 | **Muscle Balance** | Checks if opposing muscle groups (chest/back, quads/hamstrings) are trained evenly |
| 20 | **Recommendations** | Suggests exercises based on training gaps, plateaus, and muscle imbalances |
| 50 | **Advanced Insights** | Deep analysis across your full training history |

### Under the Hood

**Vectorization** — each workout is encoded as an 18-dimensional vector capturing total volume, exercise count, intensity distribution, muscle group coverage, rest patterns, and more. Vectors are stored locally and searched using cosine similarity via Apple Accelerate/vDSP.

**Plateau Detection** — sliding-window coefficient of variation analysis on per-exercise volume. When volume flatlines, the app identifies the stall and suggests variations.

**Muscle Balance** — tracks antagonist muscle pair ratios and flags imbalances at three severity levels (mild/moderate/severe) with corrective exercise suggestions.

**Quality Score** — post-workout score across four dimensions: volume consistency, intensity (RPE), rest time pacing, and muscle balance.

---

## Calorie Estimation

Calorie tracking works differently depending on which device runs the workout.

### Apple Watch — Sensor-Based

When a workout runs on Apple Watch, calorie data comes directly from the hardware. The Watch uses its optical heart rate sensor, accelerometer, and gyroscope via `HKLiveWorkoutBuilder` to measure active energy burned in real time. These are the same sensor-fused calorie numbers that populate the Move ring. No equations are used — it's measured data from the wrist.

Live metrics (heart rate, active calories, elapsed time) are displayed during the workout and the final values are saved to HealthKit as an `HKWorkout` with `.traditionalStrengthTraining` activity type.

### iPhone — Equation-Based

When a workout is logged on iPhone without Watch involvement, calories are estimated using a research-based model with three components:

1. **MET-based session calories** — `MET × bodyWeight(kg) × hours`. MET values are sourced from the [2024 Compendium of Physical Activities (Herrmann et al.)](https://pacompendium.com/) and assigned per exercise category (barbell, kettlebell, machine, bodyweight, etc.) with separate values for compound and isolation movements. Active lifting is estimated at ~30 seconds per set; the remainder is standing rest at ~1.5 MET.

2. **Volume bonus** — based on [Lytle et al. (2019)](https://doi.org/10.1249/MSS.0000000000002111), a regression model (R²=0.75) for resistance exercise energy expenditure. Applies a coefficient of ~2.5 kcal per 1000 kg total volume moved.

3. **EPOC (Excess Post-Exercise Oxygen Consumption)** — 6-15% of session calories, scaled by average RPE when available, or compound exercise ratio as fallback.

The only personal data used is **body weight** (from HealthKit or user preferences). No age, height, or sex data is collected. Warmup sets are excluded. Results are cross-validated against [Joao et al. (2021)](https://doi.org/10.3390/app11125592) (~6 kcal/min average).

---

## Widgets and Live Activities

### Home Screen Widgets

- **Workout Summary** (small) — last workout name, relative date, exercise count
- **Weekly Progress** (medium) — progress ring showing workouts this week vs. goal, streak count, total workouts
- **Streak** (accessory circular + rectangular) — current streak and weekly progress for Lock Screen and StandBy

### Live Activity — Rest Timer

When a rest timer is running during a workout, a Live Activity appears on the Lock Screen and Dynamic Island:

- **Lock Screen** — circular progress ring with countdown, exercise name, and set number
- **Dynamic Island (expanded)** — "REST" label, countdown, progress bar with exercise/set info
- **Dynamic Island (compact)** — timer icon and countdown
- **Dynamic Island (minimal)** — timer icon

---

## Webhook Integration

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

---

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

---

## Privacy

Zero data collection. No analytics. No tracking. No account required. Everything lives on your iPhone and Apple Watch — unless you configure a webhook, in which case workout data is sent to the endpoint you specify.

---

## Architecture

```
StrengthTracker/
├── Shared/                  # Shared module (StrengthTrackerShared)
│   ├── Models/Domain/       # Domain models (Exercise, Workout, WorkoutTemplate, etc.)
│   │   ├── Analytics/       # Analytics domain (WorkoutVector, PlateauAnalysis, MuscleBalance)
│   │   └── Progression/     # Progression domain (ProgressionPlan, PlanExercise, TrainingBlock, PlannedSession)
│   ├── Persistence/         # SwiftData entities, mappers, repository implementations
│   ├── Repositories/        # Repository protocol definitions
│   ├── Services/            # ConnectivityManager, HealthKit, RestTimer, UserPreferences, Webhook, ExerciseSeeder, TemplateSeedService
│   │   ├── Analytics/       # Vectorizer, VectorSearch, PlateauDetection, MuscleBalance
│   │   └── Progression/     # ProgramDesignService, SessionExecutionService, AdaptiveAdjustmentService, TrainingStatusDetector
│   ├── ViewModels/          # Shared ViewModels (WorkoutVM, TemplateVM, AnalyticsVM, ProgressionPlanVM)
│   └── DI/                  # AppContainer (dependency injection)
├── iOS/                     # iPhone app (StrengthTrackeriOS)
│   ├── App/                 # App entry point, ContentView
│   └── Features/            # Dashboard, Workout, Templates, History, Progress, Progression, Settings
├── WatchApp/                # Watch app (StrengthTrackerWatch)
│   ├── App/                 # Watch app entry point
│   ├── Features/            # WorkoutList, ActiveWorkout, Summary
│   └── Services/            # WatchHealthKitManager
├── Tests/                   # Unit tests
├── Package.swift            # SPM package definition
└── project.yml              # XcodeGen project configuration
```

**Key patterns:**

- **DDD** — domain models, mappers, SwiftData entities, repositories, services, ViewModels
- **MVVM** — `@Observable` ViewModels with SwiftUI views
- **Repository** — protocol-based data access with SwiftData implementations
- **Mapper** — domain model ↔ SwiftData entity conversion (Float32 storage, Double computation for vectors)
- **DI Container** — `AppContainer` creates and caches all dependencies as singletons
- **Stateless Services** — analytics and progression services take all context as parameters, no mutable state
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
