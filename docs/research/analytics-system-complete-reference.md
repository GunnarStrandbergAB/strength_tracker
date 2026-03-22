# HellBentIron Analytics System — Complete Reference

> Exhaustive documentation of every analytics service, equation, data model, UI element, and user-facing text string in the StrengthTracker analytics system.
> Generated 2026-03-22.

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
   - 8.8 Color Coding Reference
   - 8.9 Number Formatting Rules
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
    └─ Phase 4 (19+ workouts — "Advanced Insights")
        ├─ TrainingLoadService (ACWR)
        ├─ OverloadTrackingService
        ├─ DeloadDetectionService
        ├─ TrainingDriftService
        ├─ PhaseDetectionService
        ├─ BlockComparisonService
        ├─ AnomalyDetectionService
        └─ InsightTextGenerator (Template or Apple Intelligence)
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

`AnalyticsFeatureGate` gates features behind workout count thresholds:

| Phase | Threshold | Features Unlocked |
|-------|-----------|-------------------|
| **1** | 1–4 workouts | Basic stats, PR tracking |
| **2** | 5+ workouts | Similar Workouts, Quality Score, Strength Trends, Exercise Recommendations |
| **3a** | 10+ workouts | Plateau Detection |
| **3b** | 19+ workouts | Muscle Balance, Advanced Insights |
| **3c** | 20+ workouts | Recovery Timeline |

**UI display names and descriptions:**

| Feature | Display Name | Description Shown |
|---------|-------------|-------------------|
| similarWorkouts | "Similar Workouts" | "Find past workouts that match your current session" |
| qualityScore | "Quality Score" | "Rate each workout on volume, intensity, and balance" |
| strengthTrends | "Strength Trends" | "Track strength changes over time per exercise" |
| exerciseRecommendations | "Recommendations" | "Get exercise suggestions based on your training gaps" |
| plateauDetection | "Plateau Detection" | "Spot exercises where progress has stalled" |
| muscleBalance | "Muscle Balance" | "Check if opposing muscle groups are trained evenly" |
| recoveryTimeline | "Recovery Timeline" | "Optimal rest days between sessions" |
| advancedInsights | "Advanced Insights" | "Deep analysis across your full training history" |

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
5. WorkoutAnalyticsViewModel receives aggregate
6. UI views render from ViewModel properties
7. Widget data refreshed via WidgetDataService
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
| 0 | `total_volume_norm` | `Σ(weight × reps)` for all completed non-warmup sets | `÷ 50,000 kg` |
| 1 | `avg_weight_norm` | Mean weight across all sets | `÷ 300 kg` |
| 2 | `avg_reps_norm` | Mean reps across all sets | `÷ 30` |
| 3 | `set_count_norm` | Total completed non-warmup sets | `÷ 100` |
| 4 | `exercise_diversity` | Count of unique exercises | `÷ 15` |
| 5 | `duration_norm` | Workout duration in seconds | `÷ 7,200 (2h)` |
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
| 17 | `time_of_day_sin` | `sin(hour × 2π / 24) × 0.5 + 0.5` | 0–1 |

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

Uses Apple Accelerate (`vDSP_dotprD`, `vDSP_vsdivD`) on iOS for performance.

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
centroid[i] = Σ vectors[j][i] / count
```

Arithmetic mean across all dimensions.

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
minImprovementThreshold = 1.05    (5% improvement required to reset stall counter)
```

#### Algorithm

For each exercise with 4+ weekly occurrences:

1. Group sets by calendar week (Monday start)
2. Compute weekly volume: `Σ(weight × reps)` for each week
3. Track consecutive stalled weeks:

```
for week i in 1..<weeks:
    if weeklyVolume[i] >= weeklyVolume[i-1] × 1.05:
        weeksStalled = 0    // 5% improvement resets counter
    else:
        weeksStalled += 1
```

4. Only report if `consecutiveWeeksStalled >= 2`
5. Sort results by weeks stalled descending

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

