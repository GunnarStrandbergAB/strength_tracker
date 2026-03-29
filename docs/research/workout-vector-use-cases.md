# Workout Vector Use Cases — Research Report

> Date: 2026-03-29
> Branch: vector_update
> Prerequisite: Fix muscle group aggregation bug (`.lats`, `.traps`, `.lowerBack`, `.forearms`, `.obliques` silently dropped from vector buckets)

## Background

Each workout is encoded as an 18-dimensional L2-normalized feature vector:

| Index | Feature | Range (pre-norm) | Source |
|-------|---------|-------------------|--------|
| 0 | total_volume_norm | 0–1 (vol/20000) | Sum of weight x reps |
| 1 | avg_weight_norm | 0–1 (weight/150) | Mean weight across sets |
| 2 | avg_reps_norm | 0–1 (reps/30) | Mean reps across sets |
| 3 | set_count_norm | 0–1 (sets/100) | Total completed sets |
| 4 | exercise_diversity | 0–1 (unique/15) | Unique exercise count |
| 5 | duration_norm | 0–1 (dur/5400s) | Session duration |
| 6 | chest_ratio | 0–1 | Chest vol / total vol |
| 7 | back_ratio | 0–1 | Back vol / total vol |
| 8 | legs_ratio | 0–1 | Legs vol / total vol |
| 9 | shoulders_ratio | 0–1 | Shoulders vol / total vol |
| 10 | arms_ratio | 0–1 | Arms vol / total vol |
| 11 | core_ratio | 0–1 | Core vol / total vol |
| 12 | compound_ratio | 0–1 | Barbell exercises / total |
| 13 | avg_rpe | 0–1 (RPE/10) | Mean RPE across sets |
| 14 | volume_vs_prev_7d | -1–1 | Volume change vs 7d avg |
| 15 | volume_vs_prev_30d | -1–1 | Volume change vs 30d avg |
| 16 | pr_count_norm | 0–1 (PRs/10) | Personal records hit |
| 17 | time_of_day | 0–1 (minute/1440) | Linear time mapping |

After feature computation, the full vector is L2-normalized (projected onto the unit hypersphere) so that dot product = cosine similarity.

### Current uses

1. **Anomaly detection** — EWMA centroid + 2-sigma outlier flagging
2. **Similar workout search** — cosine similarity nearest-neighbor (not surfaced in UI)
3. **Training drift** — 14d vs 15-45d centroid comparison
4. **Phase detection** — weekly centroid classification
5. **Block comparison** — 4-week block centroids compared

### Architectural note: store L2 magnitude

Several ideas below require access to pre-normalization feature values. Currently `WorkoutVectorizer.vectorize()` normalizes inline and discards the magnitude. Storing the L2 magnitude as a single additional field on `WorkoutVectorEntity` would allow reconstruction of raw features from `normalized_vector * magnitude`, unlocking ideas marked with (**).

---

## Category A: Vector Math & Analysis

These operate directly on the vector space using lightweight algorithms feasible on-device.

### A1. Workout Archetype Clustering

**What:** Auto-discover the user's distinct workout types (e.g., "heavy compounds", "chest & triceps hypertrophy", "light full-body") without manual labels.

**How:** k-means with k chosen by silhouette score (k=2..6). Cosine distance as metric (1 - dot product). Label clusters by their dominant vector dimensions — if dims 6+12 dominate the centroid: "Heavy Chest/Compounds".

**Enables:** Archetype frequency tracking, under-used archetype suggestions ("You haven't done a Leg Hypertrophy workout in 3 weeks"), and is the foundation for sequence prediction (A2).

**Data needed:** 10+ workouts. Re-cluster when a new vector falls far from all existing centroids.

**Feasibility:** High. k-means on 18 dims x 200 vectors completes in microseconds with Accelerate.

---

### A2. Workout Sequence Prediction (Markov Chain)

