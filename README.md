# HellBentIron

A no-nonsense strength training tracker for iPhone and Apple Watch. Built with SwiftUI and SwiftData.

Built for lifters who want to log their workouts quickly and get back to the bar. No accounts, no subscriptions, no cloud — your data stays on your device.

## Features

### iPhone

- **Dashboard** — overview of recent workouts, weekly volume (bodyweight-aware), EWMA-smoothed quality trend, quick-start buttons, and active Watch workout banner
- **Workout Templates** — create templates for your favorite routines. Start a workout from a template and adjust on the fly — add exercises, skip exercises, change the weight. Templates save time without locking you in.
- **Template Library** — 9 pre-built templates (Push/Pull/Leg Day, Upper/Lower Body, Full Body A & B, Chest & Triceps, Back & Biceps). Browse, preview exercises, and add to your collection as fully editable copies.
- **Quick Start** — no template? Start an empty workout and add exercises as you go. The full exercise library is always one tap away.
- **Active Workout** — log sets with weight/reps, RPE tracking, automatic rest timer, exercise navigation. Tap set number to change type — warm-up, drop set, failure, or rest-pause.
- **Set Types** — five set types (normal, warm-up, drop set, failure, rest-pause). Configure per-set in templates or toggle during workout. Warm-up sets are automatically excluded from personal records, volume totals, and calorie estimates.
- **Exercise Library** — 326 built-in exercises covering barbell, dumbbell, kettlebell, cable, machine, bodyweight, calisthenics, and more. Custom exercise support included.
- **Workout History** — review past workouts with full exercise and set detail
- **Progress Tracking** — automatic personal record detection. Hit a new PR and you'll know it.
- **Workout Analytics** — on-device vector analytics with EWMA-smoothed quality scoring, plateau detection, muscle balance tracking, and exercise recommendations. No cloud, no AI API calls — pure math on your device.
- **Progression Planning** — deterministic periodization engine that generates complete 12-week training programs. See [Progression Planning](#progression-planning) below.
- **Webhook Integration** — POST workout JSON to any external endpoint after every completed workout (openClaw PT, AI trainers, n8n, Zapier, etc.)
- **Settings** — weight unit (kg/lbs), rest timer duration, webhook configuration, and preferences
- **Widgets** — home screen widgets (Training Hub with interactive workout controls, quality score, Workout Summary, Weekly Progress, Streak) and Live Activities via WidgetKit and ActivityKit

### Apple Watch

- **Quick Start** — pick exercises and start a workout directly from the wrist
- **Template Workouts** — start workouts from templates synced from iPhone
- **Today's Plan** — planned sessions from the active progression plan appear on Watch, ready to start with pre-filled weights and reps
- **Set Logging** — weight and reps input with +/- buttons and Digital Crown rotation. Set type badges (warm-up, drop, etc.) shown per set.
- **Unit-Aware Steps** — 2.5 kg or 5 lbs increments based on user preference
- **Live Metrics** — real-time heart rate, active calories, and duration via HealthKit sensors
- **Rest Timer** — automatic rest countdown between sets with dedicated timer view. Per-exercise rest time overrides (set in templates, synced to Watch). Pause/resume support. Background notification when timer completes.
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

A 5-step wizard guides plan creation:

1. **Goal** — select a primary training goal (strength, hypertrophy, power, or general fitness). Each goal defines an intensity range and rep scheme.
2. **Program Type** — choose a periodization model: linear, daily undulating, weekly undulating, or block.
3. **Exercises** — pick exercises from the library. For each exercise, the app estimates your current 1RM from workout history (or you enter it manually).
4. **Schedule** — set training days per week (1–7) and assign each day to a specific weekday. Optionally link a **workout template** to each day and pick which exercises train on which days — when linked, the plan merges the template's structure (exercise order, notes) with the plan's progression-driven weights and reps.
5. **Start Date** — pick a start date (defaults to the next training day on or after today). The engine computes concrete **scheduled dates** for every session based on the start date and training days. Sessions show their date in the plan detail view and can be individually rescheduled.

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

The plan's stored 1RM values are updated after each session using an **asymmetric EWMA**:

- **Upward (PR):** `new_1RM = estimated` — accepted immediately so PRs reflect instantly
- **Downward:** `new_1RM = 0.3 × estimated + 0.7 × current` — smoothed to filter out bad days
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

### Date Scheduling

Plans compute concrete dates for every session. The engine anchors training days to the user's chosen start date (not Monday-aligned). Sessions can be rescheduled individually from the plan detail view. Overdue sessions (date in the past, not completed) are visually flagged.

### Apple Intelligence Integration

The progression module includes a two-tier coaching layer:

- **iOS 26+** (Apple Intelligence): routes coaching text through Apple's on-device Foundation Models for context-aware explanations tailored to the lifter's plan and performance
- **iOS 17–25**: falls back to structured template strings that adapt coaching tone by training level — encouraging and educational for beginners, data-driven for intermediates, concise and technical for advanced lifters

The AI-ready model layer includes structured inputs for natural language plan creation (goal descriptions, experience, equipment, injury limitations), workout note signal extraction (pain, fatigue, sleep quality), and post-workout narrative summaries. Plan creation source is tracked (structured wizard vs. natural language) for future NL-driven plan generation.

---

## Workout Analytics

All analytics run entirely on-device — no cloud, no AI API calls, no data leaves your phone. Every workout is converted into an 18-dimensional feature vector that captures volume, intensity, muscle targeting, and training patterns. As you log more workouts, the app progressively unlocks deeper insights.

### Progressive Unlocks

Analytics features are hidden until there's enough training data for them to be meaningful. The insights card doesn't appear on the dashboard until you're close to the first unlock. Each feature tells you how many more workouts you need. 24 features unlock progressively from workout 1 to 50+.

| Workouts | What Unlocks |
|---|---|
| 1+ | Post-workout debrief with stats and coaching bullets |
| 5+ | Quality scores, weight suggestions, pre-workout context, weekly digest, similar workouts |
| 10+ | Plateau detection, exercise hints, effort creep warnings, archetype clustering, achievements |
| 15+ | Workout suggestions, sequence prediction |
| 19+ | Advanced insights, trajectory analysis, training fingerprints, muscle neglect alerts |
| 20+ | Recovery timeline, time-of-day analysis, change point detection |
| 50+ | Personal volume-response curves (MEV/MAV/MRV from your own data) |

### Under the Hood

**Vectorization** — each workout is encoded as an 18-dimensional vector capturing total volume, exercise count, intensity distribution, muscle group coverage, rest patterns, and more. Normalization constants are tuned to the 90th–95th percentile of real training data (e.g., volume ÷ 20,000 kg, weight ÷ 150 kg, duration ÷ 5,400s). Time of day uses a linear mapping (minuteOfDay / 1440) to avoid cyclical encoding collisions. Vectors are L2-normalized and searched using cosine similarity via Apple Accelerate/vDSP. Centroids are re-normalized after averaging to maintain accurate similarity scores.

**Plateau Detection** — tracks max estimated 1RM (e1RM) per exercise per week using Epley/Brzycki formulas. Improvement thresholds scale dynamically by training status: 5% for beginners, 2% for intermediate, 0% for advanced (maintaining strength counts as progress). When e1RM flatlines for 2+ weeks, the app identifies the stall and suggests variations.

**Muscle Balance** — tracks 6 antagonist muscle pair ratios (chest/back, quads/hamstrings, biceps/triceps, shoulders/lats, core/lower back, glutes/hip flexors) and flags imbalances at three severity levels (mild/moderate/severe) with corrective exercise suggestions.

**Quality Score** — two-level scoring system across four equally-weighted dimensions (25 points each):

*Per-workout scores* are computed on workout completion and shown on the completion sheet and workout detail view. Fixed color thresholds: green (80+), gold (60-79), orange (40-59), red (<40).

*Aggregate quality* is an EWMA-smoothed (λ=0.3) trend across all completed workouts, shown on the analytics dashboard as "Training Quality". Color coding is percentile-based (relative to the user's own EWMA history): green = top quartile, gold = 50-75th, orange = 25-50th, red = bottom quartile. A trend badge shows percentage change vs. the EWMA value ~4 weeks ago. For users with fewer than 3 workouts, a simple average is shown with no trend. The aggregate score is also surfaced in the home screen widget.

The four scoring dimensions:

- **Volume** — compares each muscle group's session volume against its own 12-week per-session average (70/30 primary/secondary split). Bodyweight exercises use the user's body weight (from HealthKit or preferences). A ±20% deadband scores 100; deviations taper linearly to 0 at ±100%.
- **Intensity** — compares each set's estimated 1RM to the historical best for that exercise over the last 6 months. The current workout is excluded from the lookup so you're scored against past performance, not yourself.
- **Consistency** — coefficient of variation of rest intervals between consecutive sets (capped at 10 minutes, intervals ≤15s filtered to exclude superset/drop-set transitions). Low CV (≤0.25) scores 100; high CV (≥0.8) scores 30. Minimum 2 valid intervals required; defaults to 80 if fewer.
- **Balance** — uses Intensity-Weighted Volume (IWV = reps × %1RM) aggregated over a 12-week window across all workouts, scored against 6 antagonist pairs. A 1:1 ratio scores 100; a 3:1 ratio scores 0. Pairs where only one side was trained score 0; untrained pairs are excluded.

Per-workout scores are cached by workout ID, and the history-accepting overload avoids redundant data fetches when computing aggregate or daily quality bars.

### Advanced Insights (19+ workouts)

Once unlocked, a compact **Advanced Insights** card appears on the analytics dashboard showing a training load gauge, current training phase, top insight, and muscle recovery summary. Tapping it opens a full detail view with all sections below. All calculations use the **e1RM effort ratio** (set e1RM / historical best) and **IWV** (reps × %1RM) — never RPE.

**Training Load (ACWR)** — session load is the sum of IWV across all working sets. Systemic ACWR uses daily calendar EWMA (λ=0.25 acute, λ=0.069 chronic) so rest days properly decay fatigue. Requires 8 workouts spanning 14+ days before activating (cold-start guard). The Acute:Chronic Workload Ratio determines your load zone: under-training (<0.6), optimal (0.8–1.3), caution (1.3–1.5), or danger (>1.5). Per-muscle-group ACWR uses a rolling sum method (7-day acute / 28-day chronic ÷ 4) to avoid saw-tooth artifacts for muscles trained 1–2×/week.

**Progressive Overload** — per-exercise best e1RM per calendar week, with linear regression to determine trend. Exercises are classified as progressing (>0.5 kg/wk), plateau (±0.5 kg/wk), or regressing (<−0.5 kg/wk). Requires at least 4 weeks of data.

**Deload Detection** — monitors four fatigue signals: intensity creep (effort ratio increasing over 3 sessions), performance decline (e1RM dropping in 40%+ exercises over 2 sessions), overdue (>6 weeks since volume dropped below 60% of 4-week average), and sustained high ACWR (>1.4 for 2+ weeks). Triggers are combined into an urgency score (0–1) with a suggested action.

**Volume Landmarks** — weekly hard sets per muscle group compared against population-based MEV (Minimum Effective Volume) and MRV (Maximum Recoverable Volume) ranges, adjusted by training status. Primary muscles get full credit; secondary muscles get 0.5× credit divided by the number of secondaries (e.g., bench press: 1.0 chest + 0.25 triceps + 0.25 shoulders = 1.5 total, not 2.0).

**Recovery Estimation** — per-muscle-group recovery status based on time since last trained, volume (set count modifier), and intensity (effort ratio modifier) applied to base recovery hours. Status is green (ready, ≥100%), yellow (recovering, ≥70%), or red (fatigued, <70%).

**Training Drift** — compares the centroid of recent workout vectors (last 14 days) against a baseline centroid (15–45 days ago) using cosine similarity. Per-dimension drift is reported for any feature with |delta| > 0.10, with a summary of what's shifting (e.g., more isolation work, lower volume).

**Phase Detection** — weekly centroid vectors are classified against prototype training phases (accumulation, intensification, peaking, deload, mixed) using key vector dimensions (volume, weight, reps, sets, compound ratio). A 3-window moving mode filter smooths noisy transitions.

**Block Comparison** — auto-compares the current 4-week block against the previous 4-week block via centroid cosine similarity and per-dimension deltas (>10% reported). Generates a text summary of key differences.

**Anomaly Detection** — maintains an EWMA centroid (L2 re-normalized) over all workout vectors and flags workouts where the anomaly score (1 − cosine similarity to centroid) exceeds mean + 2×stddev. The top 3 deviating dimensions are reported per anomaly.

**Smart Highlights** — a prioritized feed of natural-language insights generated from all the above data. Warnings (deload needed, danger ACWR, over-volume) rank highest, followed by improvements (progressing exercises, optimal load), then milestones (phase transitions, training drift). On iOS 26+ with Apple Intelligence, highlights are generated by the on-device Foundation Models framework for varied, coach-like text; older devices use structured templates.

### Coaching Insights (progressive, 1–50+ workouts)

Three coaching surfaces deliver contextual intelligence at the moments it matters — not buried in a dashboard you never open.

**Post-Workout Debrief** — a summary sheet after every workout showing duration, volume, sets, PRs, a quality score donut (animated), and 2–3 contextual coaching bullets. Bullets are priority-ranked from 8 insight sources: PRs, ACWR warnings, quality score deltas, overload trends, volume changes, under-training signals, recovery notes, and session comparisons (cosine similarity match against your entire history). On iOS 26+, Apple Intelligence rewrites bullet text for natural phrasing.

**Pre-Workout Context** — recovery status per muscle group (colored dots: green/ready, orange/recovering, red/fatigued), ACWR gauge bar with zone label, adherence stats (days since last workout, weekly frequency, current streak), and start buttons. Shown on the active workout screen when analytics data is available (5+ workouts).

**Inline Exercise Coaching** — per-exercise weight suggestions (e1RM extrapolation + inverse Brzycki, adjusted for recovery status and ACWR: −10% fatigued, −5% recovering, −15% danger ACWR, −10% caution, 60% for deload, rounded to 2.5 kg), effort creep warnings (RPE slope > 0.3/session without strength gains over 3+ sessions), and exercise hints (plateau, absence, trending, recovery).

**Weekly Digest** — a dashboard card shown Mon–Wed: last week's workout count, volume delta %, PRs, and a top coaching insight (best progressing exercise, volume shift, or consistency note).

**Training Archetypes** — k-means++ clustering (k=2..min(8, n/3), cosine distance, silhouette score selection) groups your workouts into patterns like "Push Day", "Leg Day", "Full Body". A training fingerprint tracks archetype distribution entropy (variety) and stability over time.

**Trajectory Analysis** — 3-window centroid differencing computes velocity and acceleration of your training changes in 18-dimensional vector space. Detects steady state, deceleration, volume stagnation, muscle drift, spinning wheels (low velocity + high angular change), and predicts weeks to plateau.

**Achievements** — 6 quality-based badges (Progressive Loader, Plateau Breaker, Iron Consistency, Balanced Builder, Volume Explorer, Smart Recovery) earned from training milestones. Badges persist in UserDefaults.

**Adherence Analysis** — 8-week frequency trends via linear regression, gap analysis (mean + σ), streak tracking (consecutive weeks), dropout risk classification (high = gap > mean + 2σ and declining frequency), and expected next workout prediction.

**Change Point Detection** — CUSUM on the dissimilarity time series of workout vectors detects significant training shifts. Per-change-point dimension analysis shows what shifted (e.g., "volume increased", "muscle coverage decreased").

**Time-of-Day Analysis** — compares quality scores across 4 training windows (morning, afternoon, evening, night) to find your best time to train. Requires ≥3 workouts per window and >5% quality difference.

**Volume-Response Curves** (50+ workouts) — per-muscle quadratic regression of weekly sets vs. overload slope yields personal MEV, MAV, and MRV values derived entirely from your own training data.

---

## Calorie Estimation

Calorie tracking works differently depending on which device runs the workout.

### Apple Watch — Sensor-Based

When a workout runs on Apple Watch, calorie data comes directly from the hardware. The Watch uses its optical heart rate sensor, accelerometer, and gyroscope via `HKLiveWorkoutBuilder` to measure active energy burned in real time. These are the same sensor-fused calorie numbers that populate the Move ring. No equations are used — it's measured data from the wrist.

Live metrics (heart rate, active calories, elapsed time) are displayed during the workout and the final values are saved to HealthKit as an `HKWorkout` with `.traditionalStrengthTraining` activity type.

### iPhone — Equation-Based

When a workout is logged on iPhone without Watch involvement, calories are estimated using a research-based model with three components:

1. **MET-based session calories** — `MET × bodyWeight(kg) × hours`. MET values are sourced from the [2024 Compendium of Physical Activities (Herrmann et al.)](https://pacompendium.com/) and assigned per exercise category (barbell, kettlebell, machine, bodyweight, etc.) with separate values for compound and isolation movements. Active lifting time is estimated per set: **40 seconds for compound, 25 seconds for isolation** exercises. The equipment MET applies only to active time; rest time uses a standing MET of 1.5. This prevents overestimation for lifters who take long rest periods.

2. **Volume bonus** — based on [Lytle et al. (2019)](https://doi.org/10.1249/MSS.0000000000002111), a regression model (R²=0.75) for resistance exercise energy expenditure. Uses a **dynamic Lytle coefficient** that scales with compound ratio: ~1.0 kcal/1000 kg for all-isolation workouts up to ~3.5 kcal/1000 kg for all-compound workouts, reflecting the greater energy cost of multi-joint movements.

3. **EPOC (Excess Post-Exercise Oxygen Consumption)** — 6–10% of session calories (capped at 10%), scaled by average RPE when available, or compound exercise ratio as fallback.

The only personal data used is **body weight** (from HealthKit or user preferences). No age, height, or sex data is collected. Warmup sets are excluded. Results are cross-validated against [Joao et al. (2021)](https://doi.org/10.3390/app11125592) (~6 kcal/min average).

---

## Widgets and Live Activities

### Home Screen Widgets

- **Training Hub** (small, medium, large) — adaptive widget that switches between analytics mode and active workout mode:
  - **Analytics mode** (no active workout): small shows a rotating insight card from analytics highlights; medium shows a 7-day calendar strip, weekly progress, quality score, top 2 highlights, and next planned session; large adds a progress ring (workouts vs. weekly goal), top 3 highlights, and next planned session with exercise preview
  - **Active workout mode** (during workout): small shows current exercise name, set count, and elapsed time; medium adds next set targets and a rest timer countdown or "Complete Set" button; large shows a full workout dashboard with rest timer controls and next exercise preview
  - **Widget controls** — complete set, skip exercise, add rest time, skip rest — all work without opening the app
  - Weekly goal reads from the active progression plan. Highlights unlock progressively: recommendations at 5+ workouts, plateau warnings at 10+, full advanced insights at 19+
  - Volume and quality data in the widget use the same calendar-week (Monday-start) boundaries and bodyweight-aware calculations as the dashboard, so numbers always match
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
│   │   ├── Analytics/       # Vectorizer, VectorSearch, PlateauDetection, MuscleBalance, TrainingLoad, Overload, Deload, Drift, Phase, Recovery, Anomaly, InsightText,
│   │   │                    # CoachingInsight, WeightSuggestion, Adherence, Trajectory, Archetype, ChangePoint, Achievement
│   │   └── Progression/     # ProgramDesignService, SessionExecutionService, AdaptiveAdjustmentService, TrainingStatusDetector
│   ├── ViewModels/          # Shared ViewModels (WorkoutVM, TemplateVM, AnalyticsVM, ProgressionPlanVM)
│   └── DI/                  # AppContainer (dependency injection)
├── iOS/                     # iPhone app (StrengthTrackeriOS)
│   ├── App/                 # App entry point, ContentView
│   └── Features/            # Dashboard (WeeklyDigestCard), Workout (PostWorkoutSummaryView, PreWorkoutContextCard), Templates, History, Progress, Progression, Settings
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
