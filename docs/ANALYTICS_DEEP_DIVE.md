# Analytics System Deep Dive

Exhaustive audit of the StrengthTracker analytics implementation.
Generated 2026-03-14 from 6 parallel exploration agents.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Data Flow](#2-data-flow)
3. [Volume Calculation](#3-volume-calculation)
4. [Weekly Comparison Logic](#4-weekly-comparison-logic)
5. [Widget System](#5-widget-system)
6. [Dashboard & Views](#6-dashboard--views)
7. [Analytics Services Inventory](#7-analytics-services-inventory)
8. [Domain Models](#8-domain-models)
9. [Bugs & Fixes](#9-bugs--fixes)
10. [Redundancies & Code Smells](#10-redundancies--code-smells)
11. [Recommendations](#11-recommendations)

---

## 1. Architecture Overview

The analytics system follows DDD principles with a service-oriented architecture:

```
┌─────────────────────────────────────────────────────┐
│                    UI Layer                          │
│  AnalyticsDashboardView  AdvancedInsightsView        │
│  InsightsCardView        ExerciseInsightsView         │
│  Widgets (4 iOS + 1 Watch)                           │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│               ViewModel Layer                        │
│  WorkoutAnalyticsViewModel   DashboardViewModel      │
│  ProgressViewModel           HistoryViewModel        │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│          Service Orchestrator                         │
│  WorkoutAnalyticsService (coordinates 17 services)   │
│  WidgetDataService (widget-specific aggregation)     │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│            17 Specialized Services                   │
│  PlateauDetection    MuscleBalance    TrainingLoad   │
│  OverloadTracking    DeloadDetection  Recovery       │
│  VolumeLandmarks     PhaseDetection   TrainingDrift  │
│  BlockComparison     AnomalyDetect    VectorSearch   │
│  WorkoutVectorizer   QualityScore     PersonalRecord │
│  ExerciseRecommend   InsightGenerator                │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│            Persistence Layer                         │
│  AnalyticsRepository  (SwiftData)                    │
│  WorkoutVectorEntity  (18-dim Float32 vector)        │
│  WorkoutVectorMapper  (Float32 ↔ Double conversion)  │
└─────────────────────────────────────────────────────┘
```

### Progressive Feature Unlock

| Phase | Workouts | Features Unlocked |
|-------|----------|-------------------|
| 1 | 1+ | Dashboard basics (counts, volume, duration, PRs) |
| 2 | 5+ | Quality score, similar workouts, strength trends, recommendations |
| 3 | 10-20 | Plateau detection (10), muscle balance (20), recovery timeline (20) |
| 4 | 19-50+ | Training load, deload, drift, phases, block comparison, anomalies |

Gated by `AnalyticsFeatureGate` (`Shared/Services/Analytics/AnalyticsFeatureGate.swift`).

---

## 2. Data Flow

### Workout Completion → Analytics

```
User completes workout
    │
    ├─→ WorkoutViewModel.completeWorkout()
    │       ├─→ PersonalRecordService.detectNewPRs()
    │       └─→ WorkoutAnalyticsService.ensureVectorized()
    │               └─→ WorkoutVectorizer.vectorize() → 18-dim vector
    │                       └─→ AnalyticsRepository.storeVector()
    │
    ├─→ WidgetDataService.buildWidgetData()
    │       ├─→ calculateVolumeTrend()
    │       ├─→ calculateStreak()
    │       ├─→ buildWeekCalendar()
    │       └─→ WidgetCenter.shared.reloadAllTimelines()
    │
    └─→ Next dashboard open:
            └─→ WorkoutAnalyticsViewModel.loadDashboardInsights()
                    └─→ WorkoutAnalyticsService.generateInsights()
                            └─→ All 17 services produce WorkoutInsights aggregate
```

### 18-Dimensional Workout Vector

Features extracted by `WorkoutVectorizer` (`Shared/Services/Analytics/WorkoutVectorizer.swift`):

| Index | Feature | Normalization |
|-------|---------|---------------|
| 0 | total_volume_norm | /50,000 |
| 1 | avg_weight_norm | /300 |
| 2 | avg_reps_norm | /30 |
| 3 | set_count_norm | /100 |
| 4 | exercise_diversity | raw (0-1) |
| 5 | duration_norm | /7200 |
| 6 | chest_ratio | muscle % |
| 7 | back_ratio | muscle % |
| 8 | legs_ratio | muscle % |
| 9 | shoulders_ratio | muscle % |
| 10 | arms_ratio | muscle % |
| 11 | core_ratio | muscle % |
| 12 | compound_ratio | compound% |
| 13 | avg_rpe | /10 |
| 14 | volume_vs_prev_7d | ratio |
| 15 | volume_vs_prev_30d | ratio |
| 16 | pr_count_norm | /10 |
| 17 | time_of_day_sin | sin(hour) |

Vectors are L2-normalized and stored as Float32 (72 bytes per vector).
Search uses Apple Accelerate vDSP dot product (<5ms for 2000 vectors).

---

## 3. Volume Calculation

### Formula: `weight × reps` per set (summed across sets/exercises)

**Set level** — `Shared/Models/Domain/WorkoutSet.swift:16-19`:
```swift
public var setVolume: Double {
    guard isCompleted, setType != .warmup else { return 0 }
    return (weight ?? 0) * Double(reps ?? 0)
}
```

**Exercise level** — `WorkoutSet.swift:45-47`:
```swift
public var exerciseVolume: Double {
    sets.reduce(0) { $0 + $1.setVolume }
}
```

**Workout level** — `Workout.swift:20-22` (simple) and `:25-35` (bodyweight-aware):
```swift
// Simple — used by widgets and dashboard
public var totalVolume: Double {
    exercises.reduce(0) { $0 + $1.exerciseVolume }
}

// Bodyweight-aware — used by vectorizer and some analytics
public func totalVolume(bodyWeightKg: Double) -> Double {
    exercises.reduce(0) { total, exercise in
        total + exercise.sets
            .filter(\.isCompleted)
            .filter { $0.setType != .warmup }
            .reduce(0) { sum, set in
                let w = set.weight ?? (exercise.exercise.exerciseType == .bodyweightReps ? bodyWeightKg : 0)
                return sum + w * Double(set.reps ?? 0)
            }
    }
}
```

### Is volume "smartly" implemented?

**Partially.** The base formula (`weight × reps`) is standard for resistance training volume. The system does have:
- Bodyweight substitution for bodyweight exercises (but only in `totalVolume(bodyWeightKg:)`, not the default `totalVolume`)
- Warmup set exclusion
- Per-muscle-group volume attribution with 70/30 primary/secondary split
- Intensity-Weighted Volume (IWV) for quality scoring: `reps × pct1RM × (RPE/10)`

**What's missing:**
- No tonnage normalization (absolute volume favors heavy lifters)
- No per-exercise relative volume (volume relative to historical max)
- The simple `totalVolume` (used by widgets/dashboard) ignores bodyweight entirely — see Bug #1

---

## 4. Weekly Comparison Logic

### The Core Bug: Calendar Week, Not Rolling Window

The weekly comparison uses **calendar week boundaries** (Monday 00:00 to Sunday 23:59), NOT a rolling 7-day window. On Monday, "this week" contains only Monday's data while "last week" has 7 full days.

**Buggy code in `WidgetDataService.calculateVolumeTrend()`** (`Shared/Services/WidgetDataService.swift:181-204`):
```swift
guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
    return (nil, nil)
}
let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!

let thisWeekVolume = workouts
    .filter { ($0.completedAt ?? .distantPast) >= thisWeekStart }  // ← open-ended
    .reduce(0.0) { $0 + $1.totalVolume }

let lastWeekVolume = workouts
    .filter {
        let date = $0.completedAt ?? .distantPast
        return date >= lastWeekStart && date < thisWeekStart       // ← full 7 days
    }
    .reduce(0.0) { $0 + $1.totalVolume }
```

**Same bug duplicated** in `iOS/App/StrengthTrackeriOS.swift:309-336` (`refreshWidgetData()`).

**Monday scenario:**
- This week: 1 day of data → e.g. 800 kg
- Last week: 7 days of data → e.g. 5000 kg
- Comparison: **-84%** "very down compared to last week"

**Correct code exists elsewhere** — `DashboardViewModel.workoutsInWeek()` (`:103-111`) uses `weekInterval.contains()` which properly bounds both start and end. `WorkoutHistory.workoutsInWeek()` (`:29-37`) also does it correctly.

### Week Start Day Inconsistency

Multiple places manually set `cal.firstWeekday = 2` (Monday), but not consistently:

| Location | Sets firstWeekday? |
|----------|-------------------|
| `DashboardViewModel.workoutsInWeek()` | Yes (2 = Monday) |
| `WidgetDataService.buildWeekCalendar()` | Yes (2 = Monday) |
| `WidgetDataService.calculateVolumeTrend()` | **NO** (uses system default) |
| `PlateauDetectionService.analyzePlateaus()` | **NO** (uses system default) |
| `OverloadTrackingService.computeOverloadTrends()` | **NO** (uses system default) |

On systems where `Calendar.current.firstWeekday` is Sunday (default in US), these services compute different week boundaries than the dashboard.

---

## 5. Widget System

### Widget Inventory

| Widget | Sizes | Refresh | Data Shown |
|--------|-------|---------|------------|
| TrainingHubWidget | small/medium/large | 5min (workout) / 30min (analytics) | Active workout state OR rotating highlights |
| WorkoutSummaryWidget | small | 30min | Last workout name, date, exercise count |
| WeeklyProgressWidget | medium | 30min | Progress ring, streak, total workouts |
| StreakAccessoryWidget | accessoryCircular/Rect | 1hr | Streak, weekly progress |
| WatchRestTimerWidget | native | dynamic | Rest timer state |

### Why the Widget Shows Different Things (Streaks vs Quality)

The **TrainingHubWidget** rotates through pre-computed **highlights** using WidgetKit's timeline mechanism:

1. `WidgetDataService.buildWidgetData()` stores the top 3 `WidgetHighlight` entries
2. `TrainingHubProvider.getTimeline()` creates multiple timeline entries, each with a different `highlightIndex`
3. Entries are spaced **30 minutes apart** (line 44)
4. The view selects: `entry.data.highlights[entry.highlightIndex % highlights.count]`

**Highlight sources** (priority order):
1. Analytics insights (PRs, plateaus, improvements, warnings) from `WorkoutAnalyticsService`
2. **Volume trend supplement** — added if fewer than 3 highlights exist (`StrengthTrackeriOS.swift:305-336`)
3. **Quality score supplement** — added if still fewer than 3 (`StrengthTrackeriOS.swift:340-347`)

So the widget is NOT random — it deterministically rotates through whatever highlights the analytics system generated. But because the highlight list changes based on workout history, feature unlock state, and supplementary fill logic, the user sees different metrics at different times.

### Widget Data Flow

```
App enters foreground (.active scenePhase)
    │
    └─→ ContentViewWrapper.refreshWidgetData()
            │
            ├─→ Process pending widget completions
            ├─→ Fetch all workouts from repository
            ├─→ Get analytics highlights (ViewModel cache OR generate)
            ├─→ Fetch active progression plan → next planned session
            ├─→ Supplement highlights if < 3 (volume trend, quality score)
            │
            └─→ WidgetDataService.buildWidgetData()
                    ├─→ Calculate streak (consecutive training days)
                    ├─→ Build 7-day calendar (Mon-Sun)
                    ├─→ Calculate volume trend (this week vs last week)
                    ├─→ Build active workout state
                    │
                    └─→ Write JSON to App Group UserDefaults
                            └─→ WidgetCenter.shared.reloadAllTimelines()
```

**App Group**: `group.se.gunnarstrandberg.hellbent.shared`
**UserDefaults key**: `widget_data`

---

## 6. Dashboard & Views

### View Hierarchy

```
ContentView
└─→ InsightsCardView (compact card, top 1-2 insights)
        └─→ NavigationLink → AnalyticsDashboardView (full dashboard)
                ├─→ Workout count
                ├─→ Feature roadmap (unlock progress)
                ├─→ Quality Score gauge (5+ workouts)
                ├─→ Muscle Balance bars + imbalance warnings (20+ workouts)
                ├─→ Plateau Warnings (10+ workouts)
                ├─→ Exercise Recommendations
                └─→ AdvancedInsightsCardView (19+ workouts)
                        └─→ NavigationLink → AdvancedInsightsView
                                ├─→ Smart Highlights
                                ├─→ Training Load (ACWR gauge)
                                ├─→ Training Phase + phase history timeline
                                ├─→ Volume Landmarks (MEV/MRV per muscle)
                                ├─→ Recovery Status per muscle group
                                ├─→ Progressive Overload trends per exercise
                                ├─→ Training Drift (dimension deltas)
                                ├─→ Deload Recommendation
                                ├─→ Block Comparison (4-week blocks)
                                └─→ Anomalous Workouts
```

### Per-Workout Views

- **WorkoutQualityScoreView**: Score gauge + volume/intensity/pacing breakdown (in WorkoutDetailView)
- **ExerciseInsightsView**: Per-exercise plateau status + recommendations (in ExerciseDetailView)
- **SimilarWorkoutsView**: List of similar past workouts with similarity scores

### No Time Period Controls

There are **no user-facing toggles** for time windows. All periods are hardcoded:
- Volume trend: calendar week
- Muscle balance: 4 weeks
- Plateau detection: 4-week sliding window
- Recovery: 2 weeks
- Training drift: 14 days recent vs 15-45 days baseline
- Block comparison: 2×4-week blocks
- Best e1RM: 6 months
- Quality score volume component: 12 weeks

---

## 7. Analytics Services Inventory

All services in `Shared/Services/Analytics/`:

| Service | Type | Description | Min Data |
|---------|------|-------------|----------|
| `WorkoutAnalyticsService` | @MainActor class | Orchestrator, coordinates all services | - |
| `WorkoutVectorizer` | @MainActor class | Extracts 18-dim feature vector from workout | - |
| `VectorSearchService` | @MainActor class | Cosine similarity search (Accelerate vDSP) | - |
| `WorkoutQualityScoreService` | @MainActor class | 4-component quality score (0-100) | 5 workouts |
| `PlateauDetectionService` | @MainActor class | CV-based stall detection per exercise | 4 weeks |
| `MuscleBalanceService` | @MainActor class | 6 antagonist pair analysis | - |
| `ExerciseRecommendationService` | @MainActor class | 3-tier exercise recommendations | - |
| `RecoveryEstimationService` | @MainActor class | Per-muscle recovery status | - |
| `VolumeLandmarkService` | @MainActor class | MEV/MRV per muscle group | - |
| `TrainingLoadService` | static enum | EWMA acute/chronic workload ratio | 4 workouts |
| `OverloadTrackingService` | static enum | Weekly e1RM linear regression | 4 weeks |
| `DeloadDetectionService` | static enum | 5-trigger deload recommendation | 6 workouts |
| `PhaseDetectionService` | @MainActor class | Weekly phase classification | 4 weeks |
| `TrainingDriftService` | @MainActor class | Recent vs baseline vector drift | 2 recent + 3 baseline |
| `BlockComparisonService` | @MainActor class | 4-week block centroid comparison | 8 weeks |
| `AnomalyDetectionService` | @MainActor class | EWMA centroid deviation detection | 5 vectors |
| `PersonalRecordService` | class | PR detection (5 types) | - |

### Quality Score Components (25 pts each)

| Component | Method | Logic |
|-----------|--------|-------|
| Volume | `computeVolumeScore()` | Per-muscle deviation from 12-week rolling average (±20% = 100) |
| Intensity | `computeIntensityScore()` | Set e1RM as % of exercise best e1RM (6mo) |
| Consistency | `computeConsistencyScore()` | Time-per-set: 60-180s=100, 45-240s=80, 30-300s=50 |
| Balance | `computeBalanceScore()` | IWV ratio across 6 antagonist pairs |

### Training Load (ACWR)

- Acute EWMA lambda: 0.25
- Chronic EWMA lambda: 0.069
- Zones: <0.6 (undertraining), 0.6-1.3 (optimal), 1.3-1.5 (caution), >1.5 (danger)

### 1RM Formulas

Two different formulas used:
- **Epley**: `weight × (1 + reps/30)` — used for reps ≤ 5 and in PersonalRecordService
- **Brzycki**: `weight × 36 / (37 - reps)` — used for reps > 5 in AnalyticsCalculations

---

## 8. Domain Models

All in `Shared/Models/Domain/Analytics/`:

| Model | Purpose |
|-------|---------|
| `WorkoutInsights` | Aggregate root for all dashboard analytics |
| `WorkoutVector` | 18-dim L2-normalized feature vector |
| `WorkoutQualityScore` | 4-component quality metric (0-100) |
| `TrainingLoad` | ACWR + acute/chronic loads + per-muscle ACWR |
| `OverloadTrend` | Per-exercise weekly e1RM regression |
| `PlateauAnalysis` | Stalled weeks + CV + recommendation |
| `MuscleBalance` | Per-muscle volumes + 6-pair imbalance analysis |
| `RecoveryPattern` | Per-muscle recovery hours + status |
| `OptimalVolumeRange` | MEV/MRV per muscle + current status |
| `ExerciseRecommendation` | Recommended exercise with reason + confidence |
| `DeloadRecommendation` | Urgency score + 5 triggers |
| `TrainingPhase` | Current phase + phase history timeline |
| `TrainingDrift` | Overall drift score + per-dimension deltas |
| `BlockComparison` | 4-week block similarity + summary |
| `WorkoutAnomaly` | Anomaly score + deviating dimensions |
| `AnalyticsHighlight` | Smart insight (PR/streak/milestone/improvement/warning) |
| `SimilarWorkout` | Match with similarity score + features |

Persistence: `WorkoutVectorEntity` (SwiftData, Float32 storage, `@Attribute(.unique)` on id).

---

## 9. Bugs & Fixes

### BUG 1 (CRITICAL): Weekly Volume Shows Dramatic Drop Every Monday

**Symptom:** Widget and dashboard show "very down compared to last week" every Monday.

**Root Cause:** Volume comparison uses calendar week boundaries. On Monday, "this week" has 1 day of data vs "last week" with 7 full days.

**Affected Files:**
- `Shared/Services/WidgetDataService.swift:181-204` — `calculateVolumeTrend()`
- `iOS/App/StrengthTrackeriOS.swift:309-336` — `refreshWidgetData()`

**Fix:** Replace calendar-week comparison with a rolling 7-day window:

```swift
// BEFORE (buggy):
let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
let thisWeekVolume = workouts.filter { ($0.completedAt ?? .distantPast) >= thisWeekStart }

// AFTER (rolling window):
let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now)!

let thisWindowVolume = workouts
    .filter { let d = $0.completedAt ?? .distantPast; return d >= sevenDaysAgo && d <= now }
    .reduce(0.0) { $0 + $1.totalVolume }

let lastWindowVolume = workouts
    .filter { let d = $0.completedAt ?? .distantPast; return d >= fourteenDaysAgo && d < sevenDaysAgo }
    .reduce(0.0) { $0 + $1.totalVolume }
```

---

### BUG 2 (CRITICAL): Bodyweight Exercises Have Zero Volume in Multiple Analytics

**Symptom:** Users who primarily do bodyweight exercises (pull-ups, push-ups, dips) see zero volume in muscle balance analysis, misleadingly perfect balance scores, and understated widget volume.

**Root Cause:** `ExerciseSet.setVolume` returns `(weight ?? 0) * reps`. For bodyweight exercises where `weight` is nil, volume is always 0. The bodyweight-aware `Workout.totalVolume(bodyWeightKg:)` exists but is NOT used by:
- `MuscleBalanceService.analyzeBalance()` — uses `exerciseVolume` (zero for bodyweight)
- `WidgetDataService.calculateVolumeTrend()` — uses `totalVolume` (zero for bodyweight)
- `StrengthTrackeriOS.refreshWidgetData()` — uses `totalVolume` (zero for bodyweight)
- `CalorieEstimationService` — uses `weight ?? 0` (zero for bodyweight)

**Correctly handled by:**
- `WorkoutVectorizer.calculateTotalVolume()` — uses bodyweight fallback
- `Workout.totalVolume(bodyWeightKg:)` — uses bodyweight fallback

**Fix:** Pass `bodyWeightKg` into volume calculations everywhere, or make `setVolume` accept an optional bodyweight parameter. At minimum, update `MuscleBalanceService` and `WidgetDataService` to use the bodyweight-aware method.

---

### BUG 3 (HIGH): Week Start Day Not Consistently Set to Monday

**Symptom:** On systems with Sunday as default first weekday (US default), analytics services compute different week boundaries than the dashboard.

**Affected Services:**
- `WidgetDataService.calculateVolumeTrend()` — no firstWeekday override
- `PlateauDetectionService.analyzePlateaus()` — no firstWeekday override
- `OverloadTrackingService.computeOverloadTrends()` — no firstWeekday override

**Fix:** Create a shared calendar utility:
```swift
extension Calendar {
    static var mondayStart: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }
}
```
Use `Calendar.mondayStart` everywhere instead of `Calendar.current`.

---

### BUG 4 (HIGH): Widget vs Dashboard Use Different Volume Calculations

**Symptom:** Widget volume numbers may not match what the dashboard or analytics show.

**Root Cause:** Widget uses `Workout.totalVolume` (no bodyweight fallback), while quality score and vectorizer use bodyweight-aware volume. Additionally, WidgetDataService and StrengthTrackeriOS compute volume trends independently with duplicated (and both buggy) code.

**Fix:** Centralize volume trend computation in `WidgetDataService` only (remove duplicate in `StrengthTrackeriOS.swift`), and use the bodyweight-aware volume method.

---

### BUG 5 (MEDIUM): Calorie Estimation Includes Warmup Sets

**File:** `Shared/Services/CalorieEstimationService.swift:76`

**Root Cause:**
```swift
let exerciseVolumeKg = completedSets.reduce(0.0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) }
```
Does not filter `setType != .warmup`, inflating calorie estimates. Also uses `weight ?? 0` instead of bodyweight fallback.

**Fix:** Add `.filter { $0.setType != .warmup }` before reduce, and handle bodyweight exercises.

---

### BUG 6 (MEDIUM): Race Condition in Quality Score Loading

**File:** `Shared/ViewModels/WorkoutAnalyticsViewModel.swift:120-134`

**Root Cause:** Workouts are fetched independently for quality score computation, separate from the insight generation fetch. If a workout is saved between the two fetches, quality score may be computed on a different "latest" workout than the one used for insights.

**Fix:** Fetch workouts once at the start of `loadDashboardInsights()` and pass through to quality score computation.

---

### BUG 7 (LOW): `completedAt` vs `startedAt` Inconsistency

Different analytics use different timestamps for date filtering:
- Widget volume trend: `completedAt ?? .distantPast`
- Dashboard week filter: `startedAt`
- Plateau detection: `startedAt`

For incomplete workouts, this could group them into different weeks depending on the code path.

---

## 10. Redundancies & Code Smells

### REDUNDANCY 1: Volume Trend Calculated in Two Places

The weekly volume trend (this week vs last week) is computed independently in:
1. `WidgetDataService.calculateVolumeTrend()` (`:181-204`)
2. `StrengthTrackeriOS.refreshWidgetData()` (`:309-336`)

Both have the same calendar-week bug. The second one adds supplementary highlights based on the trend. These should be unified.

### REDUNDANCY 2: Muscle Group Attribution Logic Duplicated 4+ Times

The 70% primary / 30% secondary muscle split is copy-pasted in:
1. `WorkoutVectorizer.calculateMuscleGroupVolumes()` (`:134-142`)
2. `WorkoutQualityScoreService.computeVolumeScore()` (`:118-125`)
3. `MuscleBalanceService.analyzeBalance()` (`:47-55`)
4. `WorkoutQualityScoreService.computeMuscleGroupIWV()` (`:84-91`)

**Fix:** Extract to `AnalyticsCalculations.attributeVolume(volume:, primaryMuscle:, secondaryMuscles:)`.

### REDUNDANCY 3: `computeCentroid()` Duplicated in 4 Services

Identical centroid computation exists in:
1. `TrainingDriftService.computeCentroid()`
2. `PhaseDetectionService.computeCentroid()`
3. `BlockComparisonService.computeCentroid()`
4. `AnomalyDetectionService` (inline EWMA centroid)

**Fix:** Move to `VectorSearchService.computeCentroid()`.

### REDUNDANCY 4: Best e1RM Map Built in Multiple Places

`buildBestE1RMMap()` is defined in both:
1. `AnalyticsCalculations.buildBestE1RMMap()` (`:15-38`)
2. `WorkoutQualityScoreService.buildBestE1RMMap()` — local version

### CODE SMELL: Hardcoded Magic Numbers

| Value | Location | Purpose |
|-------|----------|---------|
| 50,000 | WorkoutVectorizer | maxVolume normalization constant |
| 300 | WorkoutVectorizer | maxWeight normalization constant |
| 0.25 / 0.069 | TrainingLoadService | EWMA lambdas |
| 1.5 / 2.0 | MuscleBalanceService | Imbalance thresholds |
| 0.10 | PlateauDetectionService | plateauThresholdCV |
| 1.05 | PlateauDetectionService | minImprovementThreshold |
| 12 weeks | WorkoutQualityScoreService | Volume score lookback window |
| 6 months | AnalyticsCalculations | Best e1RM window |
| 14 / 45 days | TrainingDriftService | Recent/baseline windows |

None of these are configurable. Consider moving to a `AnalyticsConfig` struct.

### CODE SMELL: Muscle Balance Returns Perfect Score for Broken Data

When `MuscleBalanceService` finds no imbalances (which happens when all volumes are zero — e.g., bodyweight-only users), it returns `1.0` (perfect balance). This is technically correct but misleading when the data itself is invalid.

---

## 11. Recommendations

### Priority 1: Fix Weekly Volume Comparison
- Switch to rolling 7-day window OR normalize partial-week data
- Fix in both `WidgetDataService` and `StrengthTrackeriOS`
- This is the most user-visible bug

### Priority 2: Fix Bodyweight Volume
- Pass `bodyWeightKg` through the widget and dashboard volume pipelines
- Affects muscle balance, widget volume, calorie estimation

### Priority 3: Standardize Calendar Configuration
- Create `Calendar.mondayStart` extension
- Replace all ad-hoc `cal.firstWeekday = 2` and bare `Calendar.current` usage

### Priority 4: Deduplicate Volume Trend Logic
- Single source of truth in `WidgetDataService`
- Remove duplicate in `StrengthTrackeriOS.refreshWidgetData()`

### Priority 5: Extract Shared Analytics Utilities
- Muscle group attribution → `AnalyticsCalculations`
- Vector centroid → `VectorSearchService`
- Calendar helpers → shared extension

### Priority 6: Add Time Period Controls
- Let users toggle between "this week" and "last 7 days"
- Let users choose analytics lookback window

---

## File Index

### Domain Models (`Shared/Models/Domain/Analytics/`)
- `AnalyticsHighlight.swift`
- `BlockComparison.swift`
- `DeloadRecommendation.swift`
- `ExerciseRecommendation.swift`
- `MuscleBalance.swift`
- `OptimalVolumeRange.swift`
- `OverloadTrend.swift`
- `PlateauAnalysis.swift`
- `RecoveryPattern.swift`
- `SimilarWorkout.swift`
- `TrainingDrift.swift`
- `TrainingLoad.swift`
- `TrainingPhase.swift`
- `WorkoutAnomaly.swift`
- `WorkoutInsights.swift`
- `WorkoutQualityScore.swift`
- `WorkoutVector.swift`

### Services (`Shared/Services/Analytics/`)
- `AnalyticsCalculations.swift`
- `AnalyticsError.swift`
- `AnalyticsFeatureGate.swift`
- `AnomalyDetectionService.swift`
- `AppleIntelligenceInsightGenerator.swift`
- `BlockComparisonService.swift`
- `DeloadDetectionService.swift`
- `ExerciseRecommendationService.swift`
- `InsightTextGenerating.swift`
- `MuscleBalanceService.swift`
- `OverloadTrackingService.swift`
- `PhaseDetectionService.swift`
- `PlateauDetectionService.swift`
- `RecoveryEstimationService.swift`
- `TemplateInsightGenerator.swift`
- `TrainingDriftService.swift`
- `TrainingLoadService.swift`
- `VolumeLandmarkService.swift`
- `VectorSearchService.swift`
- `WorkoutAnalyticsService.swift`
- `WorkoutQualityScoreService.swift`
- `WorkoutVectorizer.swift`

### Persistence
- `Shared/Persistence/SwiftData/Entities/WorkoutVectorEntity.swift`
- `Shared/Persistence/SwiftData/Repositories/SwiftDataAnalyticsRepository.swift`
- `Shared/Persistence/Mappers/WorkoutVectorMapper.swift`
- `Shared/Repositories/Protocols/AnalyticsRepository.swift`

### ViewModels
- `Shared/ViewModels/WorkoutAnalyticsViewModel.swift`
- `Shared/ViewModels/DashboardViewModel.swift`
- `Shared/ViewModels/ProgressViewModel.swift`
- `Shared/ViewModels/HistoryViewModel.swift`

### Views
- `iOS/Features/Analytics/Views/AnalyticsDashboardView.swift`
- `iOS/Features/Analytics/Views/AdvancedInsightsView.swift`
- `iOS/Features/Analytics/Views/AdvancedInsightsCardView.swift`
- `iOS/Features/Analytics/Views/InsightsCardView.swift`
- `iOS/Features/Analytics/Views/ExerciseInsightsView.swift`
- `iOS/Features/Analytics/Views/WorkoutQualityScoreView.swift`
- `iOS/Features/Analytics/Views/SimilarWorkoutsView.swift`

### Widget
- `iOS/WidgetExtension/TrainingHubWidget.swift`
- `iOS/WidgetExtension/TrainingHubViews.swift`
- `iOS/WidgetExtension/WorkoutSummaryWidget.swift`
- `iOS/WidgetExtension/WeeklyProgressWidget.swift`
- `iOS/WidgetExtension/StreakAccessoryWidget.swift`
- `iOS/WidgetExtension/WidgetIntents.swift`
- `Shared/Models/Domain/WidgetData.swift`
- `Shared/Services/WidgetDataService.swift`

### Widget Data Refresh
- `iOS/App/StrengthTrackeriOS.swift` (ContentViewWrapper.refreshWidgetData, line ~256)