**What:** Given the user's last workout type (archetype from A1), predict what they'll train next and suggest optimal sequencing.

**How:** Build a first-order transition matrix over archetypes: P(next_type | current_type). Augment with day-of-week distributions and outcome data (quality score delta after each transition type).

**Reveals:**
- "Based on your patterns, today is likely a Leg Hypertrophy day (78%)"
- Which transitions produce the best outcomes (e.g., heavy legs -> light upper -> heavy push yields more PRs than back-to-back heavy days)
- Schedule disruption: "You usually train legs on Tuesdays — it's been 10 days"

**Data needed:** 20+ workouts for meaningful transition probabilities.

**Feasibility:** High. Counting + normalization, builds on A1.

---

### A3. Trajectory Curvature — Predictive Plateau Detection

**What:** Instead of waiting for e1RM to flatline (reactive), detect the pre-plateau state 2-3 weeks early by analyzing the shape of the vector trajectory through 18-dimensional space.

**How:**
1. Compute displacement vectors between consecutive workouts: d(i) = v(i+1) - v(i)
2. Compute cosine similarity between consecutive displacements: sim(d(i), d(i+1))
3. When displacements become orthogonal or opposing (cosine < 0), training is oscillating
4. When displacement magnitudes shrink (||d(i)|| -> 0), training is stagnating
5. The ratio magnitude / angular change = "trajectory efficiency"

**Reveals:** High magnitude + consistent direction = progressive overload. Low magnitude + high angular change = spinning wheels (shuffling exercises without progressing). This is predictive where PlateauDetectionService is reactive.

**Key insight:** Track curvature separately in the volume-weight-reps subspace (dims 0-2) vs. the muscle-distribution subspace (dims 6-11). Stagnation in the first with drift in the second = shuffling exercises without overloading.

**Data needed:** 5+ recent workouts for a window. Existing vectors suffice.

**Feasibility:** High. Vector subtraction + norms + cosine similarity — all in VectorSearchService already.

---

### A4. Vector Momentum — Adaptation Rate

**What:** Compute the "velocity" (first derivative) and "acceleration" (second derivative) of the vector trajectory to quantify how fast training is changing and whether adaptation is speeding up or slowing down.

**How:**
- Velocity: v(t) = vector(t) - vector(t-1)
- Acceleration: a(t) = v(t) - v(t-1)
- ||v(t)|| = training change rate; ||a(t)|| = training change acceleration

**Reveals:**
- Adaptation velocity plateau: ||v(t)|| consistently small + ||a(t)|| near zero = training has reached steady state
- Overreaching: rapidly increasing ||v(t)|| with negative acceleration in volume but positive in RPE = fatigue accumulating
- Supercompensation timing: after deload (large negative velocity), time to velocity reversal estimates recovery lag
- Historical comparison: "Your current change rate is 40% of what it was during your best PR streak"

**Data needed:** Existing vectors, 5+ for meaningful signal.

**Feasibility:** High. Vector subtraction and norms.

---

### A5. Change Point Detection — Automatic Program Logging

**What:** Detect when the user's training fundamentally shifted (started a new program, changed split) without requiring them to log it.

**How:**
1. Compute running dissimilarity: 1 - cosine(current_vector, EWMA_centroid_of_prior_workouts)
2. Apply CUSUM (Cumulative Sum control chart) to this series to find change points
3. At each change point, characterize the shift by comparing centroids before/after

**Reveals:**
- "You transitioned from accumulation to intensification around March 15th: +22% avg weight, -18% avg reps, +15% compound ratio"
- Automatic periodization journal without manual input
- Seasonal patterns over 12+ months of data

**Feasibility:** High. CUSUM is trivially implementable. PhaseDetectionService does a simpler version already with prototype matching; formal change point detection is more rigorous.

---

### A6. Training Fingerprint Stability

**What:** Track cosine similarity between consecutive workouts as a time series. Measures how varied or repetitive training is over time.