#### Acute-Chronic Workload Ratio

```
Session load = Σ IWV for all working sets
    where IWV = reps × pct1RM × (RPE / 10 if available)

Acute EWMA  (λ = 0.25)  — weights recent sessions heavily
Chronic EWMA (λ = 0.069) — smooth long-term baseline

ACWR = acuteEWMA.last / chronicEWMA.last
```

#### Load Zone Classification

| Zone | ACWR Range | Meaning |
|------|-----------|---------|
| Under Training | < 0.6 | Insufficient stimulus |
| Optimal | 0.6–1.3 | Ideal training window |
| Caution | 1.3–1.5 | High fatigue accumulation |
| Danger | > 1.5 | Critical overtraining risk |

Also computed **per muscle group** using primary muscle attribution. Only muscles with 4+ sessions of data included.

Minimum 4 completed workouts required.

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
Secondary muscle: 0.5 credit per set
Current weekly sets = sum over last 4 weeks ÷ 4, rounded to nearest int
```

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
```

#### Anomaly Detection

```
anomalyScore[i] = 1.0 − cosineSimilarity(vector[i], centroid)

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
    deviation = |ratio − 1.0|
    groupScore = max(0, 100 × (1 − max(0, deviation − 0.2) / 0.8))

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
CV = stddev(intervals) / mean(intervals)

if CV ≤ 0.25: score = 100
if CV ≤ 0.80: score = 100 − (CV − 0.25) × (70 / 0.55)
else:         score = 30
```

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

#### 1RM EWMA Smoothing

```
α = 0.3
Outlier threshold: 15% deviation rejection
Regression guard: only apply downward if estimated < 95% of current

smoothed1RM = 0.3 × estimated + 0.7 × current
```

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

```
sessionCalories = MET × bodyweight(kg) × time(hours)
volumeBonus = ~2.46 kcal per 1,000 kg total volume (Lytle coefficient)
epocCalories = 6–15% of session (varies by RPE and compound ratio)
totalCalories = session + volumeBonus + EPOC
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

### 8.8 Color Coding Reference

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

### 8.9 Number Formatting Rules

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

### Feature Unlocks

| Feature | Workouts Required |
|---------|:-:|
| Similar Workouts | 5 |
| Quality Score | 5 |
| Strength Trends | 5 |
| Recommendations | 5 |
| Plateau Detection | 10 |
| Muscle Balance | 19 |
| Advanced Insights | 19 |
| Recovery Timeline | 20 |

### Analysis Thresholds

| Parameter | Value | Service |
|-----------|:-----:|---------|
| Min workouts for advanced | 19 | WorkoutAnalyticsService |
| Min workouts for ACWR | 4 | TrainingLoadService |
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
| Improvement threshold | 5% (1.05×) | PlateauDetectionService |
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
| Volume score deviation tolerance | ±20% | WorkoutQualityScoreService |
| 1RM outlier threshold | 15% | SessionExecutionService |
| 1RM regression guard | 5% drop min | SessionExecutionService |

### Vector Normalization Constants

| Dimension | Max Value |
|-----------|:-:|
| Total volume | 50,000 kg |
| Average weight | 300 kg |
| Average reps | 30 |
| Set count | 100 |
| Exercise diversity | 15 |
| Duration | 7,200 sec |
| PR count | 10 |

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
| AnalyticsFeatureGate.swift | Progressive unlocking |
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

### Domain Models (`Shared/Models/Domain/Analytics/`)

WorkoutInsights, WorkoutVector, AnalyticsHighlight, TrainingLoad, OverloadTrend, DeloadRecommendation, TrainingDrift, TrainingPhase, RecoveryPattern, OptimalVolumeRange, PlateauAnalysis, MuscleBalance, ExerciseRecommendation, SimilarWorkout, WorkoutQualityScore, BlockComparison, WorkoutAnomaly
