# HellBentIron Analytics System — Complete Reference

> Exhaustive documentation of every analytics service, equation, data model, UI element, and user-facing text string in the StrengthTracker analytics system.
> Generated 2026-03-22. Updated 2026-03-29 (M1-M9 coaching insights).

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Progressive Feature Unlocking](#2-progressive-feature-unlocking)
3. [Data Pipeline — From Workout to Insight](#3-data-pipeline)
4. [Core Analytics Services & Equations](#4-core-analytics-services)
   - 4.1 WorkoutVectorizer
   - 4.2 VectorSearchService
   - 4.3 PlateauDetectionService
   - 4.4 MuscleBalanceService
   - 4.5 ExerciseRecommendationService
   - 4.6 AnalyticsCalculations (shared formulas)
5. [Advanced Insights Services & Equations](#5-advanced-insights-services)
   - 5.1 TrainingLoadService (ACWR)
   - 5.2 OverloadTrackingService
   - 5.3 DeloadDetectionService
   - 5.4 VolumeLandmarkService
   - 5.5 RecoveryEstimationService
   - 5.6 TrainingDriftService
   - 5.7 PhaseDetectionService
   - 5.8 BlockComparisonService
   - 5.9 AnomalyDetectionService
   - 5.10 WorkoutQualityScoreService
   - 5.11 CoachingInsightService
   - 5.12 WeightSuggestionService
   - 5.13 AdherenceAnalysisService
   - 5.14 TrajectoryAnalysisService
   - 5.15 WorkoutArchetypeService
   - 5.16 ChangePointDetectionService
   - 5.17 AchievementTrackingService
6. [Progression & Coaching Services](#6-progression--coaching-services)
   - 6.1 TrainingStatusDetector
   - 6.2 ProgramDesignService
   - 6.3 SessionExecutionService
   - 6.4 AdaptiveAdjustmentService
   - 6.5 PlanAnalyticsService
   - 6.6 PersonalRecordService
   - 6.7 CalorieEstimationService
7. [Data Models — What Is Stored](#7-data-models)
8. [UI/UX — Exact Wordings & Presentation](#8-uiux--exact-wordings--presentation)
   - 8.1 InsightsCardView (Dashboard Card)
   - 8.2 AnalyticsDashboardView (Full Analytics Page)
   - 8.3 AdvancedInsightsCardView (Compact Summary)
   - 8.4 AdvancedInsightsView (Full Detail)
   - 8.5 ExerciseInsightsView
   - 8.6 SimilarWorkoutsView
   - 8.7 WorkoutQualityScoreView
   - 8.8 PostWorkoutSummaryView
   - 8.9 PreWorkoutContextCard
   - 8.10 WeeklyDigestCard
   - 8.11 Color Coding Reference
   - 8.12 Number Formatting Rules
9. [Recommendations & Insights — How They Are Created and Presented](#9-recommendations--insights)
   - 9.1 Advanced Highlights (19+ workouts)
   - 9.2 Early Highlights (5–18 workouts)
   - 9.3 Plateau Recommendations
   - 9.4 Muscle Imbalance Recommendations
   - 9.5 Exercise Recommendations
   - 9.6 Deload Recommendations
   - 9.7 Coaching Explanations (Plan Adjustments)
   - 9.8 Post-Workout Summaries
   - 9.9 Drift & Block Comparison Text
   - 9.10 Phase Descriptions
   - 9.11 Post-Workout Coaching Bullet Selection
   - 9.12 Weekly Digest Top Insight Selection
   - 9.13 Exercise Hint Priority
10. [Apple Intelligence Integration](#10-apple-intelligence-integration)
11. [Key Thresholds & Constants](#11-key-thresholds--constants)

---

## 1. Architecture Overview

The analytics system is a **stateless, service-oriented pipeline** built on MVVM + Repository + DDD patterns. All services are `@MainActor` and `Sendable`.

```
Workout Completed
    │
    ▼
WorkoutVectorizer ──► 18-dim L2-normalized feature vector
    │                    stored in WorkoutVectorEntity (SwiftData)
    ▼
WorkoutAnalyticsService.generateInsights()
    │
    ├─ Phase 2 (5+ workouts)
    │   ├─ PlateauDetectionService
    │   ├─ MuscleBalanceService
    │   └─ ExerciseRecommendationService
    │
    ├─ Phase 3 (all workouts)
    │   ├─ RecoveryEstimationService
    │   └─ VolumeLandmarkService
    │
    ├─ Phase 4 (19+ workouts — "Advanced Insights")
    │   ├─ TrainingLoadService (ACWR)
    │   ├─ OverloadTrackingService
    │   ├─ DeloadDetectionService
    │   ├─ TrainingDriftService
    │   ├─ PhaseDetectionService
    │   ├─ BlockComparisonService
    │   ├─ AnomalyDetectionService
    │   └─ InsightTextGenerator (Template or Apple Intelligence)
    │
    └─ Phase 5 (Coaching — all workouts, progressive content)
        ├─ CoachingInsightService (post-workout debrief, weekly digest, exercise hints, muscle neglect)
        ├─ WeightSuggestionService (e1RM-based suggestions, effort creep detection)
        ├─ AdherenceAnalysisService (frequency, streaks, dropout risk)
        ├─ TrajectoryAnalysisService (velocity/acceleration in vector space)
        ├─ WorkoutArchetypeService (k-means clustering, fingerprinting)
        ├─ ChangePointDetectionService (CUSUM, time-of-day analysis)
        └─ AchievementTrackingService (badges, volume-response curves)
    │
    ▼
WorkoutInsights aggregate ──► WorkoutAnalyticsViewModel ──► UI Views
```

**Key architectural decisions:**
- **Stateless services** — no mutable state; same inputs always produce same outputs
- **Vector-powered** — 18-dimensional workout vectors enable similarity search, drift detection, phase detection, block comparison, and anomaly detection
- **Progressive disclosure** — features unlock as workout count grows
- **Apple Intelligence optional** — `FoundationModels` enhances text on iOS 26+; templates are the fallback

---

## 2. Progressive Feature Unlocking

`AnalyticsFeatureGate` gates 24 features behind workout count thresholds:

| Phase | Threshold | Features Unlocked |
|-------|-----------|-------------------|
| **1** | 1 workout | Post-Workout Debrief (progressive content) |
| **2** | 5+ workouts | Similar Workouts, Quality Score, Strength Trends, Exercise Recommendations, Weight Suggestions, Weekly Digest, Pre-Workout Context |
| **3a** | 10+ workouts | Plateau Detection, Effort Creep Warning, Exercise Hints, Archetype Clustering, Achievements |
| **3b** | 15+ workouts | Sequence Prediction, Workout Suggestion |
| **3c** | 19+ workouts | Muscle Balance, Advanced Insights, Trajectory Analysis, Training Fingerprint, Muscle Neglect |
| **3d** | 20+ workouts | Recovery Timeline, Time-of-Day Analysis, Change Point Detection |
| **4** | 50+ workouts | Volume-Response Curves |

**All 24 features with display names:**

| Feature | Threshold | Display Name | Description Shown |
|---------|:-:|-------------|-------------------|
| postWorkoutDebrief | 1 | "Post-Workout Debrief" | "Summary and coaching bullets after every workout" |
| weightSuggestion | 5 | "Weight Suggestions" | "Smart weight recommendations based on your recent performance" |
| weeklyDigest | 5 | "Weekly Digest" | "Week-over-week training comparison" |
| similarWorkouts | 5 | "Similar Workouts" | "Find past workouts that match your current session" |
| qualityScore | 5 | "Quality Score" | "Rate each workout on volume, intensity, and balance" |
| strengthTrends | 5 | "Strength Trends" | "Track strength changes over time per exercise" |
| exerciseRecommendations | 5 | "Recommendations" | "Get exercise suggestions based on your training gaps" |
| preWorkoutContext | 5 | "Pre-Workout Context" | "Recovery status, ACWR gauge, and adherence stats before you start" |
| effortCreepWarning | 10 | "Effort Creep Warning" | "Detect when RPE rises without strength gains" |
| exerciseHints | 10 | "Exercise Hints" | "Inline coaching tips per exercise" |
| plateauDetection | 10 | "Plateau Detection" | "Spot exercises where progress has stalled" |
| archetypeClustering | 10 | "Archetype Clustering" | "Discover your workout patterns via k-means clustering" |
| achievements | 10 | "Achievements" | "Earn badges for training milestones" |
| sequencePrediction | 15 | "Sequence Prediction" | "Predict your next workout type" |
| workoutSuggestion | 15 | "Workout Suggestion" | "Get a suggested workout based on archetype analysis" |
| muscleBalance | 19 | "Muscle Balance" | "Check if opposing muscle groups are trained evenly" |
| advancedInsights | 19 | "Advanced Insights" | "Deep analysis across your full training history" |
| trajectoryAnalysis | 19 | "Trajectory Analysis" | "Velocity and acceleration of training changes" |
| trainingFingerprint | 19 | "Training Fingerprint" | "Your unique training pattern signature" |
| muscleNeglect | 19 | "Muscle Neglect" | "Detect declining volume for specific muscle groups" |
| recoveryTimeline | 20 | "Recovery Timeline" | "Optimal rest days between sessions" |
| timeOfDayAnalysis | 20 | "Time-of-Day Analysis" | "Find your best training window" |
| changePointDetection | 20 | "Change Point Detection" | "Detect significant shifts in your training pattern" |
| volumeResponseCurve | 50 | "Volume-Response Curves" | "Personal MEV/MAV/MRV derived from your own data" |

**Unlock progress text:** `"Complete [X] more workout(s) to unlock [Feature Name]"`

---

## 3. Data Pipeline

### From workout completion to user-visible insight:

```
1. User completes workout
2. WorkoutVectorizer.vectorize() → 18-dim vector
3. Vector stored in SwiftData (WorkoutVectorEntity, 72 bytes Float32)
4. WorkoutAnalyticsService.generateInsights() called
   a. Fetch all completed workouts
   b. Run applicable services based on workout count
   c. Generate insight text (template or AI)
   d. Assemble WorkoutInsights aggregate
5. CoachingInsightService.generatePostWorkoutDebrief() called
   a. Compute basic stats (duration, volume, sets, PRs)
   b. Find most similar past session via vector cosine similarity
   c. Generate priority-ranked coaching bullets (max 3)
   d. Optionally enhance bullet text via Apple Intelligence
   e. Assemble PostWorkoutDebrief → PostWorkoutSummaryView sheet
6. WorkoutAnalyticsViewModel receives aggregate
7. UI views render from ViewModel properties
8. Widget data refreshed via WidgetDataService

Pre-workout path:
1. User opens ActiveWorkoutView (with 5+ workouts)
2. RecoveryEstimationService → per-muscle recovery status
3. TrainingLoadService → ACWR and load zone
4. AdherenceAnalysisService → gap, frequency, streak, dropout risk
5. PreWorkoutContextCard renders recovery dots, ACWR gauge, adherence stats
```

### Caching:
- **In-memory vector cache**: `[UUID: WorkoutVector]`, valid for 300 seconds
- **Insights reload throttle**: Skips reload if last load was within 60 seconds (unless forced)
- **Batch migration**: First analytics access vectorizes all existing workouts (one-time, keyed by UserDefaults `analytics_migration_complete`)

---

## 4. Core Analytics Services

### 4.1 WorkoutVectorizer

**File:** `Shared/Services/Analytics/WorkoutVectorizer.swift`

Converts a workout into an 18-dimensional L2-normalized feature vector for cosine similarity computation.

#### 18 Feature Dimensions

| Dim | Feature Name | Formula | Normalization |
|-----|-------------|---------|---------------|
| 0 | `total_volume_norm` | `Σ(weight × reps)` for all completed non-warmup sets | `÷ 20,000 kg` |
| 1 | `avg_weight_norm` | Mean weight across all sets | `÷ 150 kg` |
| 2 | `avg_reps_norm` | Mean reps across all sets | `÷ 30` |
| 3 | `set_count_norm` | Total completed non-warmup sets | `÷ 100` |
| 4 | `exercise_diversity` | Count of unique exercises | `÷ 15` |
| 5 | `duration_norm` | Workout duration in seconds | `÷ 5,400 (90min)` |
| 6 | `chest_ratio` | Chest volume ÷ total volume | 0–1 |
| 7 | `back_ratio` | Back volume ÷ total volume | 0–1 |
| 8 | `legs_ratio` | (Quad+Ham+Glute+Calf) ÷ total | 0–1 |
| 9 | `shoulders_ratio` | Shoulder volume ÷ total | 0–1 |
| 10 | `arms_ratio` | (Biceps+Triceps) ÷ total | 0–1 |
| 11 | `core_ratio` | Core volume ÷ total | 0–1 |
| 12 | `compound_ratio` | Barbell exercises ÷ total exercises | 0–1 |
| 13 | `avg_rpe` | Mean RPE across sets | `÷ 10` |
| 14 | `volume_vs_prev_7d` | `clamp((vol − avg7d) / avg7d, −1, 1)` | −1 to 1 |
| 15 | `volume_vs_prev_30d` | `clamp((vol − avg30d) / avg30d, −1, 1)` | −1 to 1 |
| 16 | `pr_count_norm` | Personal records in this workout | `÷ 10` |
| 17 | `time_of_day` | `minuteOfDay / 1440.0` (linear mapping, monotonic) | 0–1 |

All values clamped to `min(value / normConstant, 1.0)` before L2 normalization.

#### Volume Attribution

```
Primary muscle:    70% of exercise volume
Secondary muscles: 30% split equally among all secondaries

Example: Bench Press (primary=chest, secondary=[triceps, shoulders])
  chest    += volume × 0.70
  triceps  += volume × 0.15
  shoulders += volume × 0.15
```

#### L2 Normalization

```
magnitude = √(Σ feature[i]²)
normalized[i] = feature[i] / magnitude    (if magnitude > 0)
```

Uses the shared `AnalyticsCalculations.l2Normalize(_:)` utility which leverages Apple Accelerate (`vDSP_dotprD`, `vDSP_vsdivD`) on iOS for performance.

#### Vector Migration

A `vectorVersion` counter is stored in `UserPreferencesService`. When normalization constants change, the version is bumped and all stored vectors are automatically recomputed on next analytics access.

#### Storage

`WorkoutVectorEntity` in SwiftData:
- `vectorData: Data` — 72 bytes (18 × Float32)
- Denormalized fields: `totalVolume`, `workoutDate`, `primaryMuscleGroups` (top 3)

---

### 4.2 VectorSearchService

**File:** `Shared/Services/Analytics/VectorSearchService.swift`

#### Cosine Similarity

For L2-normalized vectors, cosine similarity = dot product:

```
similarity(A, B) = Σ A[i] × B[i]
```

Range: 0 (orthogonal) to 1 (identical). Uses `vDSP_dotprD` on iOS.

#### Centroid Computation

```
centroid_raw[i] = Σ vectors[j][i] / count
centroid = AnalyticsCalculations.l2Normalize(centroid_raw)
```

Arithmetic mean across all dimensions, then L2 re-normalized. This is critical because the average of unit vectors is not itself a unit vector — without re-normalization, dot-product-based similarity scores against the centroid would be artificially low.

#### findSimilar(query, vectors, topK)

1. Compute dot product of query with every candidate
2. Sort descending by similarity
3. Return top K results as `[(index, similarity)]`

**Performance:** <5ms for 2,000 vectors on iPhone.

---

### 4.3 PlateauDetectionService

**File:** `Shared/Services/Analytics/PlateauDetectionService.swift`

#### Constants

```
minWeeksForAnalysis = 4
Improvement threshold: dynamic by training status (see below)
```

#### Algorithm

Progression is measured using **max estimated 1RM (e1RM) per exercise per week** — not raw volume. This avoids false plateau alerts when lifters periodize (e.g., switching from accumulation to peaking reduces volume but increases intensity).

The e1RM is computed via `AnalyticsCalculations.calculateOneRM()` (Epley/Brzycki hybrid).

The improvement threshold scales dynamically by training status (provided by `TrainingStatusDetector.detect()`):

| Training Status | Threshold | Rationale |
|----------------|:---------:|-----------|
| Beginner | 1.05 (5%) | Rapid expected gains |
| Intermediate | 1.02 (2%) | Moderate expected gains |
| Advanced | 1.00 (0%) | Maintaining strength is sufficient |

For each exercise with 4+ weekly occurrences:

1. Group sets by calendar week (Monday start)
2. Compute **max e1RM** for each week (best single-set estimate)
3. Track consecutive stalled weeks:

```
for week i in 1..<weeks:
    if maxE1RM[i] >= maxE1RM[i-1] × threshold(trainingStatus):
        weeksStalled = 0
    else:
        weeksStalled += 1
```

4. Only report if `consecutiveWeeksStalled >= 2`
5. Sort results by weeks stalled descending

`analyzePlateaus()` now accepts a `trainingStatus` parameter, wired through `WorkoutAnalyticsService` via `TrainingStatusDetector.detect()`.

#### Coefficient of Variation (diagnostic metric)

```
CV = σ / μ    where σ = √(Σ(vol − mean)² / count)
```

---

### 4.4 MuscleBalanceService

**File:** `Shared/Services/Analytics/MuscleBalanceService.swift`

#### 6 Antagonist Pairs

```
(chest, back)
(quadriceps, hamstrings)
(biceps, triceps)
(shoulders, lats)
(core, lowerBack)
(glutes, hipFlexors)
```

#### Imbalance Detection

For each pair with both muscles trained:

```
ratio = volume[A] / volume[B]

if ratio >= 2.0:  severity = .severe
if ratio >= 1.5:  severity = .moderate
(also checks reverse: volume[B] / volume[A])
```

#### Balance Score

```
Penalties: mild = 0.05, moderate = 0.15, severe = 0.30
balanceScore = max(0, 1.0 − Σ penalties)
```

Range: 0 (severely imbalanced) to 1 (perfectly balanced).

---

### 4.5 ExerciseRecommendationService

**File:** `Shared/Services/Analytics/ExerciseRecommendationService.swift`

#### Recommendation Sources (in priority order)

| Priority | Source | Confidence | Reason |
|----------|--------|------------|--------|
| 1 | Muscle imbalance (top 2) | 0.90 | `.fillsMuscleGap` |
| 2 | Plateau breaker (top 2, stalled 2+ weeks) | 0.85 | `.plateauBreaker` |
| 3 | Gap filler (muscles not trained in last 5 workouts) | 0.70 | `.fillsMuscleGap` |

**Major muscles checked for gaps:** chest, back, shoulders, quadriceps, hamstrings, biceps, triceps

Deduplicated by exercise ID (first occurrence wins). Max 5 returned.

---

### 4.6 AnalyticsCalculations (Shared Formulas)

**File:** `Shared/Services/Analytics/AnalyticsCalculations.swift`

#### Estimated 1RM (Brzycki / Epley hybrid)

```
if reps == 1:    e1RM = weight
if reps <= 5:    e1RM = weight × (1 + reps / 30)      // Epley
if reps 6–15:    e1RM = weight × 36 / (37 − reps)     // Brzycki
```

#### Set Intensity-Weighted Volume (IWV)

```
pct1RM = min(weight / bestE1RM, 1.5)    // cap at 150%
base = reps × pct1RM

if RPE > 0:
    IWV = base × (RPE / 10)
else:
    IWV = base
```

#### L2 Normalization Utility

```
public static func l2Normalize(_ vector: [Double]) -> [Double]
```

Shared utility used by `WorkoutVectorizer`, `VectorSearchService.computeCentroid`, and `AnomalyDetectionService`. Uses Apple Accelerate (`vDSP_dotprD`, `vDSP_vsdivD`) when available for performance.

#### EWMA (Exponentially Weighted Moving Average)

```
result[0] = values[0]
result[i] = λ × values[i] + (1 − λ) × result[i−1]
```

Higher λ = more weight on recent values.

#### Linear Regression (OLS)

```
slope = (n × ΣXY − ΣX × ΣY) / (n × ΣX² − (ΣX)²)
intercept = (ΣY − slope × ΣX) / n
R² = 1 − (SS_residual / SS_total)
```

---

## 5. Advanced Insights Services

Require 19+ completed workouts to activate.

### 5.1 TrainingLoadService (ACWR)

**File:** `Shared/Services/Analytics/TrainingLoadService.swift`

#### Acute-Chronic Workload Ratio (Systemic)

EWMA is computed on a **daily calendar basis**, not per-session. A `buildDailyLoads()` helper maps workout dates to day indices from the first workout to today. Rest days appear as load = 0, allowing proper fatigue decay.

```
Session load = Σ IWV for all working sets
    where IWV = reps × pct1RM × (RPE / 10 if available)

L_d = total session load for day d (0 on rest days)

Acute_d  = 0.25 × L_d + 0.75 × Acute_{d-1}
Chronic_d = 0.069 × L_d + 0.931 × Chronic_{d-1}

ACWR = Acute_today / Chronic_today
```

#### Cold-Start Guard

Minimum **8 completed workouts** spanning **14+ calendar days** required before ACWR is computed. Returns `nil` until threshold met. This prevents the chronic EWMA from being unstable with too few data points, which would inflate ACWR for new users.

#### Load Zone Classification

| Zone | ACWR Range | Meaning |
|------|-----------|---------|
| Under Training | < 0.6 | Insufficient stimulus |
| Optimal | 0.6–1.3 | Ideal training window |
| Caution | 1.3–1.5 | High fatigue accumulation |
| Danger | > 1.5 | Critical overtraining risk |

#### Per-Muscle-Group ACWR (Rolling Sum)

Per-muscle ACWR uses a **rolling sum** method instead of EWMA, which is better suited for muscles trained infrequently (1–2×/week). EWMA produces a saw-tooth pattern for sparse data; rolling sums are stable.

```
Acute  = sum of muscle IWV over last 7 days
Chronic = sum of muscle IWV over last 28 days / 4

ACWR_muscle = Acute / Chronic
```

Only muscles with 4+ sessions of data included.

---

### 5.2 OverloadTrackingService

**File:** `Shared/Services/Analytics/OverloadTrackingService.swift`

#### Per-Exercise Trend Analysis

1. Group best weekly e1RM per exercise by calendar week
2. Require 4+ weeks of data per exercise
3. Apply OLS linear regression on week indices vs e1RM values

```
slope = kg gained (or lost) per week
overloadIndex = R² × sign(slope)    // quality × direction, range −1 to 1
```

#### Trend Classification

| Status | Slope Threshold |
|--------|----------------|
| Progressing | > +0.5 kg/week |
| Plateau | −0.5 to +0.5 kg/week |
| Regressing | < −0.5 kg/week |

---

### 5.3 DeloadDetectionService

**File:** `Shared/Services/Analytics/DeloadDetectionService.swift`

Requires 6+ completed workouts. Returns `nil` if urgency < 0.15.

#### 5 Fatigue Signals

| Signal | Condition | Urgency Weight |
|--------|-----------|----------------|
| **Performance Decline** | 40%+ exercises regressing | `0.3 × ratio` |
| **Intensity Creep** | Effort ratio increasing 3+ consecutive sessions | `0.2` |
| **High ACWR** | ACWR > 1.4 | `0.3 × min((ACWR − 1.3) / 0.5, 1.0)` |
| **Overdue** | >6 weeks since volume dropped <60% of 4-week avg | `0.2 × min((weeks − 6) / 4, 1.0)` |
| **RPE Creep** | Avg RPE increasing 3+ consecutive sessions | `0.2 × min(increase / 2.0, 1.0)` |

```
totalUrgency = Σ signal urgencies
if totalUrgency < 0.15: return nil (no action)
```

#### Intensity Creep Detection

```
For last 3–5 sessions:
    meanEffort[session] = avg(e1RM_set / bestE1RM) per session

Triggered if: meanEffort[1] > meanEffort[0] AND meanEffort[2] > meanEffort[1]
```

#### Deload Week Detection

```
Build weekly session loads
For week i (4+):
    avg = mean(loads[i-4..i-1])
    if load[i] < avg × 0.6:
        mark as deload week
weeksSinceDeload = totalWeeks − lastDeloadWeekIndex
```

---

### 5.4 VolumeLandmarkService

**File:** `Shared/Services/Analytics/VolumeLandmarkService.swift`

Computes optimal weekly set ranges (MEV/MRV) per muscle group.

#### Population Defaults

| Muscle | MEV (sets/wk) | MRV (sets/wk) |
|--------|:---:|:---:|
| Chest | 8 | 22 |
| Back | 8 | 25 |
| Shoulders | 6 | 20 |
| Quadriceps | 6 | 22 |
| Hamstrings | 4 | 16 |
| Glutes | 4 | 16 |
| Biceps | 4 | 18 |
| Triceps | 4 | 18 |
| Calves | 6 | 16 |
| Core | 4 | 16 |
| Lats | 6 | 22 |
| Traps | 4 | 16 |
| Forearms | 2 | 12 |
| Lower Back | 2 | 10 |

#### Training Status Adjustments

```
Beginner:      MEV = max(base − 2, 2),   MRV = max(base − 4, MEV)
Intermediate:  MEV = base,               MRV = base
Advanced:      MEV = base + 2,           MRV = base + 4
```

#### Set Counting

```
Primary muscle:   1.0 credit per completed non-warmup set
Secondary muscle: 0.5 / secondaryCount credit per set

Example: Bench Press (1 primary, 2 secondary)
  Chest (primary):   1.0 credit
  Triceps (secondary): 0.5 / 2 = 0.25 credit
  Shoulders (secondary): 0.5 / 2 = 0.25 credit
  Total set credits: 1.0 + 0.25 + 0.25 = 1.5 (not 2.0)

Current weekly sets = sum over last 4 weeks ÷ 4, rounded to nearest int
```

The secondary credit is divided by the number of secondary muscles to prevent credit inflation. Without this, exercises targeting many secondaries would generate artificially high set counts, causing premature MRV warnings.

#### Volume Status

```
current < MEV:  underVolume
MEV ≤ current ≤ MRV:  optimal
current > MRV:  overVolume
```

---

### 5.5 RecoveryEstimationService

**File:** `Shared/Services/Analytics/RecoveryEstimationService.swift`

#### Base Recovery Hours

| Muscle | Hours |
|--------|:-----:|
| Chest | 64 |
| Back | 56 |
| Shoulders | 48 |
| Quadriceps | 48 |
| Hamstrings | 56 |
| Glutes | 48 |
| Biceps | 40 |
| Triceps | 40 |
| Calves | 36 |
| Core | 36 |
| Lats | 56 |
| Traps | 48 |
| Forearms | 36 |
| Lower Back | 56 |

#### Adjusted Recovery Calculation

```
volumeModifier = 1.0 + max(0, hardSets − 4) × 0.08
    (each set beyond 4 adds 8% recovery time)

meanEffortRatio = avg(e1RM_set / bestE1RM)

blendedEffort = (meanEffortRatio + RPE/10) / 2    (if RPE available)
              = meanEffortRatio                    (otherwise)

intensityModifier = 0.8 + blendedEffort × 0.4     (range 0.8–1.2)

adjustedHours = baseHours × volumeModifier × intensityModifier
recoveryPct = min(hoursSinceTrained / adjustedHours, 1.0)
```

#### Recovery Status

| Status | Threshold |
|--------|-----------|
| Ready | recoveryPct ≥ 1.0 |
| Recovering | recoveryPct ≥ 0.7 |
| Fatigued | recoveryPct < 0.7 |

---

### 5.6 TrainingDriftService

**File:** `Shared/Services/Analytics/TrainingDriftService.swift`

Compares recent training patterns against baseline.

#### Windows

- Recent: last 14 days (min 2 workouts)
- Baseline: 15–45 days ago (min 3 workouts)

#### Computation

```
recentCentroid = computeCentroid(recent vectors)
baselineCentroid = computeCentroid(baseline vectors)

overallDriftScore = 1.0 − cosineSimilarity(recent, baseline)
    (0 = identical, 1 = completely different)
```

#### Per-Dimension Drift

```
For each dimension i (0–17):
    delta = recentCentroid[i] − baselineCentroid[i]
    if |delta| > 0.10:    // 10% threshold
        flagged as drifting
Sort by |delta| descending
```

---

### 5.7 PhaseDetectionService

**File:** `Shared/Services/Analytics/PhaseDetectionService.swift`

Requires 4+ weeks of data.

#### Phase Classification (per weekly centroid)

Using vector dimensions: `dim[0]=volume, dim[1]=weight, dim[2]=reps, dim[3]=sets, dim[12]=compound_ratio`:

```
DELOAD:           volume < 0.15 AND weight < 0.15 AND sets < 0.15
PEAKING:          weight > volume × 1.3 AND reps < 0.2 AND compound > 0.15
INTENSIFICATION:  weight > volume AND weight > reps
ACCUMULATION:     (volume > weight OR sets > weight) AND reps > 0.1
Otherwise:        MIXED
```

3-element moving mode filter applied for temporal smoothing.

---

### 5.8 BlockComparisonService

**File:** `Shared/Services/Analytics/BlockComparisonService.swift`

Compares current 4-week block vs previous 4-week block.

```
currentCentroid = centroid(last 4 weeks)
previousCentroid = centroid(4–8 weeks ago)

similarity = cosineSimilarity(current, previous)    // 0–1

Per-dimension: deltas where |delta| > 0.10
```

Requires 3+ workouts in each block.

---

### 5.9 AnomalyDetectionService

**File:** `Shared/Services/Analytics/AnomalyDetectionService.swift`

Requires 5+ vectors.

#### EWMA Centroid Estimation

```
centroid = first vector
for each subsequent vector (chronologically):
    centroid[d] = 0.1 × vector[d] + 0.9 × centroid[d]    (λ = 0.1)

centroid = AnalyticsCalculations.l2Normalize(centroid)
```

The centroid is L2 re-normalized after the EWMA loop. Without this, the EWMA centroid's magnitude shrinks below 1.0, causing dot-product-based anomaly scores to be artificially inflated. Dimension drift comparisons also use the normalized centroid.

#### Anomaly Detection

```
anomalyScore[i] = 1.0 − cosineSimilarity(vector[i], normalizedCentroid)

threshold = mean(scores) + 2.0 × stddev(scores)    // z-score = 2.0 (~95%)

If score > threshold → anomaly
    Deviating dimensions: |delta| > 0.10, top 3
```

---

### 5.10 WorkoutQualityScoreService

**File:** `Shared/Services/Analytics/WorkoutQualityScoreService.swift`

#### 4-Pillar Score (each 0–100)

```
overallScore = (volume + intensity + consistency + balance) / 4
```

**Volume Score** (12-week window):
```
For each muscle trained:
    perSessionAvg = historyVolume[muscle] / sessionCount
    ratio = currentVolume / perSessionAvg

    if 0.8 ≤ ratio ≤ 1.4:
        groupScore = 100            // sweet spot (progressive overload rewarded)
    else if ratio < 0.8:
        groupScore = max(0, ratio / 0.8 × 100)   // linear penalty below average
    else:  // ratio > 1.4
        groupScore = max(60, 100 − (ratio − 1.4) / 0.6 × 40)  // gentle taper, floor 60

volumeScore = average(groupScores)
```

**Intensity Score:**
```
For each non-warmup set:
    ratio = setE1RM / historicalBestE1RM
intensityScore = min(max(mean(ratios) × 100, 0), 100)
```

**Consistency Score (Rest Rhythm):**
```
intervals = [time between consecutive sets, max 600s, exclude >10min]
validIntervals = intervals.filter { $0 > 15 }    // exclude superset/drop-set transitions

if validIntervals.count < 2: score = 80.0    // not enough data, default to reasonable score

CV = stddev(validIntervals) / mean(validIntervals)

if CV ≤ 0.25: score = 100
if CV ≤ 0.80: score = 100 − (CV − 0.25) × (70 / 0.55)
else:         score = 30
```

Intervals ≤ 15 seconds are filtered out before CV computation to exclude superset and drop-set transitions. Without this filter, advanced lifters performing supersets would be penalized for intentionally short rest intervals.

**Balance Score** (12-week IWV, 6 antagonist pairs):
```
For each pair:
    ratio = max(iwv_A, iwv_B) / min(iwv_A, iwv_B)
    pairScore = max(0, 100 × (1 − (ratio − 1) / 2))
balanceScore = average(valid pair scores)
```

#### Aggregate Quality (EWMA, λ = 0.3)

```
ewmaOverall = ewma(overallScores, λ=0.3)
trend = ((currentEWMA − ewma4WeeksAgo) / ewma4WeeksAgo) × 100%
percentile = rank(currentEWMA) / totalWorkouts
```

### 5.11 CoachingInsightService

**File:** `Shared/Services/Analytics/CoachingInsightService.swift`

Central coaching brain that produces contextual insights for post-workout, pre-workout, and inline contexts. Stateless.

#### Post-Workout Debrief Generation

Generates a `PostWorkoutDebrief` with basic stats and up to 3 priority-ranked coaching bullets:

| Priority | Source | Condition | Title Example |
|:-:|--------|-----------|---------------|
| 1 | personalRecord | PRs in session | "2 New PRs" |
| 2 | acwr | ACWR danger/caution (19+ wkts) | "High Training Load" |
| 3 | qualityScore | Score >5 pts from EWMA (5+ wkts) | "Quality Up" / "Quality Down" |
| 5 | overloadTrend | Exercise progressing (10+ wkts) | "Bench Press Trending Up" |
| 6 | volumeDelta | Volume >10% from 30-day avg (5+ wkts) | "Volume Up" / "Volume Down" |
| 7 | acwr | ACWR under-training (19+ wkts) | "Low Training Load" |
| 8 | recovery | Muscle fatigued with ready date (19+ wkts) | "Recovery Note" |
| 9 | sessionComparison | Similar session ≥70% match (10+ wkts) | "Similar to Mar 15, 2026" |

Bullets are sorted by priority (ascending), top 3 selected. Optionally enhanced via `InsightTextGenerating.enhancePostWorkoutBullets()` (Apple Intelligence).

#### Session Comparison (C6)

Uses `VectorSearchService.findSimilar()` (cosine similarity, topK=1) to find the most similar past workout. Requires ≥0.70 similarity. Computes volume delta (%) and intensity delta (%) against the matched session.

#### Muscle Neglect Detection (C5)

Monitors weekly sets per muscle group over an 8-week window:

```
For each muscle with ≥4 weeks of data:
    slope = linearRegression(weeklySets)
    if slope < -0.5:
        baseline = mean(first half of weeks)
        current = mean(last 2 weeks)
        decline% = (baseline − current) / baseline × 100
        if decline% > 20%: emit MuscleNeglectWarning
```

Warnings sorted by `percentDecline` (worst first).

#### Exercise Hints (C4)

Per-exercise micro-insight, one per exercise, in priority order:

| Priority | Condition | Text Example |
|:-:|-----------|--------------|
| 1 | Plateau ≥3 weeks | "Stalled 4 weeks — try a variation" |
| 2 | Absence ≥14 days | "21 days since last session" |
| 3 | Overload progressing | "Trending +1.5 kg/wk" |
| 4 | Recovery status | "Primary muscle recovered — good to push" / "still recovering" / "fatigued — consider lighter work" |

#### Weekly Digest (C2)

Week-over-week comparison card (Mon-Wed display). Requires 5+ workouts and a non-empty previous week.

Top insight selection priority:
1. Best progressing exercise by slope → "[Exercise] Gaining"
2. Volume delta >20% → "Volume Up/Down"
3. Fallback → "Consistent Training"

---

### 5.12 WeightSuggestionService

**File:** `Shared/Services/Analytics/WeightSuggestionService.swift`

Suggests weights for upcoming sets based on recent e1RM, overload trends, recovery, and ACWR.

#### Weight Suggestion Algorithm

```
1. bestE1RM = best e1RM for exercise in last 3 months
2. adjustedE1RM = bestE1RM

3. If overloadTrend is progressing:
      weeksSince = weeks since last session of this exercise
      adjustedE1RM += slopePerWeek × weeksSince

4. If deload: return roundToNearest2.5(e1RM × 0.60)

5. Apply recovery modifier:
      fatigued:   adjustedE1RM × 0.90  (−10%)
      recovering: adjustedE1RM × 0.95  (−5%)
      ready:      no change

6. Apply ACWR modifier:
      danger:  adjustedE1RM × 0.85  (−15%)
      caution: adjustedE1RM × 0.90  (−10%)
      optimal/under: no change

7. Convert e1RM to target weight:
      reps = 1:  weight = e1RM
      reps 2–5:  weight = e1RM / (1 + reps/30)         [inverse Epley]
      reps 6+:   weight = e1RM × (37 − reps) / 36      [inverse Brzycki]

8. Round to nearest 2.5 kg
```

#### Effort Creep Detection

Detects when RPE rises while strength stagnates:

```
sessions = last 5 sessions for this exercise (need ≥3)
rpeSlope = linearRegression(sessionIndex → avgRPE)
e1rmSlope = linearRegression(sessionIndex → bestE1RM)

if rpeSlope > 0.3/session AND e1rmSlope ≤ 0:
    emit EffortCreepWarning(rpeIncrease, sessionsTracked)
```

---

### 5.13 AdherenceAnalysisService

**File:** `Shared/Services/Analytics/AdherenceAnalysisService.swift`

Analyzes training frequency, consistency, and dropout risk over an 8-week window.

#### Computed Metrics

| Metric | Method |
|--------|--------|
| weeklyFrequency | Mean workouts per ISO week (8-week window) |
| frequencyTrend | Linear regression on weekly counts: slope >0.2 → progressing, <−0.2 → regressing, else plateau |
| mostCommonDays | Top 3 weekdays by workout count (1=Mon..7=Sun) |
| averageGapDays | Mean inter-workout gap (days) |
| currentGapDays | Days since last completed workout |
| longestStreak | Max consecutive weeks with ≥1 workout (52-week scan) |
| currentStreak | Current consecutive weeks with ≥1 workout |
| dropoutRisk | See below |
| expectedNextDate | Next occurrence of most common training day |
| scheduleSummary | "You typically train Mon, Wed, Fri" |

#### Dropout Risk Classification

```
gapStdDev = stddev(inter-workout gaps)  // population stddev, ≥3 gaps required
                                         // fallback: avgGap × 0.5

high:     currentGap > avgGap + 2σ AND frequencyTrend == regressing
moderate: currentGap > avgGap + σ
low:      otherwise
```

---

### 5.14 TrajectoryAnalysisService

**File:** `Shared/Services/Analytics/TrajectoryAnalysisService.swift`

Computes velocity and acceleration of training changes in the 18-dimensional vector space using 3-window centroid differencing.

#### Algorithm

```
sorted = vectors sorted by date, take last max(windowSize, 6)
Divide into 3 equal windows: old, mid, new

oldCentroid = mean(old window vectors)
midCentroid = mean(mid window vectors)
newCentroid = mean(new window vectors)

velocity = newCentroid − midCentroid           (per-dimension)
oldVelocity = midCentroid − oldCentroid
acceleration = velocity − oldVelocity

velMag = ‖velocity‖₂
accMag = ‖acceleration‖₂
```

#### Derived Metrics

| Metric | Condition |
|--------|-----------|
| isSteadyState | velMag < 0.05 AND accMag < 0.02 |
| isDecelerating | Volume acceleration (dims 0–2) all negative |
| volumeSubspaceStagnating | ‖velocity[0:2]‖ < 0.03 |
| muscleSubspaceDrifting | ‖velocity[6:11]‖ > 0.10 |
| spinningWheels | velMag < 0.05 AND angular change > 45° |
| trajectoryEfficiency | velMag / (angularChange / 180°) |
| predictedPlateauWeeks | ceil(velMag / accMag), capped at 52 (only if decelerating and velMag > 0.01) |

Angular change = acos(cosineSimilarity(velocity, oldVelocity)) × 180/π

---

### 5.15 WorkoutArchetypeService

**File:** `Shared/Services/Analytics/WorkoutArchetypeService.swift`

Clusters workouts into archetypes using k-means++ with cosine distance, then generates training fingerprints.

#### Archetype Clustering (A1)

```
1. L2-normalize all workout vectors
2. For k in 2..min(8, n/3):
      (assignments, centroids) = kMeans++(data, k, maxIter=50, cosineDistance)
      score = silhouetteScore(data, assignments, k)
3. Select k with best silhouette score
4. Label each cluster from centroid muscle ratios:
      legs > 0.35 → "Leg Day"
      chest > 0.3 && arms > 0.15 → "Push Day"
      back > 0.3 → "Pull Day"
      shoulders > 0.3 → "Shoulder Day"
      maxRatio < 0.25 && diversity > 0.5 → "Full Body"
      compound > 0.6 → "Heavy Compounds"
      arms > 0.35 → "Arms Day"
      core > 0.3 → "Core Focus"
      else → "Mixed Training"
```

#### Training Fingerprint (A6 + A7)

Computed from archetypes over a configurable window (default 4 weeks):

| Metric | Method |
|--------|--------|
| archetypeDistribution | Proportion of each archetype in recent period |
| entropy | Shannon entropy / log₂(k), normalized 0–1 (higher = more variety) |
| stabilityScore | Cosine similarity between current and prior period distributions |
| varietyTrend | If entropy delta > 0.1 → progressing; < −0.1 → regressing; else plateau |
| consecutiveSimilarity | Mean cosine similarity between consecutive workout vectors |

---

### 5.16 ChangePointDetectionService

**File:** `Shared/Services/Analytics/ChangePointDetectionService.swift`

Detects significant shifts in training patterns using CUSUM on dissimilarity time series.

#### CUSUM Algorithm

```
1. Compute EWMA centroid (α=0.3) across sorted vectors
2. For each vector i (starting from 1):
      dissimilarity[i] = 1 − cosineSimilarity(vector[i], ewmaCentroid)
      Update EWMA centroid

3. On the dissimilarity series:
      mean = mean(dissimilarities)
      stdDev = stddev(dissimilarities)
      cusumHigh = 0

      For each i:
          z = (dissimilarity[i] − mean) / stdDev
          cusumHigh = max(0, cusumHigh + z − 0.5)
          if cusumHigh > threshold (default 2.0):
              Emit TrainingChangePoint
              cusumHigh = 0  // reset

4. For each change point, compute top 3 dimension shifts
   (before vs after centroid, |delta| > 0.05)
```

#### Time-of-Day Analysis (B5)

Groups workouts into 4 windows (Morning 6-11, Afternoon 11-5, Evening 5-10, Night 10-6) and compares average quality scores. Reports best and worst windows if delta > 5% and each window has ≥3 data points.

---

### 5.17 AchievementTrackingService

**File:** `Shared/Services/Analytics/AchievementTrackingService.swift`

Tracks 6 badge achievements and computes personal volume-response curves.

#### 6 Badge Definitions

| Badge | Criteria | Icon |
|-------|----------|------|
| Progressive Loader | 3+ exercises progressing simultaneously | arrow.up.right.circle.fill |
| Plateau Breaker | Exercise went from plateau to 3+ weeks progressing | bolt.circle.fill |
| Iron Consistency | 8 consecutive weeks with ≥1 workout | flame.circle.fill |
| Balanced Builder | All muscle groups at optimal volume for 4 weeks | scale.3d |
| Volume Explorer | All 6 muscle groups trained in one week | globe |
| Smart Recovery | Took deload when recommended | heart.circle.fill |

Earned achievements stored in UserDefaults (`earned_achievements`). Each badge can only be earned once.

#### Volume-Response Curves (A9, 50+ workouts)

Per-muscle-group quadratic regression of weekly sets vs. overload slope:

```
gain = a × sets² + b × sets + c

Requires:
  - 50+ completed workouts
  - 12+ data points per muscle group
  - R² > 0.3
  - a < 0 (inverted parabola)

Personal volume landmarks:
  MAV = −b / (2a)                    // sets at peak gain
  MEV = lower root (gain = 0)        // minimum effective volume
  MRV = upper root (gain = 0)        // maximum recoverable volume
```

---

## 6. Progression & Coaching Services

### 6.1 TrainingStatusDetector

**File:** `Shared/Services/Progression/TrainingStatusDetector.swift`

```
Beginner:     < 3 months AND < 50 workouts, OR weekly frequency < 2.0
Intermediate: (≥ 3 months OR ≥ 50 workouts) AND ≥ 2.0 weekly frequency
Advanced:     > 18 months AND > 200 workouts AND ≥ 3.0 weekly frequency
```

Weekly frequency measured over last 3 months using calendar week counting.

#### 1RM Estimation (OneRMEstimate)

- **Recent** (0–6 months): No penalty
- **Extended** (6–12 months): 10% detraining penalty
- **Beyond 12 months**: Ignored
- Uses Epley (reps ≤ 5) / Brzycki (reps 6–15)
- Rounded to nearest 2.5 kg

---

### 6.2 ProgramDesignService

**File:** `Shared/Services/Progression/ProgramDesignService.swift`

Four periodization models:

| Model | Intensity Step/wk | Deload Frequency | Suited For |
|-------|:-:|:-:|:-:|
| Linear | Beginner 2.5%, Int 2%, Adv 1.5% | Every 4th week (beg/int only) | Beginners |
| DUP | 2% per block | Every 4th week (beg/int only) | Intermediate |
| WUP | 2% per block | Per block | Intermediate |
| Block | Phase-specific | After realization | Advanced |

**Block Periodization phases:**
- Accumulation: 65–75% 1RM, 3–4 sets, 8–12 reps
- Transmutation: 78–88% 1RM, 4–5 sets, 4–6 reps
- Realization: 88–100% 1RM, 3–5 sets, 1–3 reps
- Deload: 50% intensity, 2 sets, 10 reps

---

### 6.3 SessionExecutionService

**File:** `Shared/Services/Progression/SessionExecutionService.swift`

#### 1RM EWMA Smoothing (Asymmetric)

```
Outlier threshold: 15% deviation rejection
Regression guard: only apply downward if estimated < 95% of current

Upward (PR):   smoothed1RM = estimated          // accept immediately
Downward:      smoothed1RM = 0.3 × estimated + 0.7 × current    // smooth as before
```

The EWMA is **asymmetric**: new personal records are accepted immediately (α = 1.0 upward), while downward fluctuations are smoothed (α = 0.3). This prevents the smoothing function from "crushing" legitimate PRs — e.g., a 100→110 kg jump would only register as 103 kg with symmetric smoothing.

On first use (current1RM = 0): direct assign without EWMA.

---

### 6.4 AdaptiveAdjustmentService

**File:** `Shared/Services/Progression/AdaptiveAdjustmentService.swift`

#### Detraining Detection

| Days Since Last Workout | Severity | Intensity Reduction |
|:-:|:-:|:-:|
| 10–21 | 0.3 | 5% |
| 21–42 | 0.6 | 10% |
| 42+ | 0.9 | 15% + repeat-block |

#### Beginner Regression

- 2 consecutive misses: 5% load decrease
- 3+ consecutive misses: 10% load decrease + repeat week

#### Multi-Signal Deload

If `deloadSignals.count ≥ 2`: trigger deload adjustment (50% volume reduction for 1 week).

Arbitration: max 3 proposals, deload always wins conflicts.

---

### 6.5 PlanAnalyticsService

**File:** `Shared/Services/Progression/PlanAnalyticsService.swift`

Resolves planned sessions to actual workouts via:
1. Direct link (`completedWorkoutId`)
2. Template match
3. Date proximity (within 2 days)

**Adherence:** `isOnTrack = overallAdherence ≥ 0.75`

---

### 6.6 PersonalRecordService

**File:** `Shared/Services/PersonalRecordService.swift`

PR types detected (priority order): e1RM > maxWeight > maxReps > maxVolume

---

### 6.7 CalorieEstimationService

**File:** `Shared/Services/CalorieEstimationService.swift`

#### Active/Rest Time Split

Active lifting time is estimated per set based on exercise type:
- Compound exercises: **40 seconds** per set
- Isolation exercises: **25 seconds** per set

```
activeTime = Σ (setsPerExercise × activeSecondsPerSet)
restTime = totalDuration − activeTime
```

The equipment MET is applied only to active time. A recovery MET of 1.5 is applied to rest time. This prevents overestimation for lifters who take long rest periods.

#### Volume Bonus (Dynamic Lytle Coefficient)

The Lytle coefficient scales dynamically based on the workout's compound ratio:

```
compoundRatio = compoundVolume / totalVolume    (0.0–1.0)
dynamicCoefficient = (1.0 + compoundRatio × 2.5) / 1000.0

volumeBonus = totalVolume × dynamicCoefficient
```

This ranges from ~1.0 kcal/1000 kg (all isolation) to ~3.5 kcal/1000 kg (all compound), reflecting the greater energy cost of multi-joint movements.

#### EPOC

```
epocCalories = 6–10% of session calories (varies by RPE and compound ratio)
```

EPOC is capped at **10%** (reduced from 15%), matching research showing standard resistance training EPOC caps at ~5–7% of session expenditure.

#### Total

```
totalCalories = activeCalories + restCalories + volumeBonus + EPOC
```

**MET values by equipment:**
- Kettlebell compound: 9.0, isolation: 6.0
- Barbell/Trap/EZ compound: 5.5, isolation: 4.0
- Dumbbell compound: 5.0, isolation: 3.5
- Bodyweight: 4.5–6.5 (RPE-dependent)
- Machine/Cable compound: 4.0, isolation: 3.5

---

## 7. Data Models

### WorkoutInsights (Aggregate Root)

Not persisted — assembled fresh by services each time.

| Field | Type | Description |
|-------|------|-------------|
| generatedAt | Date | Computation timestamp |
| workoutCount | Int | Total completed workouts |
| plateaus | [PlateauAnalysis] | Stalled exercises |
| muscleBalance | MuscleBalance? | Balance analysis |
| recommendations | [ExerciseRecommendation] | Suggested exercises |
| recoveryPatterns | [RecoveryPattern] | Per-muscle recovery |
| optimalVolumes | [OptimalVolumeRange] | Per-muscle volume targets |
| trainingLoad | TrainingLoad? | ACWR data (19+) |
| overloadTrends | [OverloadTrend] | Per-exercise trends (19+) |
| deloadRecommendation | DeloadRecommendation? | Deload suggestion (19+) |
| trainingDrift | TrainingDrift? | Baseline divergence (19+) |
| trainingPhase | TrainingPhaseDetection? | Current phase (19+) |
| blockComparison | BlockComparison? | Block diff (19+) |
| anomalies | [WorkoutAnomaly] | Outlier workouts (19+) |
| highlights | [AnalyticsHighlight] | Top insights (19+) |
| trajectoryAnalysis | TrajectoryAnalysis? | Trajectory velocity/acceleration (19+) |

### WorkoutVector

18-dimensional L2-normalized feature vector. Stored as 72-byte Float32 binary blob in SwiftData. Denormalized fields: totalVolume, workoutDate, primaryMuscleGroups (top 3).

### TrainingLoad

ACWR with acute/chronic EWMA values, load zone, per-muscle-group ACWR.

### OverloadTrend

Per-exercise: weekly e1RM series, linear regression slope (kg/wk), R²-based overload index, trend status.

### DeloadRecommendation

Urgency score (0–1), triggered signals, weeks since last deload, human-readable suggestion.

### PlateauAnalysis

Per-exercise: weeks stalled, volume CV, last progress date, computed recommendation text.

### MuscleBalance

Per-muscle volumes and set counts, detected imbalances with severity and recommendations, overall balance score (0–1).

### RecoveryPattern

Per-muscle: adjusted recovery hours, recovery percentage, status (ready/recovering/fatigued), ready-to-train date.

### OptimalVolumeRange

Per-muscle: MEV, MRV (adjusted for training status), current weekly sets, volume status.

### WorkoutQualityScore

Per-workout: 4 pillar scores (0–100) + overall. Aggregate: EWMA-smoothed, trend vs 4 weeks ago, percentile rank.

### BlockComparison

4-week block similarity, per-dimension deltas, summary text.

### WorkoutAnomaly

Anomaly score (0–1), deviating dimensions (top 3).

### TrainingPhaseDetection

Current phase, weekly phase history.

### ExerciseRecommendation

Exercise, reason, confidence (0.7–0.9), target muscle group.

### AnalyticsHighlight

Type (personalRecord/streak/milestone/improvement/warning), title, detail text.

### CoachingInsight

Priority-ranked coaching bullet: priority (lower = more important), title, detail, SF Symbol icon, CoachingColor (.primary/.success/.warning/.danger/.info), InsightSource (personalRecord/qualityScore/effortCreep/overloadTrend/volumeDelta/acwr/recovery/sessionComparison/adherence/plateau/muscleNeglect/trajectory).

### ExerciseHint

Per-exercise micro-insight: text, SF Symbol icon.

### ExerciseCoachingData

Per-exercise coaching cache: `[Int: WeightSuggestion]` (setIndex → suggestion), optional EffortCreepWarning, optional ExerciseHint.

### PostWorkoutDebrief

Post-workout summary: workoutName, duration, totalVolume, totalSets, exerciseCount, optional WorkoutQualityScore, prsHit, coaching bullets `[CoachingInsight]`, optional SessionComparison.

### SessionComparison

Most similar past workout: matchDate, matchName, similarity (0–1), volumeDelta (%), intensityDelta (%).

### WeightSuggestion

Suggested weight for a set: weight (rounded to 2.5 kg), targetReps, explanation, modifiers (e.g. "Recovery: -5%", "High ACWR: -15%").

### EffortCreepWarning

RPE trending up without strength gains: exerciseName, rpeIncrease, sessionsTracked, message.

### AdherenceAnalysis

Training consistency analysis: weeklyFrequency, frequencyTrend (TrendStatus), mostCommonDays ([1=Mon..7=Sun]), averageGapDays, currentGapDays, longestStreak, currentStreak, dropoutRisk (DropoutRisk: .low/.moderate/.high), expectedNextDate, scheduleSummary.

### TrajectoryAnalysis

Vector-space trajectory: velocityMagnitude, accelerationMagnitude, isSteadyState, isDecelerating, trajectoryEfficiency, predictedPlateauWeeks, volumeSubspaceStagnating, muscleSubspaceDrifting, spinningWheels, topAcceleratingDims, topDeceleratingDims.

### WeeklyDigest

Week-over-week comparison: weekStart, topInsight (CoachingInsight), workoutsThisWeek, workoutsLastWeek, volumeDeltaPercent, qualityTrend, prsThisWeek.

### WorkoutArchetype

Cluster of similar workouts: label (auto-generated from centroid), centroid ([Double]), memberWorkoutIds, dominantFeatures (top 3), avgVolume, avgDuration, frequency (sessions/week), lastPerformed, daysSinceLastPerformed.

### TrainingFingerprint

Training pattern signature: archetypeDistribution ([String: Double]), entropy (0–1, normalized Shannon entropy), stabilityScore (cosine similarity vs prior period), varietyTrend (TrendStatus), consecutiveSimilarity.

### MuscleNeglectWarning

Declining muscle group volume: muscleGroup, weeksDecline, currentWeeklySets, baselineWeeklySets, percentDecline, message.

### WorkoutSuggestion

Archetype-based workout suggestion: suggestedArchetype, reason, optional overdueArchetype, optional overdueMessage.

### ArchetypePrediction

Predicted next workout type: predictedLabel, confidence (0–1), alternatives [(label, probability)].

### TrainingChangePoint

Detected training shift: date, workoutIndex, description, keyDimensionShifts ([DimensionDrift]: featureName, delta).

### TimeOfDayAnalysis

Best/worst training windows: bestWindow, bestAvgQuality, worstWindow, worstAvgQuality, message.

### Achievement

Training badge: id, name, description, SF Symbol icon, optional earnedAt. 6 badge types defined.

### VolumeResponseCurve

Personal volume-response per muscle: muscleGroup, personalMEV, personalMAV, personalMRV, rSquared, message.

---

## 8. UI/UX — Exact Wordings & Presentation

### 8.1 InsightsCardView (Dashboard Card)

**Header:** `"INSIGHTS"` (10pt bold, uppercase, letter-spacing 1.5)

**States:**

| State | What Shows |
|-------|-----------|
| No Pro Access | Lock icon + "Unlock Analytics" + "PRO" badge + "Plateaus, muscle balance, quality scores & more" |
| Loading | Spinner + "Analyzing workout history..." (migrating) or "Loading insights..." |
| Progress | Lock icon + progress bar + "Complete [X] more workout(s) to unlock [Feature Name]" |
| Content | Up to 2 insight rows (see priority below) + "View All" link |

**Insight row priority (top 2 shown):**
1. Plateaus (top 2): icon `exclamationmark.triangle.fill` (orange) — "[Exercise]" / "Stalled [X] weeks"
2. Imbalances (top 1): icon `arrow.left.arrow.right` (orange/red) — "[Primary] / [Comparison]" / "[X.X]:1 ratio"
3. Recommendations (top 1): icon `lightbulb.fill` (primary) — "[Exercise]" / reason text
4. Advanced highlight (top 1): type-specific icon
5. Fallback: icon `checkmark.circle.fill` (green) — "On Track" / "[X] workouts analyzed"

---

### 8.2 AnalyticsDashboardView (Full Analytics Page)

**Sections in order:**

1. **Next Feature Unlock Banner**: icon `sparkles` + "[X] more workout(s) to unlock **[Feature Name]**"
2. **Workout Count**: Large "[X]" (36pt bold) + "workouts completed"
3. **Feature Roadmap**: Per feature — name, description, progress bar, "Unlocked" badge or "[X] more" text
4. **Training Quality** (if unlocked): Large EWMA score "[X] / 100" + 4 dimension bars (Volume, Intensity, Balance, Rest Rhythm) + "Based on [X] recent workouts"
5. **Muscle Balance** (if unlocked): Per-muscle volume bars + set counts + imbalance warnings
6. **Plateau Warnings** (if unlocked): Per plateau — "[Exercise]" / "Stalled for [X] week(s)" / recommendation
7. **Recommendations** (if unlocked): Per rec — "[Exercise]" / reason text
8. **Advanced Insights Card** (if unlocked, 19+ workouts): See 8.3

---

### 8.3 AdvancedInsightsCardView (Compact Summary)

**Header:** `"ADVANCED INSIGHTS"` + chevron.right

**Left:** Circular ACWR gauge (52×52, arc from 0 to min(ACWR/2, 1)):
- Center: "[X.XX]" (13pt bold monospaced) + "ACWR" (7pt)

**Right column:**
- Phase: icon `waveform.path` + "[Phase Name]" (13pt semibold)
- Top highlight detail (11pt, 2 lines max)
- DEBUG only: AI diagnostic — "AI: [N] enhanced" or "Templates (AI: [error])"
- Recovery: icon `heart.fill` + "[X] ready" + "· [X] recovering"

---

### 8.4 AdvancedInsightsView (Full Detail)

10 sections, each showing when data is available:

**1. Smart Highlights** — Per highlight: type icon + title + detail

| Highlight Type | Icon | Color |
|----------------|------|-------|
| personalRecord | `trophy.fill` | primary |
| streak | `flame.fill` | orange |
| milestone | `flag.fill` | primary |
| improvement | `arrow.up.right` | green (success) |
| warning | `exclamationmark.triangle.fill` | red (danger) |

**2. Training Load** — Large gauge (72×72) + rows: "Acute" → "[X.0]", "Chronic" → "[X.0]", "Zone" → zone name

**3. Training Phase** — Icon + phase name + description + history timeline (colored blocks)

| Phase | Timeline Color |
|-------|----------------|
| Accumulation | Primary |
| Intensification | Orange |
| Peaking | Red (danger) |
| Deload | Green (success) |
| Mixed | TextTertiary |

**4. Volume Landmarks** — Per muscle: status dot + name + "[current] / [min]–[max]" + status label ("Under"/"Optimal"/"Over")

**5. Recovery Status** — Per muscle: status dot + name + status label

| Status | Color | Label |
|--------|-------|-------|
| Ready | Green (success) | "Ready" |
| Recovering | Yellow | "Recovering" |
| Fatigued | Red (danger) | "Fatigued" |

**6. Progressive Overload** — Per exercise: trend icon + name + "[±X.X] kg/wk" + label

| Trend | Icon | Color | Label |
|-------|------|-------|-------|
| Progressing | `arrow.up.right` | Green (success) | "Progressing" |
| Plateau | `arrow.right` | Yellow | "Plateau" |
| Regressing | `arrow.down.right` | Red (danger) | "Regressing" |

**7. Training Drift** — Icon `arrow.triangle.branch` (orange) + "[X]% drift from baseline" + per-dimension deltas

**8. Deload Recommendation** — Shield icon (red if urgency >0.5, else orange) + "Urgency: [X]%" + suggested action + "[X] weeks since last deload"

**9. Block Comparison** — Summary text + "[X]% similar" + block labels

**10. Anomalous Workouts** — Top 3: icon `exclamationmark.octagon` (orange) + "Anomaly score: [X]%" + "Deviating: [dim1], [dim2]"

---

### 8.5 ExerciseInsightsView

Embedded in ExerciseDetailView:

- **Locked:** "Unlock plateau detection with [X] more workouts"
- **Plateau:** icon `exclamationmark.triangle.fill` (orange) + "Plateau Detected" + "No progress for [X] week(s)" + recommendation
- **No plateau:** icon `checkmark.circle.fill` (green) + "Progressing well - no plateau detected"
- **Recommendations:** icon `lightbulb.fill` (primary) + reason text

---

### 8.6 SimilarWorkoutsView

- **Loading:** "Finding similar workouts..."
- **Empty:** icon `magnifyingglass` + "No similar workouts found" + "Complete more workouts to find matches"
- **Results:** Workout name + date + similarity badge "[X]%" + volume + matched features

---

### 8.7 WorkoutQualityScoreView

Large circular gauge (52×52): score/100 + 3 mini dimension bars (Volume, Intensity, Rest Rhythm — Balance excluded for single workouts).

Score color: ≥80 green, ≥60 primary, ≥40 orange, <40 red.

---

### 8.8 PostWorkoutSummaryView

**File:** `iOS/Features/Workout/Views/PostWorkoutSummaryView.swift`

Full-screen sheet presented after every completed workout (1+ workouts). Animated entrance with staggered delays.

**Layout (top to bottom):**

1. **Checkmark header** — `checkmark.circle.fill` (56pt, spring animation, scale 0.3→1.0) + "Workout Done" (title2 bold)
2. **Stats** — workout name (headline) + 3 stat pills (clock/duration, dumbbell/exercises, number/sets) + total volume (kg) + PR count if > 0 (trophy icon)
3. **Quality score donut** (if available, 5+ workouts) — 72×72 circle, trim animates from 0 to score/100, color: ≥80 green, ≥60 primary, <60 red. Score number in center (title3 bold monospaced).
4. **Coaching bullets** (0–3) — each in a card: SF Symbol icon (color-coded by CoachingColor) + title (subheadline bold) + detail (caption). Cards stagger-animate in (0.15s between each).
5. **"Got It" button** — full-width, primary color, 12px rounded corners

**Colors:** `STColors.primary` (gold), `STColors.success` (green), `.orange` (warning), `STColors.danger` (red), `STColors.textSecondary` (info/neutral).

---

### 8.9 PreWorkoutContextCard

**File:** `iOS/Features/Workout/Views/PreWorkoutContextCard.swift`

Card shown on ActiveWorkoutView before starting a workout (5+ workouts, replaces simple start view when analytics data available).

**Layout (top to bottom):**

1. **Header** — "READY TO TRAIN" (12pt bold, uppercase, tracking 1.5, primary color)
2. **Recovery status** — per-muscle rows (up to 6): colored dot (green=ready, orange=recovering, red=fatigued) + muscle name + status label. Summary: "X ready, Y recovering"
3. **Training load** — "Training Load" label + "ACWR X.XX" (15pt bold, color-coded by zone) + gauge bar (80px wide, fill = ACWR/2.0) + zone label (Under/Optimal/Caution/Danger)
4. **Adherence** — 3-column: "Last workout: X days ago" + "This week: X typical" + streak (if >1 week): "Streak: X wk" (primary color)
5. **Start buttons** — "START WORKOUT" (primary, full-width, 48px height) + optional "START FROM PLAN" (text-only, secondary)

Sections separated by dividers. Entire card: surface background, rounded corners, border stroke.

---

### 8.10 WeeklyDigestCard

**File:** `iOS/Features/Dashboard/Views/WeeklyDigestCard.swift`

Dashboard card shown Monday through Wednesday. Positioned between ProgressionPlanCard and stats carousel.

**Layout:**

1. **Header row** — "LAST WEEK" (11pt bold, uppercase, tracking 1.5) + right-aligned "X so far this week (+/-delta)"
2. **Stats row** — badges: workouts count, volume delta %, PRs (if > 0). Each badge: value (15pt bold) + label (10pt tertiary).
3. **Top insight** — SF Symbol icon (color-coded) + title (13pt semibold) + detail (11pt, 2 lines max)

Card: surface background, rounded corners, border stroke.

---

### 8.11 Color Coding Reference

| Context | Green (success) | Primary/Gold | Orange | Red (danger) | Blue | Yellow |
|---------|:-:|:-:|:-:|:-:|:-:|:-:|
| **Score** | 80–100 | 60–80 | 40–60 | 0–40 | — | — |
| **Load Zone** | Optimal | — | Caution | Danger | Under Training | — |
| **Recovery** | Ready | — | — | Fatigued | — | Recovering |
| **Volume** | Optimal | — | — | Over | Under | — |
| **Trend** | Progressing | — | — | Regressing | — | Plateau |
| **Phase** | Deload | Accumulation | Intensification | Peaking | — | — |
| **Imbalance** | — | — | Moderate | Severe | — | Mild |

---

### 8.12 Number Formatting Rules

| Data | Format | Example |
|------|--------|---------|
| ACWR | 2 decimals | "1.25" |
| Scores (0–100) | 0 decimals | "85" |
| Slope (kg/week) | ±1 decimal | "+2.5 kg/wk" |
| Volume (kg) | 0 decimals | "1,500" |
| Similarity | 0 decimals + % | "87%" |
| Drift | 0 decimals + % | "28%" |
| Ratios | 1 decimal + :1 | "2.3:1" |
| Weekly sets | Integer | "12" |
| Deload urgency | 0 decimals + % | "65%" |
| Anomaly score | 0 decimals + % | "78%" |
| Recovery hours | 0 decimals | "64h" |

---

## 9. Recommendations & Insights — How They Are Created and Presented

### 9.1 Advanced Highlights (19+ workouts)

Generated by `TemplateInsightGenerator.generateHighlights()`. Max 5 returned, in priority order:

**Priority 1 — Warnings:**

| Condition | Title | Detail Text |
|-----------|-------|-------------|
| Deload recommended | "Deload Recommended" | `suggestedAction` from DeloadDetectionService (see 9.6) |
| ACWR in danger zone | "High Training Load" | "ACWR at [X.XX] — reduce volume to avoid overtraining" |
| Muscle over MRV (top 2) | "[Muscle] Over Volume" | "[X] sets/week exceeds MRV of [Y]" |

**Priority 2 — Improvements:**

| Condition | Title | Detail Text |
|-----------|-------|-------------|
| Exercise progressing (top 2) | "[Exercise] Progressing" | "+[X.X] kg/week" |
| ACWR in optimal zone | "Optimal Training Load" | "ACWR at [X.XX] — sweet spot for progress" |

**Priority 3 — Milestones/Info:**

| Condition | Title | Detail Text |
|-----------|-------|-------------|
| Phase detected | "Training Phase: [Name]" | Phase description (see 9.10) |
| Drift > 15% | "Training Drift Detected" | "[feature] shifted [up/down]" |
| Muscles fatigued | "Muscles Still Fatigued" | "[Muscle1], [Muscle2] — consider extra rest before training again" |

---

### 9.2 Early Highlights (5–18 workouts)

Generated by `TemplateInsightGenerator.generateEarlyHighlights()`. Max 3 returned:

| Priority | Condition | Title | Detail |
|:-:|-----------|-------|--------|
| 1 | Plateau (10+ wkts, 3+ weeks stalled, top 2) | "[Exercise] Stalled" | "[X] weeks no progress" |
| 2 | Imbalance (moderate+, top 1) | "[Primary]/[Comparison] Imbalance" | "[X.X]x ratio" |
| 3 | Top recommendation | "Try [Exercise]" | Reason text (see 9.5) |

---

### 9.3 Plateau Recommendations

Computed property on `PlateauAnalysis`:

| Weeks Stalled | Recommendation Text |
|:-:|:--|
| 4+ | "Consider a deload for [Exercise] by 10-20% and focus on form." |
| 2–3 | "Try increasing volume or adding a technique variation for [Exercise]." |
| <2 | "Progress is on track for [Exercise]. Keep pushing!" |

(When exercise name not available, generic version without "[Exercise]".)

---

### 9.4 Muscle Imbalance Recommendations

Computed property on `MuscleImbalance`:

| Severity | Recommendation Text |
|----------|:--|
| Severe | "Significantly reduce [Primary] volume and increase [Comparison] by 30-40% ([X.X]x imbalance)." |
| Moderate | "Increase [Comparison] volume by 20-30% to balance [Primary] training ([X.X]x imbalance)." |
| Mild | "Consider adding 1-2 more sets for [Comparison] to improve balance with [Primary] ([X.X]x imbalance)." |

---

### 9.5 Exercise Recommendation Reasons

| Reason Enum | Display Text |
|-------------|:--|
| fillsMuscleGap | "Fills [muscle] gap" |
| plateauBreaker | "Plateau breaker" |
| similarToFavorites | "Matches your favorites" |
| recoveryAppropriate | "Good for recovery" |

---

### 9.6 Deload Recommendation Text

Generated by `DeloadDetectionService` based on urgency and triggers:

| Condition | Suggested Action Text |
|-----------|:--|
| Urgency > 0.6 | "Take a full deload week: reduce volume by 40-50% and intensity by 10-15%" |
| High ACWR trigger | "Reduce training volume this week by 30% to bring load ratio back to optimal" |
| Performance decline trigger | "Consider a lighter week focusing on technique with reduced weights" |
| RPE creep trigger | "Subjective effort is rising — consider reducing intensity before performance drops" |
| Default | "Monitor fatigue levels; a planned deload within 1-2 weeks is recommended" |

---

### 9.7 Coaching Explanations (Plan Adjustments)

Generated by `StaticCoachingProvider.explain()`:

| Adjustment Type | Title | Body | Suggested Action |
|:-:|:-:|:--|:--|
| Deload | "Recovery Week" | "Your training data suggests it's time for a lighter week. This helps your body adapt and come back stronger." | "Complete this week's sessions at the reduced volume." |
| Load Increase | "Weight Increase" | "You're getting stronger! Based on your recent performance, we're increasing the weight." | "Focus on maintaining good form at the new weight." |
| Load Decrease | "Weight Adjustment" | "We're adjusting the weight down slightly to help you build back up with better form and consistency." | "Hit all your reps cleanly this week." |
| Exercise Swap | "Exercise Change" | "To keep progressing, we're swapping in a variation that targets the same muscles from a different angle." | "Start with a lighter weight to learn the movement pattern." |
| Other | "Plan Update" | `[adjustment.description]` | (none) |

**Coaching tone by training status:**
- Beginner: "Encouraging and educational — explain the 'why' behind each recommendation."
- Intermediate: "Supportive and data-driven — reference metrics and trends."
- Advanced: "Concise and technical — focus on periodization details and marginal gains."

---

### 9.8 Post-Workout Summaries

Generated by `StaticCoachingProvider.summarizeWorkout()`:

```
Performance Summary: "Completed [X] sets across [Y] exercises."
Key Highlights: ["Completed [Exercise1]", "Completed [Exercise2]", "Completed [Exercise3]"]
Areas for Improvement: []
Motivational Note: "Great work showing up today. Consistency is the key to progress."
```

---

### 9.9 Drift & Block Comparison Text

**Drift explanation** (`TemplateInsightGenerator.generateDriftExplanation()`):

- No drift: `"Training is consistent with your established baseline."`
- With drift: `"Your recent training is [X]% different from baseline. [dim1] is [higher/lower] than usual and [dim2] is [higher/lower] than usual."`

**Block summary** (`TemplateInsightGenerator.generateBlockSummary()`):

- No changes: `"Training has been consistent between blocks."`
- With changes: `"Key changes: [dim1] [increased/decreased], [dim2] [increased/decreased], [dim3] [increased/decreased]."`

---

### 9.10 Phase Descriptions

| Phase | Display Name | Short Description | Long Description |
|-------|:-:|:--|:--|
| Accumulation | "Accumulation" | "High volume — building work capacity" | "High volume phase — building work capacity and muscle" |
| Intensification | "Intensification" | "Heavy weights — building strength" | "Moderate volume, heavier weights — building strength" |
| Peaking | "Peaking" | "Low volume, max weights — expressing strength" | "Low volume, near-max weights — expressing strength" |
| Deload | "Deload" | "Recovery phase — dissipating fatigue" | "Recovery phase — reduced training to dissipate fatigue" |
| Mixed | "General" | "Varied training pattern" | "Varied training pattern — no single phase dominates" |

### 9.11 Post-Workout Coaching Bullet Selection

Generated by `CoachingInsightService.generatePostWorkoutDebrief()`. Max 3 bullets, sorted by priority (lower = higher priority):

| Priority | Source | What It Says |
|:-:|--------|--------------|
| 1 | PRs | "X New PR(s)" / "Hit X personal record(s) this session" |
| 2 | ACWR warning | "High Training Load" / "ACWR at X.XX — consider reducing volume next session" |
| 3 | Quality delta | "Quality Up/Down" / "X/100 — Y pts above/below your average" |
| 5 | Overload trend | "[Exercise] Trending Up" / "+X.X kg/week over recent weeks" |
| 6 | Volume delta | "Volume Up/Down" / "X% above/below your 30-day average" |
| 7 | Under-training | "Low Training Load" / "ACWR at X.XX — room to push harder" |
| 8 | Recovery note | "Recovery Note" / "[Muscle] will be ready again [Day]" |
| 9 | Session comparison | "Similar to [Date]" / "X% match — Y% more/less volume" |

---

### 9.12 Weekly Digest Top Insight Selection

Generated by `CoachingInsightService.generateWeeklyDigest()`. Single insight shown:

| Priority | Condition | Title | Detail |
|:-:|-----------|-------|--------|
| 1 | Best progressing exercise | "[Exercise] Gaining" | "+X.X kg/week over recent weeks" |
| 2 | Volume delta > 20% | "Volume Up/Down" | "X% vs last week" |
| 3 | Fallback | "Consistent Training" | "X workouts this week" |

---

### 9.13 Exercise Hint Priority

Generated by `CoachingInsightService.generateExerciseHint()`. First matching condition wins:

| Priority | Condition | Text | Icon |
|:-:|-----------|------|------|
| 1 | Plateau ≥ 3 weeks stalled | "Stalled X weeks — try a variation" | exclamationmark.triangle |
| 2 | Last performed ≥ 14 days ago | "X days since last session" | clock.arrow.circlepath |
| 3 | Overload trend progressing | "Trending +X.X kg/wk" | arrow.up.right |
| 4 | Recovery ready | "Primary muscle recovered — good to push" | checkmark.circle |
| 4 | Recovery recovering | "Primary muscle still recovering" | hourglass |
| 4 | Recovery fatigued | "Primary muscle fatigued — consider lighter work" | exclamationmark.circle |

---

## 10. Apple Intelligence Integration

Two integration points exist; both fall back to templates on error.

### 10.1 Insight Enhancement (AppleIntelligenceInsightGenerator)

**Status:** Fully implemented and wired via AppContainer.

Wraps `TemplateInsightGenerator` — generates template highlights first, then rewrites each via `LanguageModelSession`.

**Per-highlight prompt:**
```
"Rewrite this training insight in a concise, motivating coach tone (max 15 words).
Type: [highlightType]. Original: [highlightDetail]"
```

**Block summary prompt:**
```
"Compare these two training blocks and summarize the key differences
in 1-2 sentences as a strength coach would. Dimension changes: [deltas]"
```

**Drift explanation prompt:**
```
"Explain this training drift to a gym-goer in 1-2 sentences.
Overall drift: [X]%. Changes: [deltas]"
```

**Post-workout bullet enhancement** (`enhancePostWorkoutBullets()`):

Rewrites coaching bullet detail text via `LanguageModelSession` for more natural, coach-like phrasing. Falls back to original template text on error. Called from `CoachingInsightService.generatePostWorkoutDebrief()` when `InsightTextGenerating` is available.

**Diagnostics:** Tracks `highlightsEnhanced`, `highlightsFalledBack`, `lastError`, `lastGenerationTime`.

### 10.2 Coaching Communication (FoundationModelsCoachingProvider)

**Status:** Implemented (as of this session). Wired via AppContainer's `coachingService`.

**Plan adjustment prompt:**
```
"You are a strength coach. Explain this plan adjustment to a [level]-level trainee
in 2-3 sentences. Adjustment: [type]. Context: [description]. Be encouraging and concise."
```

**Post-workout prompt:**
```
"You are a strength coach. Write a brief post-workout summary (2-3 sentences)
for a [level]-level trainee who just did: [exercises]. Be encouraging and specific."
```

---

## 11. Key Thresholds & Constants

### Feature Unlocks (24 features)

| Feature | Workouts Required |
|---------|:-:|
| Post-Workout Debrief | 1 |
| Weight Suggestions | 5 |
| Weekly Digest | 5 |
| Similar Workouts | 5 |
| Quality Score | 5 |
| Strength Trends | 5 |
| Recommendations | 5 |
| Pre-Workout Context | 5 |
| Effort Creep Warning | 10 |
| Exercise Hints | 10 |
| Plateau Detection | 10 |
| Archetype Clustering | 10 |
| Achievements | 10 |
| Sequence Prediction | 15 |
| Workout Suggestion | 15 |
| Muscle Balance | 19 |
| Advanced Insights | 19 |
| Trajectory Analysis | 19 |
| Training Fingerprint | 19 |
| Muscle Neglect | 19 |
| Recovery Timeline | 20 |
| Time-of-Day Analysis | 20 |
| Change Point Detection | 20 |
| Volume-Response Curves | 50 |

### Analysis Thresholds

| Parameter | Value | Service |
|-----------|:-----:|---------|
| Min workouts for advanced | 19 | WorkoutAnalyticsService |
| Min workouts for ACWR | 8 (+ 14 calendar days) | TrainingLoadService |
| Min workouts for deload | 6 | DeloadDetectionService |
| Min workouts for anomalies | 5 | AnomalyDetectionService |
| Min weeks for plateau | 4 | PlateauDetectionService |
| Min weeks for phases | 4 | PhaseDetectionService |
| Min workouts per block | 3 | BlockComparisonService |
| Min similar workouts in drift baseline | 3 | TrainingDriftService |
| Min similar workouts in drift recent | 2 | TrainingDriftService |
| Similarity floor | 0.70 | WorkoutAnalyticsService |
| Insights cache TTL | 60s | WorkoutAnalyticsViewModel |
| Vector cache TTL | 300s | WorkoutAnalyticsService |

### Equations & Constants

| Constant | Value | Used In |
|----------|:-----:|---------|
| Acute EWMA λ | 0.25 | TrainingLoadService |
| Chronic EWMA λ | 0.069 | TrainingLoadService |
| Quality EWMA λ | 0.30 | WorkoutQualityScoreService |
| 1RM EWMA α | 0.30 | SessionExecutionService |
| Anomaly EWMA λ | 0.10 | AnomalyDetectionService |
| pct1RM cap | 1.50 | AnalyticsCalculations |
| Volume primary weight | 70% | AnalyticsCalculations |
| Volume secondary weight | 30% split | AnalyticsCalculations |
| Improvement threshold | Dynamic: 5% beginner, 2% intermediate, 0% advanced | PlateauDetectionService |
| Dimension drift threshold | 10% (0.10) | DriftService/BlockService/AnomalyService |
| Anomaly z-score | 2.0 | AnomalyDetectionService |
| Trend progressing | > 0.5 kg/wk | OverloadTrackingService |
| Trend regressing | < −0.5 kg/wk | OverloadTrackingService |
| Imbalance mild | ≥ 1.5× ratio | MuscleBalanceService |
| Imbalance severe | ≥ 2.0× ratio | MuscleBalanceService |
| Recovery ready | ≥ 100% | RecoveryEstimationService |
| Recovery recovering | ≥ 70% | RecoveryEstimationService |
| ACWR under training | < 0.6 | TrainingLoadService |
| ACWR optimal | 0.6–1.3 | TrainingLoadService |
| ACWR caution | 1.3–1.5 | TrainingLoadService |
| ACWR danger | > 1.5 | TrainingLoadService |
| Deload urgency floor | 0.15 | DeloadDetectionService |
| Deload ACWR trigger | > 1.4 | DeloadDetectionService |
| Deload overdue | > 6 weeks | DeloadDetectionService |
| Performance decline | 40%+ exercises | DeloadDetectionService |
| Deload volume threshold | < 60% of 4-wk avg | DeloadDetectionService |
| Quality CV full score | ≤ 0.25 | WorkoutQualityScoreService |
| Quality CV mid range | ≤ 0.80 | WorkoutQualityScoreService |
| Quality balance pair ratio perfect | 1.0× | WorkoutQualityScoreService |
| Quality balance pair ratio zero | 3.0× | WorkoutQualityScoreService |
| Volume score sweet spot (asymmetric) | 0.8×–1.4× → 100 | WorkoutQualityScoreService |
| Volume score below average | < 0.8× → linear to 0 | WorkoutQualityScoreService |
| Volume score above sweet spot | > 1.4× → taper to floor 60 | WorkoutQualityScoreService |
| 1RM outlier threshold | 15% | SessionExecutionService |
| 1RM regression guard | 5% drop min | SessionExecutionService |

### Vector Normalization Constants

| Dimension | Max Value |
|-----------|:-:|
| Total volume | 20,000 kg |
| Average weight | 150 kg |
| Average reps | 30 |
| Set count | 100 |
| Exercise diversity | 15 |
| Duration | 5,400 sec (90 min) |
| PR count | 10 |
| Time of day | 1,440 (minutes in day, linear) |

Constants are tuned to the 90th–95th percentile of real training data. `vectorVersion` (in `UserPreferencesService`) tracks the current constant set; vectors auto-recompute on version change.

### Coaching Service Constants

| Constant | Value | Used In |
|----------|:-----:|---------|
| Weight suggestion deload modifier | 60% of e1RM | WeightSuggestionService |
| Recovery fatigued modifier | −10% | WeightSuggestionService |
| Recovery recovering modifier | −5% | WeightSuggestionService |
| ACWR danger modifier | −15% | WeightSuggestionService |
| ACWR caution modifier | −10% | WeightSuggestionService |
| Weight rounding | Nearest 2.5 kg | WeightSuggestionService |
| Effort creep min sessions | 3 | WeightSuggestionService |
| Effort creep RPE slope threshold | > 0.3/session | WeightSuggestionService |
| Adherence window | 8 weeks | AdherenceAnalysisService |
| Dropout risk high | gap > mean + 2σ AND declining | AdherenceAnalysisService |
| Dropout risk moderate | gap > mean + σ | AdherenceAnalysisService |
| Muscle neglect slope threshold | < −0.5 sets/week | CoachingInsightService |
| Muscle neglect decline threshold | > 20% | CoachingInsightService |
| Archetype k range | 2..min(8, n/3) | WorkoutArchetypeService |
| Archetype selection | Best silhouette score | WorkoutArchetypeService |
| Fingerprint entropy | Normalized Shannon (0–1) | WorkoutArchetypeService |
| Trajectory steady state | velocity < 0.05 AND accel < 0.02 | TrajectoryAnalysisService |
| Trajectory spinning wheels | velocity < 0.05 AND angular change > 45° | TrajectoryAnalysisService |
| CUSUM threshold | 2.0 | ChangePointDetectionService |
| CUSUM EWMA α | 0.3 | ChangePointDetectionService |
| Time-of-day min per window | 3 workouts | ChangePointDetectionService |
| Time-of-day min delta | > 5% quality difference | ChangePointDetectionService |
| Volume-response min workouts | 50 | AchievementTrackingService |
| Volume-response min data points | 12 per muscle | AchievementTrackingService |
| Volume-response min R² | 0.3 | AchievementTrackingService |
| Iron Consistency badge | 8 consecutive weeks | AchievementTrackingService |
| Progressive Loader badge | 3+ exercises progressing | AchievementTrackingService |

### Additional Constants

| Constant | Value | Used In |
|----------|:-----:|---------|
| Superset filter threshold | 15s | WorkoutQualityScoreService |
| Min valid intervals for consistency | 2 | WorkoutQualityScoreService |
| Default consistency score (insufficient data) | 80.0 | WorkoutQualityScoreService |
| EPOC cap | 10% | CalorieEstimationService |
| Compound active time per set | 40s | CalorieEstimationService |
| Isolation active time per set | 25s | CalorieEstimationService |
| Per-muscle ACWR method | Rolling sum (7d/28d) | TrainingLoadService |
| Vector version | 1 | UserPreferencesService |

---

## File Reference

### Analytics Services (`Shared/Services/Analytics/`)

| File | Purpose |
|------|---------|
| WorkoutAnalyticsService.swift | Main orchestrator |
| WorkoutVectorizer.swift | 18-dim vectorization |
| VectorSearchService.swift | Cosine similarity search |
| AnalyticsCalculations.swift | Shared formulas (e1RM, IWV, EWMA, OLS) |
| PlateauDetectionService.swift | Stall detection |
| MuscleBalanceService.swift | Antagonist imbalance |
| ExerciseRecommendationService.swift | Exercise suggestions |
| TrainingLoadService.swift | ACWR computation |
| OverloadTrackingService.swift | e1RM trending |
| DeloadDetectionService.swift | Fatigue signals |
| VolumeLandmarkService.swift | MEV/MRV ranges |
| RecoveryEstimationService.swift | Recovery hours |
| TrainingDriftService.swift | Baseline divergence |
| PhaseDetectionService.swift | Phase classification |
| BlockComparisonService.swift | Block diff |
| AnomalyDetectionService.swift | Outlier detection |
| WorkoutQualityScoreService.swift | Quality metrics |
| AnalyticsFeatureGate.swift | Progressive unlocking (24 features) |
| CoachingInsightService.swift | Post-workout debrief, weekly digest, exercise hints, muscle neglect |
| WeightSuggestionService.swift | e1RM-based weight suggestions, effort creep detection |
| AdherenceAnalysisService.swift | Frequency, streaks, dropout risk |
| TrajectoryAnalysisService.swift | Vector-space velocity/acceleration analysis |
| WorkoutArchetypeService.swift | k-means++ clustering, training fingerprints |
| ChangePointDetectionService.swift | CUSUM change point detection, time-of-day analysis |
| AchievementTrackingService.swift | Badge achievements, volume-response curves |
| TemplateInsightGenerator.swift | Template text |
| AppleIntelligenceInsightGenerator.swift | AI-enhanced text |
| InsightTextGenerating.swift | Generator protocol |

### Progression Services (`Shared/Services/Progression/`)

| File | Purpose |
|------|---------|
| TrainingStatusDetector.swift | Beginner/Intermediate/Advanced |
| ProgramDesignService.swift | Periodization design |
| SessionExecutionService.swift | 1RM EWMA + APRE |
| AdaptiveAdjustmentService.swift | Auto-adjustments |
| PlanAnalyticsService.swift | Plan progress |
| CoachingCommunicationService.swift | Coaching text |
| AppleIntelligenceAvailabilityService.swift | AI availability check |

### Analytics UI Views (`iOS/Features/Analytics/Views/`)

| File | Purpose |
|------|---------|
| InsightsCardView.swift | Dashboard compact card |
| AnalyticsDashboardView.swift | Full analytics page |
| AdvancedInsightsCardView.swift | Advanced summary card |
| AdvancedInsightsView.swift | Full advanced detail |
| ExerciseInsightsView.swift | Per-exercise insights |
| SimilarWorkoutsView.swift | Similar workout list |
| WorkoutQualityScoreView.swift | Quality score display |

### Coaching UI Views

| File | Location | Purpose |
|------|----------|---------|
| PostWorkoutSummaryView.swift | iOS/Features/Workout/Views/ | Full-screen post-workout debrief sheet |
| PreWorkoutContextCard.swift | iOS/Features/Workout/Views/ | Pre-workout recovery/ACWR/adherence card |
| WeeklyDigestCard.swift | iOS/Features/Dashboard/Views/ | Dashboard week-over-week comparison card |

### Domain Models (`Shared/Models/Domain/Analytics/`)

WorkoutInsights, WorkoutVector, AnalyticsHighlight, TrainingLoad, OverloadTrend, DeloadRecommendation, TrainingDrift, TrainingPhase, RecoveryPattern, OptimalVolumeRange, PlateauAnalysis, MuscleBalance, ExerciseRecommendation, SimilarWorkout, WorkoutQualityScore, BlockComparison, WorkoutAnomaly, CoachingInsight, ExerciseHint, ExerciseCoachingData, PostWorkoutDebrief, SessionComparison, WeightSuggestion, EffortCreepWarning, AdherenceAnalysis, TrajectoryAnalysis, WeeklyDigest, WorkoutArchetype, TrainingFingerprint, MuscleNeglectWarning, WorkoutSuggestion, ArchetypePrediction, TrainingChangePoint, TimeOfDayAnalysis, Achievement, VolumeResponseCurve