**How:**
- Compute sim(v_i, v_{i+1}) for all consecutive pairs
- Rolling mean (window=5) = short-term stability
- Overall variety score = 1 - mean(all consecutive similarities)
- Detect regime changes where similarity drops below mean - 2*stddev

**Reveals:**
- "Your training variety has decreased 30% over 4 weeks"
- "Program change detected 2 weeks ago — your quality scores have improved since"
- Correlate variety with outcomes: does this user benefit from more or less variation?

**Data needed:** 5+ for basic, 20+ for regime change detection.

**Feasibility:** High. N-1 dot products.

---

### A7. Workout Entropy

**What:** Shannon entropy of the workout type distribution as a training quality metric.

**How:**
1. Cluster last 30 workouts into k types (from A1)
2. Compute probability distribution p(cluster_i)
3. H = -sum(p_i * log2(p_i)), normalize by log2(k) for 0-1 scale

**Reveals:**
- Entropy near 0 = training concentrated in 1-2 types (fine for peaking, bad for general fitness)
- Entropy near 1 = balanced across all types (good variety, possible lack of focus)
- Decreasing entropy trending into a competition = natural periodization
- Flat high entropy = program-hopping

**Per-dimension variant:** Compute entropy of each dimension's value distribution. Dim 17 with low entropy = consistent schedule. Dim 4 with high entropy = constantly varying exercises.

**Feasibility:** High. Minimal code.

---

### A8. Dimensional Covariance — Training Personality (**)

**What:** The correlations between dimensions reveal structural training habits.

**How:** Compute the 18x18 covariance matrix across all workouts (using pre-normalization features — requires stored magnitude). Extract top principal components via PCA.

**Reveals:**
- High volume-RPE correlation (r > 0.8) = only trains hard on high-volume days (one-dimensional training)
- High weight-PR correlation = chases PRs by maxing out (intensity-driven)
- Low variance in muscle dims (6-11) = always same split, no variation
- Prescriptive: "Your volume and RPE are tightly coupled. Try accumulation blocks: high-volume, low-RPE"

**Data needed:** Pre-normalization features (requires magnitude storage). 20+ workouts.

**Feasibility:** Medium. 18x18 covariance matrix is trivial with Accelerate. Requires the magnitude storage prerequisite.

---

### A9. Personal Volume-Response Curve

**What:** For each muscle group, correlate weekly training volume with subsequent strength progress to discover the user's personal MEV, MAV, and MRV — not population defaults.

**How:**
- Collect (weekly_sets, subsequent_2week_e1RM_change) pairs per muscle group
- Fit quadratic regression: gain = a*sets^2 + b*sets + c
- Vertex of inverted parabola = personal MAV
- Zero-crossings = personal MEV and MRV

**Reveals:**
- "Your chest responds best to 14-18 sets/week — you're currently at 22 (overreaching)"
- Replaces population-default MEV/MRV with data-derived personal values
- Progressive disclosure: show defaults until 12+ weeks, then blend in personal data

**Data needed:** 12+ weeks per muscle group. Only shown when R-squared > 0.3.

**Feasibility:** Medium-high. Closed-form quadratic fit. Challenge is data sufficiency and noise.

---

### A10. Multivariate Fitness-Fatigue Model

**What:** Per-dimension exponential fitness-fatigue model (Banister 1975, extended). Instead of a scalar TRIMP, model fitness and fatigue decay separately for each vector dimension.

**How:** For each dimension d, fit: Performance_d(t) = sum[k1_d * w_d(i) * exp(-(t-ti)/tau1_d) - k2_d * w_d(i) * exp(-(t-ti)/tau2_d)]

**Reveals:** Volume fatigue (dim 0) decays slower than intensity fatigue (dim 1). RPE fatigue (dim 13) accumulates faster than mechanical fatigue — the psychological cost compounds differently. Validates recovery estimates from a completely different data source.

**Data needed:** 50+ workouts. Requires outcome variable (quality score or e1RM trend).

**Feasibility:** Medium-low. Nonlinear optimization (72 parameters). Start with dims 0, 1, 2, 13 only.

**References:** Banister et al. 1975; Busso 2003; Clarke & Skiba 2013; [Three-dimensional impulse-response extension (2025)](https://arxiv.org/html/2505.20859v1)

---

### A11. Cross-Dimensional Granger Causality

**What:** Test whether changes in one dimension predict future changes in another, revealing directional causal relationships in training.

**Examples:**
- Does increasing compound ratio (dim 12) at lag 2-3 cause increases in avg weight (dim 1)?
- Does high RPE (dim 13) at lag 1 cause decreased volume (dim 0)? (self-regulation signal)
- Does PR count (dim 16) cause changes in exercise diversity (dim 4)? (novelty-seeking after success)

**Data needed:** 50+ workouts. Requires stationarity (may need differencing).

**Feasibility:** Medium-low. 306 pairwise tests. Limit to 5-6 actionable pairs for on-device use.

---

## Category B: Coaching & Recommendations

These synthesize analytics signals into actionable guidance.

### B1. Fatigue-Adjusted Weight Suggestion

**What:** Before a workout, suggest target weights for each exercise based on current fatigue state.

**How:** Start from recent e1RM, then apply modifiers:
- Recovery status of primary muscle: fatigued -10%, recovering -5%, ready 0%
- ACWR zone: danger -15%, caution -10%, optimal 0%, underTraining +5%
- Deload flag: target 60-70% of e1RM
- Training phase: accumulation -> higher reps/lower weight; peaking -> lower reps/higher weight
- Days since last session for this exercise: >7d -> -5% (neural detraining)
- Convert adjusted e1RM to weight @ target reps via Brzycki inverse. Round to nearest 2.5 kg.

**Reveals:** "Bench Press: aim for 82.5 kg x 8 (based on 95 kg e1RM, -5% recovering chest, -5% high load zone)"

**Data needed:** Composes existing services (OverloadTrend, RecoveryPattern, TrainingLoad, PhaseDetection). 4+ weeks of history per exercise.

**Feasibility:** High. Arithmetic on precomputed values. Most directly actionable feature in this entire list.

---

### B2. Effort Creep Detection

**What:** When avg RPE trends upward over 3+ sessions while e1RM is flat or declining, surface a proactive warning. Classic pre-overtraining signal that even experienced lifters miss.

**Example:** "Bench press: same weight, same reps, but RPE climbed from 7 to 8.5 over 3 sessions. Your body is working harder for the same output — accumulated fatigue."

**Data needed:** Per-exercise RPE tracking + OverloadTrend. DeloadSignal.rpeCreep already detects this but only surfaces it through deload urgency.

**Feasibility:** High. The signal exists — just needs its own surfacing rather than being buried in the deload score.

---

### B3. Workout Recommendations via Nearest-Neighbor

**What:** Before a session, find the cluster the user hasn't visited recently and suggest exercises that would produce a vector in that region.

**How:** Use archetype clusters (A1), identify the most "overdue" cluster by days since last visit, find historical workouts in that cluster, present as suggested templates.

**Reveals:** "You haven't done a heavy compound lower-body session in 12 days. Here's what your best one looked like."

**Data needed:** Archetype clusters + workout history.

**Feasibility:** High. Builds on A1.

---

### B4. Planned vs Executed Divergence

**What:** If the user has a progression plan, vectorize the planned workout and compare against the executed vector. Track systematic biases over time.

**Reveals:**
- Consistently positive RPE delta: training harder than prescribed (ego lifting)
- Consistently negative volume delta: cutting workouts short
- Drift on muscle dims: substituting exercises that shift muscle emphasis
- Increasing divergence: plan is losing relevance

**Data needed:** Requires progression plan to contain enough detail for vectorization (exercises + planned sets/reps/weight).

**Feasibility:** Medium. Depends on plan data model completeness.

---

### B5. Time-of-Day Optimization

**What:** Correlate dim 17 (time of day) with quality scores, volume, RPE across history.

**Reveals:** "Your evening workouts (7-9 PM) consistently have 12% higher volume and lower RPE than morning sessions."

**Data needed:** Existing vectors + quality scores. 20+ workouts across varied times.

**Feasibility:** High. Basic correlation analysis.

---

## Category C: UX Surfacing & Presentation

These focus on when and how insights reach the user. The biggest gap in the current system is not computation — it's timing and prioritization.

### C1. Post-Workout Coaching Debrief

**What:** Immediately after completing a workout, show a 2-3 bullet contextual summary. Not "great workout" — specific observations.

**Examples:**
- "Bench e1RM up 2.5 kg from 4 weeks ago. Squat flat for 3 weeks — consider a variation."
- "18% more volume than your 30-day avg. ACWR at 1.28 — one more session like this enters caution."
- "Legs hit hard today but no back work this week. Back volume below MEV."

**Why it matters:** This is the moment of highest engagement. The lifter just finished and is curious. A 5-second glance replaces 15 minutes of spreadsheet analysis. This is what a knowledgeable partner would say in the parking lot.

**Data needed:** WorkoutVector (vol deltas), OverloadTrend, TrainingLoad (ACWR), OptimalVolumeRange (MEV/MRV), MuscleBalance. PostWorkoutSummary model already exists but isn't wired to analytics.

**Feasibility:** High. Primarily a prioritization + text generation task over existing signals.

---

### C2. Weekly Digest

**What:** A single prioritized observation comparing this week to prior week and 4-week baseline. Not a stats dump — one "aha" insight.

**Examples:**
- "Chest volume jumped 40% while shoulders dropped to 0. Last week was balanced. Intentional?"
- "Third consecutive week of deadlift e1RM gains (+1.8 kg/week). Best streak since October."
- "5 sessions this week vs usual 3-4. ACWR climbing — lighter week well-timed."

**Why it matters:** Weekly cadence matches how intermediate lifters think about programming. One prioritized insight > ten-card dashboard.

**Data needed:** BlockComparison, OverloadTrend, TrainingLoad, workout frequency.

**Feasibility:** High.

---

### C3. Pre-Workout Context Card

**What:** When starting a session, show a brief card based on current training state.

**Examples:**
- "Chest fully recovered (last 3 days ago). Triceps still recovering from yesterday's overhead work — consider reducing isolation volume."
- "ACWR at 1.35 (caution). Consider moderate session today."
- "Last 2 leg sessions below usual volume. Good day to push closer to MRV."

**Why it matters:** The "pre-game briefing" a coach would give. Transforms the app from passive recorder to active participant.

**Data needed:** RecoveryPattern, TrainingLoad, OptimalVolumeRange, template exercise list.

**Feasibility:** High.

---

### C4. Exercise-Level Micro-Insights (Inline During Logging)

**What:** While logging a set, show a subtle contextual line below the exercise header. Not a modal — a single line when relevant.

**Examples:**
- "Last 4 sessions: 3x8@80kg. Try 82.5kg or 4x8 to keep progressing."
- "You haven't done this in 18 days. Last time: 3x10@70kg."
- "Stalled 3 weeks. Consider adding a close-grip variation."

**Why it matters:** Intelligence at the point of action. No navigation to analytics needed. The insight appears exactly where and when it's relevant.

**Data needed:** Per-exercise history, PlateauAnalysis, last-performed date. Already available in workout logging flow.

**Feasibility:** High.

---

### C5. Muscle Group Neglect Detection (Trend-Based)

**What:** Track rolling 4-8 week trends per muscle group and flag systematic decline relative to the user's own baseline. Unlike single-week snapshots (noisy), 4-week trends are meaningful.

**Examples:**
- "Back training declined 35% over 4 weeks (16 to 10 weekly sets). Chest stayed at 18."
- "Legs trained in only 2 of last 4 weeks. Leg volume well below your MEV."

**Data needed:** MuscleGroupVolume trend, OptimalVolumeRange.

**Feasibility:** High.

---

### C6. Session Fingerprint Comparison

**What:** After a workout, show how it compared to the most similar historical session.

**Examples:**
- "Similar to your Dec 15 workout (87% match). That session you lifted 5% more volume and hit a bench PR."
- "vs most similar session: lower volume (-12%), higher intensity (+8%), same muscle split."

**Why it matters:** Gives historical context without requiring the user to remember or search.

**Data needed:** SimilarWorkout search (already implemented), per-feature comparison.

**Feasibility:** High.

---

### C7. Training Block Retrospective

**What:** Every 4 weeks, generate a structured narrative comparing the completed block to the previous one. Not charts — 3-4 key observations.

**Example:** "Block 2: 14 sessions vs 12 in Block 1. Total volume +8%. Bench and squat progressing (+1.2 and +0.8 kg/week). OHP stalled — consider variation next block. Balance improved 72 to 81."

**Data needed:** BlockComparison, TrainingPhaseDetection, OverloadTrend, MuscleBalance, AggregateQualityScore. All already computed.

**Feasibility:** High. Synthesis + narrative generation over existing data.

---

### C8. Quality-Based Achievements

**What:** Achievements tied to training quality, not just attendance. Reward behaviors that drive results.

**Examples:**
- "Progressive Loader": hit overload on 3+ exercises in one session (5x to unlock)
- "Balanced Builder": all major muscles within optimal volume for 4 consecutive weeks
- "Smart Recovery": took a deload when ACWR exceeded 1.3 and the app recommended it
- "Plateau Breaker": broke through a 3+ week plateau
- "Iron Consistency": 90%+ planned sessions completed for 8 weeks

**Why it matters:** Standard streaks punish rest days and deloads. Quality achievements reward smart decisions — the "Smart Recovery" badge inverts typical gamification by rewarding rest.

**Data needed:** OverloadTrend, OptimalVolumeRange, DeloadRecommendation, PlateauAnalysis, workout frequency.

**Feasibility:** Medium. Achievement tracking infrastructure needed.

---

### C9. Adherence Pattern Analysis

**What:** Analyze workout timing patterns to detect schedule regularity, predict upcoming sessions, and warn about consistency decline.

**How:**
- Inter-workout interval (IWI) statistics: mean, stddev, CV, trend
- Day-of-week frequency histogram
- Streak tracking (consecutive on-schedule workouts)
- Dropout risk: IWI trend positive (growing gaps) + current gap > mean + 1.5*stddev

**Reveals:**
- "Trained consistently every 2.1 days for 6 weeks — longest streak"
- "4.5 days since last workout — you typically train within 2.5 days"
- Widget: "Next expected workout: Tomorrow (Wednesday)"
- "Training frequency decreased 20% over 3 weeks"

**Data needed:** Workout timestamps only. 5+ for basic, 15+ for trends.

**Feasibility:** High. Pure statistics, no vector dependency.

---

## Prioritization

### Tier 1 — High impact, low effort, immediately feasible

| # | Feature | Category | Effort | Data needed |
|---|---------|----------|--------|-------------|
| C1 | Post-Workout Debrief | UX | Low | Existing signals |
| B1 | Weight Suggestion | Coaching | Medium | Existing services |
| B2 | Effort Creep Detection | Coaching | Low | Existing signals |
| C9 | Adherence Analysis | UX | Low | Timestamps only |
| C4 | Exercise Micro-Insights | UX | Medium | Existing per-exercise data |

### Tier 2 — High impact, moderate effort

| # | Feature | Category | Effort | Data needed |
|---|---------|----------|--------|-------------|
| A1 | Archetype Clustering | Analysis | Medium | 10+ vectors |
| A3 | Trajectory Curvature | Analysis | Low-Med | 5+ vectors |
| C2 | Weekly Digest | UX | Medium | Existing signals |
| C3 | Pre-Workout Card | UX | Medium | Recovery + ACWR |
| A6 | Training Fingerprint | Analysis | Low | 5+ vectors |

### Tier 3 — High potential, higher effort or data requirements

| # | Feature | Category | Effort | Data needed |
|---|---------|----------|--------|-------------|
| A2 | Sequence Prediction | Analysis | Medium | 20+ vectors, depends on A1 |
| A9 | Personal Volume Curve | Analysis | High | 12+ weeks/muscle |
| C7 | Block Retrospective | UX | Medium | Existing signals |
| C8 | Quality Achievements | UX | Medium | Achievement infra |
| A5 | Change Point Detection | Analysis | Medium | 20+ vectors |

### Tier 4 — Research-grade, long-term

| # | Feature | Category | Effort | Data needed |
|---|---------|----------|--------|-------------|
| A8 | Dimensional Covariance (**) | Analysis | Medium | Pre-norm features |
| A10 | Fitness-Fatigue Model | Analysis | High | 50+ workouts |
| A11 | Granger Causality | Analysis | High | 50+ workouts |
| B4 | Planned vs Executed | Coaching | Medium | Plan vectorization |

### What NOT to build

- Total volume all-time counters ("You've lifted 1M kg!") — vanity, changes no behavior
- Calendar heatmaps as primary view — shows attendance, not quality
- Social comparison ("Top 10% bench") — irrelevant, adds noise
- Generic streaks — punishes rest days and deloads, counterproductive for intermediate+ lifters

---

## Cross-Cutting Prerequisite: Store L2 Magnitude

Ideas A8, A10, and the "synthetic workout generation" concept require pre-normalization feature values. The fix is minimal: store `magnitude: Double` alongside the normalized vector in `WorkoutVectorEntity`. From `normalized_vector * magnitude`, the raw features can be reconstructed. This is a one-field migration that unlocks significant future capability even if not needed immediately.

---

## Key Architectural Insight

The computation layer is already rich. The gap is a **prioritization and narrative layer** that:
1. Takes the many analytics signals
2. Ranks them by urgency and novelty (has the user seen this before?)
3. Presents exactly 1-3 observations at the right moment (post-workout, pre-workout, weekly)

The difference between a dashboard of cards and a "knowledgeable training partner" is not more data — it's better timing, prioritization, and plain language delivery.

---

## References

- Banister et al., "A systems model of training for athletic performance", 1975
- [Three-Dimensional Impulse-Response Model (2025)](https://arxiv.org/html/2505.20859v1)
- [Fitness-Fatigue Models: ML Contributions (Sports Medicine Open)](https://link.springer.com/article/10.1186/s40798-022-00426-x)
- [Statistical Flaws of the Fitness-Fatigue Model (Scientific Reports 2025)](https://www.nature.com/articles/s41598-025-88153-7)
- [Privacy-Preserving Personalized Fitness Recommender (ACM TKDD)](https://dl.acm.org/doi/10.1145/3572899)
- [Personalizing Health and Fitness — Apple ML Research (MLSP 2024)](https://machinelearning.apple.com/research/personalized-heartrate)
- [Nonlinear Periodization (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC7466683/)
- [Time Series Change Point Detection Survey (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC5464762/)
- [Autoregulated Resistance Training (ScienceDirect 2025)](https://www.sciencedirect.com/science/article/pii/S1728869X25000590)
- [RP Strength Volume Landmarks](https://rpstrength.com/blogs/articles/training-volume-landmarks-muscle-growth)
