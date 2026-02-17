# StrengthTracker Analytics UX Design
## Vector-Based Workout Intelligence

**Version:** 1.0
**Date:** 2026-02-16
**Status:** Design Specification

---

## Table of Contents

1. [User Personas](#user-personas)
2. [Entry Points & Navigation](#entry-points--navigation)
3. [User Journey Maps](#user-journey-maps)
4. [Screen Wireframes](#screen-wireframes)
5. [Micro-interactions & Delight](#micro-interactions--delight)
6. [Progressive Disclosure](#progressive-disclosure)
7. [Information Architecture](#information-architecture)
8. [Accessibility](#accessibility)
9. [Copy & Tone](#copy--tone)

---

## User Personas

### Persona 1: Sarah "The Beginner"

**Demographics:**
- Age: 26, software developer
- Gym experience: 3 months
- Goal: Build strength, learn proper form

**Pain Points:**
- Unsure if her workouts are balanced
- Doesn't know when to increase weight
- Feels lost about what to do next

**Motivation:**
- Wants clear guidance without overthinking
- Values simple, actionable advice
- Prefers visual feedback over numbers

**Analytics Needs:**
- Exercise recommendations (what to add)
- Recovery insights (am I doing too much?)
- Simple trend lines (am I getting stronger?)

---

### Persona 2: Marcus "The Intermediate"

**Demographics:**
- Age: 34, marketing manager
- Gym experience: 2 years
- Goal: Break through plateaus, optimize training

**Pain Points:**
- Feels stuck at same weights for weeks
- Unsure if he's training enough or too much
- Wants to know if muscle groups are balanced

**Motivation:**
- Data-driven but wants quick insights
- Willing to adjust training based on evidence
- Values efficiency (don't waste time on wrong workouts)

**Analytics Needs:**
- Plateau detection (why am I stuck?)
- Volume optimization (too much? too little?)
- Similar workouts (what worked before?)
- Muscle balance analysis

---

### Persona 3: Jasmine "The Advanced"

**Demographics:**
- Age: 29, powerlifting competitor
- Gym experience: 5+ years
- Goal: Maximize strength, peak for competition

**Pain Points:**
- Needs granular data to fine-tune programming
- Wants to compare current cycle to past cycles
- Needs early warning signs of overtraining

**Motivation:**
- Obsessed with optimization
- Wants control over analytics parameters
- Values historical comparisons

**Analytics Needs:**
- Strength trends (1RM progression)
- Recovery analysis (per muscle group)
- Volume tracking (weekly, monthly, per-lift)
- Advanced pattern matching (similar phases)

---

## Entry Points & Navigation

### Tab Structure: Keep Existing 5 Tabs

The existing 5-tab structure is preserved. Analytics is accessed via contextual entry points (push navigation), not a dedicated tab.

**Rationale:**
- Apple HIG recommends max 5 tabs; a 6th forces "More" overflow on smaller iPhones
- Current tabs serve core transactional workflows (start workout, log sets, manage templates)
- Analytics is exploratory, not transactional — it doesn't need a persistent tab
- Contextual entry surfaces insights where they're most relevant (post-workout, exercise detail)

```
┌─────────────────────────────────────┐
│         5-Tab Navigation            │
├─────────────────────────────────────┤
│ Dashboard │ Workout │ Templates │ Exercises │ History
│   (0)     │   (1)   │    (2)    │    (3)    │   (4)
└─────────────────────────────────────┘
```

### Entry Point Strategy

| Entry Point | When | Who | Analytics Feature |
|------------|------|-----|-------------------|
| **Dashboard → Insights Card** | App opens | All users | Overview insights, actionable alerts, tap to push full Analytics screen |
| **Post-Workout Sheet** | Workout completes | All users | Workout quality score, immediate insights, "View Similar" button |
| **History → Workout Detail** | Tap completed workout | Intermediate/Advanced | Similar workouts, context-specific insights |
| **Exercises → Exercise Detail** | Tap exercise | All users | Per-exercise trends, plateau detection, recommendations |

### Navigation Hierarchy

```
Dashboard (Tab 0)
├─ Insights Card (new)
│  ├─ Tap card → Push to Analytics Dashboard screen
│  └─ Swipe → Quick insight carousel (3-5 cards)
│
Workout (Tab 1)
├─ Post-Workout Sheet (after finish)
│  ├─ Workout Quality Score
│  ├─ Highlights (PRs)
│  └─ "View Similar Workouts" → Push to Similar Workouts sheet
│
Exercises (Tab 3)
├─ Exercise Detail
│  ├─ Progress tab (existing)
│  └─ Insights tab (new)
│     ├─ Plateau detection
│     └─ Recommendations
│
History (Tab 4)
├─ Workout Detail
│  ├─ "Similar Workouts" button → Push to Similar Workouts sheet
│  └─ "Insights for this workout" section
│
Analytics Dashboard (pushed screen, NOT a tab)
├─ Accessed from Dashboard Insights Card → "View All"
├─ Overview (summary of all insights)
├─ Strength Trends
├─ Volume Analysis
├─ Muscle Balance
├─ Recovery Timeline
└─ Workout Explorer (similar workouts)
```

---

## User Journey Maps

### Journey 1: Similar Workouts

**Persona:** Marcus (Intermediate)
**Trigger:** Just finished a great push workout, wants to repeat it
**Goal:** Find similar workouts from the past

**Journey:**

```
1. Complete Workout
   ↓
2. Post-Workout Sheet appears
   "Great session! 12,450 kg volume"
   [View Similar Workouts] button
   ↓
3. Similar Workouts Sheet
   ┌────────────────────────────────┐
   │ Workouts Like "Push Day A"    │
   ├────────────────────────────────┤
   │ 🟢 92% Similar - Feb 2         │
   │    3 exercises match           │
   │    Similar volume (12.1k kg)   │
   │    [View Details]              │
   ├────────────────────────────────┤
   │ 🟡 87% Similar - Jan 24        │
   │    2 exercises match           │
   │    Higher volume (14.2k kg)    │
   │    [View Details]              │
   ├────────────────────────────────┤
   │ 🟡 85% Similar - Jan 15        │
   │    3 exercises match           │
   │    Lower volume (10.8k kg)     │
   │    [View Details]              │
   └────────────────────────────────┘
   ↓
4. Tap workout → WorkoutDetailView
   Shows full breakdown, exercises, sets
   ↓
5. [Copy as Template] button
   Creates template from that workout
```

**Key Interactions:**
- Similarity score (visual: 🟢 90%+, 🟡 75-90%, 🔴 <75%)
- Sortable (by similarity, date, volume)
- Filter by date range (last month, 3 months, all time)

**Output:**
- List of 5-10 similar workouts
- Similarity % and reason ("3 exercises match")
- Quick stats comparison (volume, duration)

**Action:**
- View workout details
- Copy as template
- Start workout from history

---

### Journey 2: Plateau Detection

**Persona:** Marcus (Intermediate)
**Trigger:** Opening the app, Dashboard loads insights
**Goal:** Understand why bench press isn't progressing

**Journey:**

```
1. Open App → Dashboard
   ↓
2. Insights Card appears (push notification)
   ┌────────────────────────────────┐
   │ 🔔 Plateau Alert               │
   │ Bench Press hasn't progressed  │
   │ in 4 weeks                     │
   │ [See Recommendations]          │
   └────────────────────────────────┘
   ↓
3. Tap → Plateau Detail Sheet
   ┌────────────────────────────────┐
   │ Bench Press - Plateau          │
   ├────────────────────────────────┤
   │ WHAT'S HAPPENING               │
   │ Your top weight has stayed at  │
   │ 80kg for 4 workouts            │
   │                                │
   │ [Chart: Weight over time]      │
   │  ↗︎↗︎↗︎→→→→                       │
   │                                │
   │ WHY IT MIGHT BE                │
   │ • Volume too high (28 sets/wk) │
   │ • Frequency too high (3x/week) │
   │ • Rest days: 1-2 days between  │
   │                                │
   │ WHAT TO TRY                    │
   │ 1️⃣ Reduce to 2x per week       │
   │ 2️⃣ Drop to 20 sets per week    │
   │ 3️⃣ Add 1 extra rest day        │
   │ 4️⃣ Try pause reps / tempo work │
   │                                │
   │ SIMILAR BREAKTHROUGHS          │
   │ "When you reduced volume in    │
   │ December, you broke through    │
   │ 75kg plateau in 2 weeks"       │
   └────────────────────────────────┘
   ↓
4. [Apply Recommendation] button
   → Adjusts workout template frequency
   → Sets reminder to check progress in 2 weeks
```

**Key Interactions:**
- Severity indicator (🔔 alert, ⚠️ watch, ℹ️ info)
- Collapsible sections (What / Why / Try / Similar)
- Actionable buttons (Apply, Dismiss, Remind Later)

**Output:**
- Clear diagnosis (weight stalled)
- Hypothesis (volume/frequency/recovery)
- Specific recommendations
- Historical context (what worked before)

**Action:**
- Apply recommendation to templates
- Dismiss alert
- Set 2-week check-in reminder

---

### Journey 3: Muscle Balance

**Persona:** Sarah (Beginner)
**Trigger:** Wonders if she's training legs enough
**Goal:** See if muscle groups are balanced

**Journey:**

```
1. Dashboard → Tap Insights Card
   ↓
2. Analytics Dashboard
   ┌────────────────────────────────┐
   │ ⚖️ Muscle Balance               │
   │ [View Breakdown]               │
   └────────────────────────────────┘
   ↓
3. Muscle Balance View
   ┌────────────────────────────────┐
   │ Weekly Volume by Muscle        │
   ├────────────────────────────────┤
   │       LAST 4 WEEKS             │
   │                                │
   │ Chest    ████████░░ 42 sets    │
   │ Back     ███████░░░ 38 sets    │
   │ Legs     ████░░░░░░ 22 sets ⚠️  │
   │ Shoulders████░░░░░░ 24 sets    │
   │ Arms     ██░░░░░░░░ 12 sets    │
   │                                │
   │ BALANCE SCORE: 72/100          │
   │                                │
   │ ⚠️ Legs are undertrained       │
   │ "You're doing 48% less leg     │
   │ volume than upper body"        │
   │                                │
   │ RECOMMENDATIONS                │
   │ • Add 2 leg exercises per week │
   │ • Try: Goblet Squats,          │
   │   Romanian Deadlifts           │
   │                                │
   │ [View Exercise Library]        │
   └────────────────────────────────┘
   ↓
4. Tap [View Exercise Library]
   → Filtered to "Legs" category
   → Sorted by "Recommended for you"
```

**Key Interactions:**
- Time range selector (1 week, 4 weeks, 12 weeks)
- Tap muscle group → see exercise breakdown
- Visual balance indicator (radial chart or bars)

**Output:**
- Volume per muscle group (sets/week)
- Balance score (0-100)
- Imbalance alerts (⚠️ undertrained, ⚡️ overtrained)
- Specific exercise recommendations

**Action:**
- Add recommended exercises to templates
- View exercise library (filtered)
- Dismiss if balance is acceptable

---

### Journey 4: Exercise Recommendations

**Persona:** Sarah (Beginner)
**Trigger:** Creating a new workout template
**Goal:** Get suggestions for what exercises to add

**Journey:**

```
1. Templates Tab → [New Template]
   ↓
2. Template Editor
   "Push Day"
   [Add Exercise] button
   ↓
3. Exercise Picker with AI Recommendations
   ┌────────────────────────────────┐
   │ 💡 Recommended for You         │
   ├────────────────────────────────┤
   │ Bench Press                    │
   │ ✓ Matches your goals           │
   │ ✓ You PR'd last week (65kg)    │
   │                                │
   │ Overhead Press                 │
   │ ✓ Complements Bench Press      │
   │ ✓ Low volume this month        │
   │                                │
   │ Incline Dumbbell Press         │
   │ ✓ Great for upper chest        │
   │ ✓ Similar to past workouts     │
   └────────────────────────────────┘
   [Browse All Exercises]
   ↓
4. Tap exercise → adds to template
   Shows recommended sets/reps:
   "Try 3 sets of 8-10 reps at 15kg"
   (based on past performance)
```

**Key Interactions:**
- Recommendations at top (3-5 exercises)
- Reason tags (✓ complements, ✓ low volume, ✓ PR potential)
- Tap to add, long-press for exercise details

**Output:**
- 3-5 recommended exercises
- Clear rationale for each
- Suggested sets/reps/weight based on history

**Action:**
- Add to template
- View exercise details
- Browse full library

---

### Journey 5: Recovery Insights

**Persona:** Marcus (Intermediate)
**Trigger:** Feels sore, wonders if he should train chest today
**Goal:** Check recovery status for muscle groups

**Journey:**

```
1. Dashboard → Insights Card
   ↓
2. Analytics Dashboard
   ┌────────────────────────────────┐
   │ 🔄 Recovery Status              │
   │ [View Timeline]                │
   └────────────────────────────────┘
   ↓
3. Recovery Timeline
   ┌────────────────────────────────┐
   │ Muscle Group Recovery          │
   ├────────────────────────────────┤
   │ TODAY (Feb 16)                 │
   │                                │
   │ Chest    🟢 Ready (72h rest)   │
   │          Last: Wed Feb 13      │
   │          Volume: 18 sets       │
   │                                │
   │ Back     🟡 Caution (36h rest) │
   │          Last: Thu Feb 14      │
   │          Volume: 24 sets (high)│
   │          Suggest: wait 12h     │
   │                                │
   │ Legs     🟢 Ready (96h rest)   │
   │          Last: Mon Feb 11      │
   │          Volume: 16 sets       │
   │                                │
   │ CALENDAR VIEW                  │
   │ [Timeline showing workouts]    │
   │  Mon  Tue  Wed  Thu  Fri       │
   │  Legs  -  Chest Back  ?        │
   │                                │
   │ TODAY'S RECOMMENDATION         │
   │ ✓ Chest or Legs                │
   │ ⚠️ Avoid Back (short recovery) │
   └────────────────────────────────┘
   ↓
4. Tap muscle group → see details
   "Back - Last trained 36h ago"
   Shows: exercises done, volume, typical recovery
```

**Key Interactions:**
- Status colors (🟢 ready, 🟡 caution, 🔴 avoid)
- Time since last training
- Volume context (high/normal/low)
- Calendar timeline view (7-day scroll)

**Output:**
- Recovery status per muscle group
- Time since last trained
- Volume-adjusted recommendations
- Visual timeline

**Action:**
- Plan today's workout based on recovery
- View past workout that trained that muscle
- Override if user feels ready

---

### Journey 6: Volume Optimization

**Persona:** Jasmine (Advanced)
**Trigger:** Monthly check-in to optimize training
**Goal:** Ensure volume is in optimal range

**Journey:**

```
1. Dashboard → Tap Insights Card → Analytics Dashboard
   ↓
2. Volume Analysis
   ┌────────────────────────────────┐
   │ 📊 Training Volume              │
   ├────────────────────────────────┤
   │ WEEKLY VOLUME                  │
   │ Current: 68 sets               │
   │ 4-week avg: 64 sets            │
   │                                │
   │ [Chart: Volume over 12 weeks]  │
   │  ┌─────────────────────────┐   │
   │  │     ╱╲    ╱╲            │   │
   │  │    ╱  ╲  ╱  ╲╱╲         │   │
   │  │   ╱    ╲╱      ╲        │   │
   │  └─────────────────────────┘   │
   │    Optimal Range: 55-75 sets   │
   │                                │
   │ STATUS: ✓ Optimal              │
   │                                │
   │ BY MUSCLE GROUP                │
   │ Chest:  14 sets  ✓ Optimal     │
   │ Back:   16 sets  ✓ Optimal     │
   │ Legs:   18 sets  ✓ Optimal     │
   │ Shoulders: 12 sets ⚠️ Low       │
   │ Arms:   8 sets   ✓ Optimal     │
   │                                │
   │ INSIGHTS                       │
   │ "Your volume is well-balanced. │
   │ Consider adding 2-4 sets for   │
   │ shoulders to match other       │
   │ muscle groups."                │
   │                                │
   │ [Adjust Template]              │
   └────────────────────────────────┘
   ↓
3. Tap BY MUSCLE GROUP row
   → Detailed breakdown per muscle
   → Shows: sets per exercise, weekly trend
   ↓
4. [Adjust Template] button
   → Opens template editor
   → Highlights shoulders section
   → Suggests adding 1 exercise or 2 sets to existing
```

**Key Interactions:**
- Time range (4 weeks, 12 weeks, all time)
- Chart zoom/scroll
- Tap muscle group for details
- Optimal range shaded on chart

**Output:**
- Total weekly volume
- Volume per muscle group
- Comparison to optimal range (research-backed)
- Trend over time (increasing/stable/decreasing)

**Action:**
- Adjust templates to hit optimal volume
- Track changes over next 2-4 weeks
- Export data (CSV for advanced users)

---

### Journey 7: Strength Trends

**Persona:** Jasmine (Advanced)
**Trigger:** Monthly progress check
**Goal:** Visualize strength progression across key lifts

**Journey:**

```
1. Analytics Dashboard → Strength Trends
   ↓
2. Strength Progression View
   ┌────────────────────────────────┐
   │ 💪 Strength Trends              │
   ├────────────────────────────────┤
   │ ESTIMATED 1RM PROGRESSION      │
   │                                │
   │ [Multi-line chart]             │
   │  ┌─────────────────────────┐   │
   │  │ Squat     ████████      │   │
   │  │ Bench     ██████        │   │
   │  │ Deadlift  ██████████    │   │
   │  └─────────────────────────┘   │
   │   Jan    Feb    Mar    Apr     │
   │                                │
   │ CURRENT 1RM ESTIMATES          │
   │ Squat:     120kg (+5kg) ↗︎      │
   │ Bench:      85kg (+2kg) ↗︎      │
   │ Deadlift:  145kg (+8kg) ↗︎      │
   │                                │
   │ VOLUME LOAD TRENDS             │
   │ Squat:     8,400kg/week ↗︎      │
   │ Bench:     5,100kg/week →      │
   │ Deadlift:  7,200kg/week ↗︎      │
   │                                │
   │ INSIGHTS                       │
   │ "All lifts progressing well!   │
   │ Bench Press volume is stable - │
   │ consider increasing to push    │
   │ past current plateau."         │
   │                                │
   │ [Compare to Past Cycles]       │
   └────────────────────────────────┘
   ↓
3. Tap [Compare to Past Cycles]
   ┌────────────────────────────────┐
   │ Current vs. Best Cycle         │
   │                                │
   │         Current   Best (Dec)   │
   │ Squat   +12kg    +15kg         │
   │ Bench   +6kg     +8kg          │
   │ DL      +18kg    +12kg  🏆     │
   │                                │
   │ "Your deadlift progress this   │
   │ cycle is your best yet!"       │
   └────────────────────────────────┘
```

**Key Interactions:**
- Select lifts to chart (up to 5)
- Time range (3 months, 6 months, 1 year, all time)
- Toggle between 1RM, volume load, tonnage
- Export chart as image

**Output:**
- Multi-line chart (up to 5 lifts)
- Current 1RM estimates
- Progress deltas (+5kg since last month)
- Volume load trends
- Historical comparisons

**Action:**
- Analyze what's working
- Identify lagging lifts
- Share progress image on social
- Adjust training based on trends

---

## Screen Wireframes

### Wireframe 1: Dashboard with Insights Card

```
┌─────────────────────────────────────┐
│ ☰  Dashboard              ⚙️        │
├─────────────────────────────────────┤
│                                     │
│  WEEKLY FREQUENCY                   │
│  ┌───────────────────────────────┐  │
│  │  ▅  ▆  █  ▅  ▆  ░  ░          │  │
│  │  M  T  W  T  F  S  S          │  │
│  │  4 workouts  +25% vs last week│  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ START EMPTY WORKOUT         │   │
│  └─────────────────────────────┘   │
│  (Primary button - yellow)          │
│                                     │
│  💡 INSIGHTS                        │
│  ┌─────────────────────────────┐   │
│  │ 🔔 Plateau Alert            │   │
│  │ Bench Press stuck 4 weeks   │   │
│  │ [See Recommendations] →     │   │
│  ├─────────────────────────────┤   │
│  │ ⚖️ Muscle Balance            │   │
│  │ Legs undertrained (48% less)│   │
│  │ [View Breakdown] →          │   │
│  ├─────────────────────────────┤   │
│  │ 🔄 Recovery Ready            │   │
│  │ Chest & Legs ready to train │   │
│  │ [View Timeline] →           │   │
│  └─────────────────────────────┘   │
│  ← Swipe for more insights →       │
│                                     │
│  STATS THIS WEEK                    │
│  ┌─────────────────────────────┐   │
│  │  Volume  Duration  PRs       │   │
│  │  32.4k   4h 12m    2         │   │
│  └─────────────────────────────┘   │
│  (Carousel - swipe left/right)      │
│                                     │
│  RECENT WORKOUTS                    │
│  ┌─────────────────────────────┐   │
│  │ Push Day A                  │   │
│  │ Feb 14  •  12.4k kg  •  65m │   │
│  │ [4 exercises]               │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ Pull Day B                  │   │
│  │ Feb 12  •  10.2k kg  •  58m │   │
│  └─────────────────────────────┘   │
│                                     │
│  [View All History] →               │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Insights card appears after Weekly Frequency
- Swipeable carousel (3-5 insights)
- Priority: Plateau Alerts > Muscle Balance > Recovery
- Each insight: icon, title, 1-line summary, action button
- Dark theme: Surface #1E1E1A, Primary #F2CC0D

---

### Wireframe 2: Post-Workout Insights Sheet

```
Appears after tapping "Finish Workout"

┌─────────────────────────────────────┐
│          Workout Complete!          │
│                                     │
│           ✓ Great Job!              │
│                                     │
│      Total Volume: 12,450 kg        │
│      Duration: 1h 5m                │
│      Exercises: 5                   │
│                                     │
│  ──────────────────────────────     │
│                                     │
│  📊 WORKOUT QUALITY                 │
│  ┌─────────────────────────────┐   │
│  │  SCORE: 85/100  ⭐⭐⭐⭐       │   │
│  │                             │   │
│  │  ✓ Volume: Optimal          │   │
│  │  ✓ Intensity: Good          │   │
│  │  ⚠️ Rest times: A bit short │   │
│  └─────────────────────────────┘   │
│                                     │
│  🎯 HIGHLIGHTS                      │
│  ┌─────────────────────────────┐   │
│  │  🏆 New PR!                 │   │
│  │  Bench Press: 85kg x 5      │   │
│  │  +2.5kg from last week      │   │
│  └─────────────────────────────┘   │
│                                     │
│  🔍 SIMILAR WORKOUTS                │
│  ┌─────────────────────────────┐   │
│  │  3 similar workouts found   │   │
│  │  [View Similar] →           │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Add Notes]  [View Full Details]  │
│                                     │
│           [Done]                    │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Modal sheet from bottom
- Celebration animation (confetti for PRs)
- Quality score (0-100) based on: volume, intensity, rest, balance
- Similar Workouts section (optional, based on vector match)
- Haptic feedback on appear

---

### Wireframe 3: Similar Workouts Sheet

```
Accessed from post-workout or History > Workout Detail

┌─────────────────────────────────────┐
│ ← Workouts Like "Push Day A"        │
├─────────────────────────────────────┤
│  Sorted by: Similarity ▾            │
│  Date range: All time ▾             │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 🟢 92% Similar              │   │
│  │ Push Day A - Feb 2          │   │
│  │                             │   │
│  │ • 3 exercises match         │   │
│  │ • Volume: 12.1k kg (97%)    │   │
│  │ • Duration: 62m             │   │
│  │                             │   │
│  │ Exercises:                  │   │
│  │ Bench Press, OHP, Dips,     │   │
│  │ Lateral Raise               │   │
│  │                             │   │
│  │ [View Details]  [Copy]      │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 🟡 87% Similar              │   │
│  │ Upper Body - Jan 24         │   │
│  │                             │   │
│  │ • 2 exercises match         │   │
│  │ • Volume: 14.2k kg (114%)   │   │
│  │ • Duration: 68m             │   │
│  │                             │   │
│  │ [View Details]  [Copy]      │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 🟡 85% Similar              │   │
│  │ Push Workout - Jan 15       │   │
│  │                             │   │
│  │ • 3 exercises match         │   │
│  │ • Volume: 10.8k kg (87%)    │   │
│  │ • Duration: 55m             │   │
│  │                             │   │
│  │ [View Details]  [Copy]      │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Load More]                        │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Similarity indicator: 🟢 90%+, 🟡 75-90%, 🔴 <75%
- Volume % vs current workout
- Sortable: Similarity, Date, Volume
- Filter: Date range, muscle groups
- Quick actions: View, Copy as Template

---

### Wireframe 4: Plateau Alert Detail

```
Accessed from Dashboard Insights Card

┌─────────────────────────────────────┐
│ ← Plateau Alert                     │
├─────────────────────────────────────┤
│                                     │
│  ⚠️ Bench Press                     │
│                                     │
│  WHAT'S HAPPENING                   │
│  ┌─────────────────────────────┐   │
│  │ Your top weight stayed at   │   │
│  │ 80kg for 4 workouts         │   │
│  │                             │   │
│  │  [Chart: Weight over time]  │   │
│  │   85 ┤                      │   │
│  │   80 ┤  ↗︎↗︎↗︎→→→→             │   │
│  │   75 ┤ ╱                    │   │
│  │   70 ┼─────────────────     │   │
│  │      Jan   Feb   Mar        │   │
│  └─────────────────────────────┘   │
│                                     │
│  WHY IT MIGHT BE ▾                  │
│  ┌─────────────────────────────┐   │
│  │ • Volume too high (28 sets) │   │
│  │ • Frequency high (3x/week)  │   │
│  │ • Short recovery (1-2 days) │   │
│  └─────────────────────────────┘   │
│                                     │
│  WHAT TO TRY ▾                      │
│  ┌─────────────────────────────┐   │
│  │ 1️⃣ Reduce to 2x per week     │   │
│  │ 2️⃣ Drop to 20 sets per week  │   │
│  │ 3️⃣ Add 1 extra rest day      │   │
│  │ 4️⃣ Try pause reps/tempo work │   │
│  └─────────────────────────────┘   │
│                                     │
│  SIMILAR BREAKTHROUGHS ▾            │
│  ┌─────────────────────────────┐   │
│  │ Dec 2025: You reduced volume│   │
│  │ from 24→18 sets and broke   │   │
│  │ through 75kg plateau in 2wks│   │
│  └─────────────────────────────┘   │
│                                     │
│  [Apply Recommendation]             │
│  [Dismiss]  [Remind in 2 Weeks]    │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Collapsible sections (▾ / ▸)
- Chart shows 12-week trend
- "Apply Recommendation" → adjusts template
- "Remind in 2 Weeks" → sets notification
- Warm, encouraging tone (not judgmental)

---

### Wireframe 5: Muscle Balance Radar

```
Accessed from Dashboard Insights Card or Analytics Dashboard

┌─────────────────────────────────────┐
│ ← Muscle Balance                    │
├─────────────────────────────────────┤
│  Time period: Last 4 weeks ▾        │
│                                     │
│  BALANCE SCORE: 72/100              │
│  ┌─────────────────────────────┐   │
│  │     ████████░░              │   │
│  └─────────────────────────────┘   │
│                                     │
│  VOLUME BY MUSCLE GROUP             │
│  ┌─────────────────────────────┐   │
│  │ Chest      ████████░░ 42    │   │
│  │ Back       ███████░░░ 38    │   │
│  │ Legs       ████░░░░░░ 22 ⚠️ │   │
│  │ Shoulders  ████░░░░░░ 24    │   │
│  │ Arms       ██░░░░░░░░ 12    │   │
│  │ Core       ██░░░░░░░░ 10    │   │
│  └─────────────────────────────┘   │
│  (Bars show sets per week)          │
│                                     │
│  ⚠️ IMBALANCES DETECTED             │
│  ┌─────────────────────────────┐   │
│  │ Legs are undertrained       │   │
│  │ You're doing 48% less leg   │   │
│  │ volume than upper body      │   │
│  │                             │   │
│  │ RECOMMENDATIONS             │   │
│  │ • Add 8-12 leg sets/week    │   │
│  │ • Try: Goblet Squats,       │   │
│  │   Romanian Deadlifts        │   │
│  │                             │   │
│  │ [View Exercise Library] →   │   │
│  └─────────────────────────────┘   │
│                                     │
│  WEEKLY TREND ▾                     │
│  ┌─────────────────────────────┐   │
│  │  [Chart: Volume over 12wks] │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Time range: 1 week, 4 weeks, 12 weeks
- Tap muscle group → detailed breakdown
- Balance score algorithm:
  - 100 = perfectly balanced (within 10% of each other)
  - 50 = moderate imbalance (20-40% difference)
  - 0 = severe imbalance (>50% difference)
- Actionable recommendations (specific exercises)

---

### Wireframe 6: Recovery Timeline

```
Accessed from Dashboard Insights Card or Analytics Dashboard

┌─────────────────────────────────────┐
│ ← Recovery Status                   │
├─────────────────────────────────────┤
│  TODAY: Friday, Feb 16              │
│                                     │
│  MUSCLE GROUPS                      │
│  ┌─────────────────────────────┐   │
│  │ Chest   🟢 Ready            │   │
│  │ 72h since last workout      │   │
│  │ Last: Wed Feb 13 (18 sets)  │   │
│  │ [View Workout] →            │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Back    🟡 Caution           │   │
│  │ 36h since last workout      │   │
│  │ Last: Thu Feb 14 (24 sets)  │   │
│  │ High volume - wait 12h more │   │
│  │ [View Workout] →            │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Legs    🟢 Ready             │   │
│  │ 96h since last workout      │   │
│  │ Last: Mon Feb 11 (16 sets)  │   │
│  │ [View Workout] →            │   │
│  └─────────────────────────────┘   │
│                                     │
│  CALENDAR TIMELINE                  │
│  ┌─────────────────────────────┐   │
│  │ Mon  Tue  Wed  Thu  Fri     │   │
│  │ Legs  -  Chest Back  ?      │   │
│  │  11  12   13   14   15      │   │
│  └─────────────────────────────┘   │
│                                     │
│  TODAY'S RECOMMENDATION             │
│  ┌─────────────────────────────┐   │
│  │ ✓ Train: Chest or Legs      │   │
│  │ ⚠️ Avoid: Back (short rest) │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Status colors:
  - 🟢 Ready (48h+ rest, normal volume)
  - 🟡 Caution (24-48h, or high volume)
  - 🔴 Avoid (<24h, or very high volume)
- Recovery time formula:
  - Base: 48h between sessions
  - +12h per 20 sets (high volume)
  - +24h for compound lifts (squat, deadlift)
- Calendar shows last 7 days, scrollable

---

### Wireframe 7: Volume Trends Chart

```
Accessed from Analytics Dashboard

┌─────────────────────────────────────┐
│ ← Training Volume                   │
├─────────────────────────────────────┤
│  Time range: 12 weeks ▾             │
│  Group by: Week ▾                   │
│                                     │
│  WEEKLY VOLUME                      │
│  Current: 68 sets                   │
│  4-week avg: 64 sets                │
│  12-week avg: 61 sets               │
│                                     │
│  TREND CHART                        │
│  ┌─────────────────────────────┐   │
│  │ 75 ┤        Optimal Range    │   │
│  │ 70 ┤ ░░░░░░░░░░░░░░░░░░░░    │   │
│  │ 65 ┤ ░░░╱╲░░░╱╲░░░░░░░░░    │   │
│  │ 60 ┤ ░╱░░░╲░╱░░╲╱╲░░░░░░    │   │
│  │ 55 ┤ ╱░░░░░╲░░░░░░░░░░░░░    │   │
│  │ 50 ┼─────────────────────    │   │
│  │    Dec  Jan  Feb  Mar        │   │
│  └─────────────────────────────┘   │
│  Shaded area: 55-75 sets (optimal)  │
│                                     │
│  STATUS: ✓ Optimal                  │
│                                     │
│  BY MUSCLE GROUP ▾                  │
│  ┌─────────────────────────────┐   │
│  │ Chest       14 sets ✓       │   │
│  │ Back        16 sets ✓       │   │
│  │ Legs        18 sets ✓       │   │
│  │ Shoulders   12 sets ⚠️ Low  │   │
│  │ Arms         8 sets ✓       │   │
│  └─────────────────────────────┘   │
│  Tap to see weekly breakdown        │
│                                     │
│  INSIGHTS ▾                         │
│  ┌─────────────────────────────┐   │
│  │ "Volume well-balanced.      │   │
│  │  Consider +2-4 sets for     │   │
│  │  shoulders to match other   │   │
│  │  muscle groups."            │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Adjust Templates]                 │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Time range: 4 weeks, 12 weeks, 6 months, 1 year
- Group by: Week, Month
- Optimal range based on research (varies by experience level)
- Tap muscle group → see per-exercise breakdown
- Export chart (image or CSV)

---

### Wireframe 8: Strength Progress Multi-Line

```
Accessed from Analytics Dashboard

┌─────────────────────────────────────┐
│ ← Strength Trends                   │
├─────────────────────────────────────┤
│  Select exercises: (5 max)          │
│  ☑️ Squat  ☑️ Bench  ☑️ Deadlift     │
│  ☐ OHP  ☐ Barbell Row               │
│                                     │
│  Metric: Est. 1RM ▾                 │
│  Time: 6 months ▾                   │
│                                     │
│  ESTIMATED 1RM PROGRESSION          │
│  ┌─────────────────────────────┐   │
│  │150┤                         │   │
│  │140┤     ────────  Deadlift  │   │
│  │130┤    ╱                    │   │
│  │120┤────────────  Squat      │   │
│  │110┤                         │   │
│  │100┤                         │   │
│  │ 90┤                         │   │
│  │ 80┤─────────  Bench         │   │
│  │ 70┼─────────────────────    │   │
│  │   Sep  Nov  Jan  Mar        │   │
│  └─────────────────────────────┘   │
│                                     │
│  CURRENT 1RM ESTIMATES              │
│  ┌─────────────────────────────┐   │
│  │ Squat      120kg  +5kg ↗︎    │   │
│  │ Bench       85kg  +2kg ↗︎    │   │
│  │ Deadlift   145kg  +8kg ↗︎    │   │
│  └─────────────────────────────┘   │
│                                     │
│  VOLUME LOAD TRENDS                 │
│  ┌─────────────────────────────┐   │
│  │ Squat      8,400kg/wk ↗︎     │   │
│  │ Bench      5,100kg/wk →     │   │
│  │ Deadlift   7,200kg/wk ↗︎     │   │
│  └─────────────────────────────┘   │
│                                     │
│  INSIGHTS ▾                         │
│  ┌─────────────────────────────┐   │
│  │ "All lifts progressing!     │   │
│  │  Bench volume stable - try  │   │
│  │  increasing to push past    │   │
│  │  current plateau."          │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Compare to Past Cycles]           │
│  [Share Progress]                   │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Select up to 5 exercises to compare
- Toggle metrics: 1RM, Volume Load, Max Weight, Max Reps
- Time range: 3 months, 6 months, 1 year, all time
- Color-coded lines (accessible contrast)
- Share progress (export chart as image)

---

### Wireframe 9: Analytics Dashboard (Overview)

```
Pushed screen from Dashboard Insights Card → "View All"

┌─────────────────────────────────────┐
│ ← Analytics                         │
├─────────────────────────────────────┤
│                                     │
│  QUICK INSIGHTS                     │
│  ┌─────────────────────────────┐   │
│  │ 🔔 1 Alert                  │   │
│  │ Bench Press plateau 4 weeks │   │
│  │ [View] →                    │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌───────────────┬─────────────┐   │
│  │ 💪 Strength   │ 📊 Volume   │   │
│  │ +8kg this     │ 64 sets/wk  │   │
│  │ month ↗︎       │ Optimal ✓   │   │
│  │ [View] →      │ [View] →    │   │
│  └───────────────┴─────────────┘   │
│                                     │
│  ┌───────────────┬─────────────┐   │
│  │ ⚖️ Balance    │ 🔄 Recovery │   │
│  │ 72/100        │ 2 groups    │   │
│  │ Legs low ⚠️   │ ready ✓     │   │
│  │ [View] →      │ [View] →    │   │
│  └───────────────┴─────────────┘   │
│                                     │
│  DETAILED ANALYSIS                  │
│  ┌─────────────────────────────┐   │
│  │ 💪 Strength Trends          │   │
│  │ [View detailed breakdown] → │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 📊 Volume Analysis          │   │
│  │ [View trends & insights] →  │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ ⚖️ Muscle Balance            │   │
│  │ [View breakdown by group] → │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 🔄 Recovery Timeline         │   │
│  │ [View muscle group status]→ │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 🔍 Workout Explorer          │   │
│  │ [Find similar workouts] →   │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Entry point from Dashboard "Insights" card
- Quick insights at top (alerts, summary cards)
- Detailed analysis sections below
- Each card: icon, title, 1-line summary, action
- Grid layout for 2x2 quick insights

---

### Wireframe 10: Exercise Recommendations (In Template Editor)

```
Inside Templates → New Template → Add Exercise

┌─────────────────────────────────────┐
│ ← Add Exercises to "Push Day"       │
├─────────────────────────────────────┤
│  Search exercises...                │
│                                     │
│  💡 RECOMMENDED FOR YOU             │
│  ┌─────────────────────────────┐   │
│  │ Bench Press                 │   │
│  │ ✓ Matches your goals        │   │
│  │ ✓ You PR'd last week (65kg) │   │
│  │ 🏅 85kg Est. 1RM            │   │
│  │                             │   │
│  │ Suggested: 3×8-10 @ 50kg    │   │
│  │ [Add to Template]           │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Overhead Press              │   │
│  │ ✓ Complements Bench Press   │   │
│  │ ✓ Low volume this month     │   │
│  │                             │   │
│  │ Suggested: 3×8-10 @ 30kg    │   │
│  │ [Add to Template]           │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Incline Dumbbell Press      │   │
│  │ ✓ Great for upper chest     │   │
│  │ ✓ Similar to past workouts  │   │
│  │                             │   │
│  │ Suggested: 3×10-12 @ 20kg   │   │
│  │ [Add to Template]           │   │
│  └─────────────────────────────┘   │
│                                     │
│  WHY THESE?                         │
│  ┌─────────────────────────────┐   │
│  │ Based on:                   │   │
│  │ • Your recent performance   │   │
│  │ • Muscle group balance      │   │
│  │ • Similar successful workouts│   │
│  └─────────────────────────────┘   │
│                                     │
│  [Browse All Exercises] →           │
│                                     │
└─────────────────────────────────────┘
```

**Design Notes:**
- Recommendations at top (3-5 exercises)
- Reason tags explain WHY (✓ icons)
- Suggested sets/reps/weight based on history
- One-tap add to template
- "Browse All" for full library access

---

## Micro-interactions & Delight

### 1. Insight Reveal Animation

**Trigger:** Dashboard loads, insights appear
**Animation:**
- Insights card slides up from bottom
- Each insight fades in sequentially (staggered by 100ms)
- Subtle bounce on final position
- Icon pulsates once on reveal

**Duration:** 800ms total

---

### 2. Plateau Alert Haptics

**Trigger:** User taps Plateau Alert card
**Haptic Pattern:**
- Medium impact on tap
- Subtle notification haptic when chart animates in
- Light impact when recommendation buttons appear

**Purpose:** Reinforce importance without being jarring

---

### 3. Workout Quality Score Animation

**Trigger:** Post-workout sheet appears
**Animation:**
- Score counts up from 0 to final (e.g., 0→85)
- Stars fill in sequentially as score increases
- Confetti burst if score >90
- Gentle pulse on final score

**Duration:** 1.2s for count-up, 0.5s for stars

---

### 4. PR Celebration

**Trigger:** New personal record detected
**Animation:**
- 🏆 icon bounces 3 times
- Confetti explosion (yellow/gold particles)
- Success haptic (3 quick pulses)
- "New PR!" badge shimmers

**Duration:** 2s (skippable)

---

### 5. Similar Workout Match Indicator

**Trigger:** User drags down to refresh similar workouts
**Animation:**
- Similarity % counter animates up
- 🟢 indicator fades in with scale animation
- Row slides in from right (staggered)

**Duration:** 500ms per row

---

### 6. Muscle Balance Radar Fill

**Trigger:** User opens Muscle Balance view
**Animation:**
- Bars animate from 0 to final value (ease-out)
- Warning ⚠️ icon pops in if imbalance detected
- Balance score counts up

**Duration:** 800ms

---

### 7. Recovery Status Color Transition

**Trigger:** User views Recovery Timeline
**Animation:**
- Status circles morph from ⚪️ → 🟢/🟡/🔴
- Time since last workout counts up
- Calendar timeline scrolls into view (spring animation)

**Duration:** 600ms

---

### 8. Recommendation Applied Confirmation

**Trigger:** User taps "Apply Recommendation"
**Animation:**
- Button transforms to checkmark ✓
- Green flash overlay
- Success haptic (single medium impact)
- Sheet dismisses after 500ms

**Duration:** 1s total

---

### 9. Chart Data Point Highlight

**Trigger:** User taps data point on strength/volume chart
**Interaction:**
- Data point enlarges (scale 1.5x)
- Tooltip appears above with value + date
- Other lines dim to 30% opacity
- Light haptic on tap

**Duration:** Instant, dismisses on tap-out

---

### 10. Insight Carousel Swipe

**Trigger:** User swipes left/right on Dashboard Insights
**Animation:**
- Cards slide with momentum (spring physics)
- Peek of next card visible (30% width)
- Page indicator dots update
- Light haptic on snap to card

**Duration:** 300ms with spring damping

---

### 11. Empty State Illustrations

**Trigger:** User has <5 workouts (not enough data)
**Animation:**
- Gentle floating animation on illustration
- "Keep going!" text pulsates slowly
- Progress bar shows "X more workouts to unlock insights"

**Purpose:** Encourage continued use, set expectations

---

### 12. Achievement Milestones

**Trigger:** User unlocks analytics feature (e.g., 5 workouts → Similar Workouts)
**Animation:**
- Badge slides in from top
- Shimmer effect across badge
- Success haptic (3 pulses)
- "New Insight Unlocked!" banner

**Duration:** 2s (dismissible)

---

## Progressive Disclosure

### Phase 1: Onboarding (1-5 Workouts)

**What the user sees:**
- Dashboard shows basic stats (volume, duration)
- No Insights card yet (not enough data)
- Post-workout sheet: simple summary, no quality score
- Exercises tab: shows PR tracking only

**Empty states:**
```
┌─────────────────────────────────────┐
│ 💪 Keep Going!                      │
│                                     │
│ [Illustration: person lifting]      │
│                                     │
│ Complete 3 more workouts to unlock: │
│ • Workout quality score             │
│ • Strength trends                   │
│ • Exercise recommendations          │
│                                     │
│ Progress: ▓▓▓░░ (2/5)               │
└─────────────────────────────────────┘
```

**Goal:** Encourage consistency without overwhelming

---

### Phase 2: Basic Insights (5-20 Workouts)

**What the user sees:**
- Dashboard: Insights card appears (1-2 insights)
  - Exercise recommendations
  - Basic strength trends
- Post-workout sheet: adds quality score
- Similar Workouts: basic matching (same exercises)
- Muscle Balance: simple bar chart (no radar)

**Available insights:**
- ✓ Exercise Recommendations
- ✓ Strength Trends (basic)
- ✓ Similar Workouts (basic)
- ✗ Plateau Detection (needs 8+ weeks)
- ✗ Volume Optimization (needs 12+ weeks)
- ✗ Recovery Timeline (needs 4+ weeks)

**Example Dashboard:**
```
┌─────────────────────────────────────┐
│ 💡 INSIGHTS                         │
│ ┌─────────────────────────────┐   │
│ │ 💪 Strength Up!             │   │
│ │ Squat +5kg this week        │   │
│ │ [View Progress] →           │   │
│ └─────────────────────────────┘   │
│ (1 insight, more unlock at 20+)    │
└─────────────────────────────────────┘
```

---

### Phase 3: Full Analytics (20-50 Workouts)

**What the user sees:**
- Dashboard: Insights card with 3-4 rotating insights
- All basic features + pattern detection
- Similar Workouts: advanced vector matching
- Muscle Balance: full radar chart, trend analysis
- Recovery Timeline unlocked

**Available insights:**
- ✓ All Phase 2 features
- ✓ Plateau Detection (needs 8+ weeks of data)
- ✓ Recovery Timeline
- ✓ Muscle Balance (with trends)
- ✗ Volume Optimization (needs 12+ weeks)
- ✗ Advanced pattern matching

**Example Dashboard:**
```
┌─────────────────────────────────────┐
│ 💡 INSIGHTS                         │
│ ┌─────────────────────────────┐   │
│ │ 🔔 Plateau Alert            │   │
│ │ Bench stuck 4 weeks         │   │
│ └─────────────────────────────┘   │
│ ┌─────────────────────────────┐   │
│ │ ⚖️ Muscle Balance            │   │
│ │ Legs undertrained (48%)     │   │
│ └─────────────────────────────┘   │
│ ┌─────────────────────────────┐   │
│ │ 🔄 Recovery Ready            │   │
│ │ Chest & Legs ready          │   │
│ └─────────────────────────────┘   │
│ ← Swipe for more (3/5) →          │
└─────────────────────────────────────┘
```

---

### Phase 4: Advanced Analytics (50+ Workouts)

**What the user sees:**
- All features unlocked
- Historical comparisons (cycles, phases)
- Advanced pattern matching
- Volume optimization (research-backed ranges)
- Predictive recommendations

**Available insights:**
- ✓ All previous features
- ✓ Volume Optimization
- ✓ Cycle Comparisons
- ✓ Advanced pattern detection
- ✓ Predictive analytics (what to expect next month)

**Example Analytics Dashboard:**
```
┌─────────────────────────────────────┐
│ 💡 ADVANCED INSIGHTS                │
│ ┌─────────────────────────────┐   │
│ │ 🔮 Prediction                │   │
│ │ At current pace, expect     │   │
│ │ 90kg bench in 4 weeks       │   │
│ └─────────────────────────────┘   │
│ ┌─────────────────────────────┐   │
│ │ 🏆 Best Cycle                │   │
│ │ Current cycle outperforms   │   │
│ │ Dec 2025 by +8kg            │   │
│ └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

---

### Feature Unlock Timeline

| Workouts | Weeks | Features Unlocked |
|----------|-------|-------------------|
| 1-4 | 1-2 | Basic stats, PR tracking |
| 5-9 | 2-4 | Quality score, basic trends, recommendations |
| 10-19 | 4-8 | Similar workouts, muscle balance, recovery timeline |
| 20-49 | 8-12 | Plateau detection, volume analysis, full insights |
| 50+ | 12+ | Advanced patterns, cycle comparisons, predictions |

**Why this approach:**
- Prevents "empty screen" problem (no data)
- Encourages consistency (unlock new features)
- Avoids overwhelming beginners
- Provides value at every stage

---

## Information Architecture

### Insight Priority System

**How insights are ranked on Dashboard:**

| Priority | Insight Type | Conditions | Display |
|----------|-------------|-----------|---------|
| 1 (Critical) | Plateau Alert | 4+ weeks no progress | 🔔 Red badge |
| 2 (High) | Muscle Balance | >40% imbalance | ⚠️ Yellow badge |
| 3 (High) | Recovery Alert | <24h rest, high volume | ⚠️ Yellow badge |
| 4 (Medium) | Volume Warning | >20% above optimal | ℹ️ Blue badge |
| 5 (Medium) | Strength Milestone | New PR this week | 🏆 Gold badge |
| 6 (Low) | Recommendation | Exercise suggestions | 💡 White badge |
| 7 (Low) | Encouragement | Consistency streak | ✨ White badge |

**Carousel Logic:**
- Show top 3-5 insights (max 5)
- Critical alerts always shown first
- User can swipe left/right to see all
- Dismissed insights hidden for 7 days (or until condition changes)

---

### Push vs Pull Insights

**Push Insights (Proactive Alerts):**
- Plateau Alert (after 4 weeks)
- Muscle Balance warning (>40% imbalance)
- Recovery warning (<24h rest)
- Volume warning (too high/low)

**When to push:**
- Dashboard loads (Insights card)
- Post-workout sheet (if relevant to that workout)
- Optional: Push notification (user setting)

**Pull Insights (User Seeks):**
- Similar Workouts (user taps History → Workout)
- Exercise Recommendations (user creates template)
- Strength Trends (user opens Analytics)
- Volume Analysis (user opens Analytics)

**When to show:**
- On-demand when user navigates to section
- Never interrupt active workout

---

### Navigation Hierarchy

```
App Root (5-tab TabView — no analytics tab)
│
├─ Dashboard (Tab 0)
│  ├─ Insights Card (new — swipeable carousel, 3-5 cards)
│  │  ├─ Tap insight → Push to Detail sheet
│  │  └─ Tap "View All" → Push to Analytics Dashboard screen
│  ├─ Weekly Frequency Chart (passive)
│  ├─ Stats Carousel (passive)
│  └─ Recent Workouts (tap → History detail)
│
├─ Workout (Tab 1)
│  └─ Post-workout sheet (after finish)
│     ├─ Quality Score
│     ├─ Highlights (PRs)
│     └─ "View Similar" button → Push to Similar Workouts sheet
│
├─ Templates (Tab 2)
│  └─ Template Editor
│     └─ Add Exercise → Recommendations section at top of picker
│
├─ Exercises (Tab 3)
│  └─ Exercise Detail
│     ├─ Progress Tab (existing)
│     └─ Insights Tab (new)
│        ├─ Plateau Detection
│        └─ Recommendations
│
├─ History (Tab 4)
│  └─ Workout Detail
│     ├─ Summary (existing)
│     └─ Insights Section (new)
│        ├─ Similar Workouts
│        └─ Workout Quality Score
│
└─ Analytics Dashboard (pushed screen, NOT a tab)
   ├─ Accessed via NavigationLink from Dashboard Insights Card
   ├─ Overview (2x2 grid: alerts + summary cards)
   ├─ Strength Trends
   ├─ Volume Analysis
   ├─ Muscle Balance
   ├─ Recovery Timeline
   └─ Workout Explorer (similar workouts)
```

---

### Grouping Strategy

**Dashboard Insights (3-5 cards):**
- Alerts (Plateau, Balance, Recovery) - always visible if active
- Milestones (PRs, Streaks) - rotates with other insights
- Recommendations (Exercises, Volume) - lowest priority

**Analytics Dashboard (6 sections):**
- Quick Insights (2x2 grid: alerts + summary)
- Detailed Analysis (list):
  - Strength Trends
  - Volume Analysis
  - Muscle Balance
  - Recovery Timeline
  - Workout Explorer

**Exercise Detail Insights (2 tabs):**
- Progress (existing: chart, stats)
- Insights (new: plateau, recommendations, history)

---

### Insight Lifecycle

```
Insight State Flow:
─────────────────
1. Detected → (system identifies pattern/alert)
2. Queued → (added to insights list with priority)
3. Shown → (displayed on Dashboard Insights card)
4. Tapped → (user views detail sheet)
5. Actioned → (user applies recommendation or dismisses)
6. Resolved → (condition no longer met, insight auto-hides)
7. Archived → (stored in history, accessible in Analytics)

Example: Plateau Alert
─────────────────────
Week 1-3: No plateau detected
Week 4: Plateau detected → Queued (priority 1)
Week 4 Day 1: Shown on Dashboard
Week 4 Day 2: User taps → Views detail
Week 4 Day 3: User applies recommendation → Actioned
Week 5: User increases weight → Plateau resolved
Week 6: Insight auto-hides, archived in Analytics
```

---

## Accessibility

### VoiceOver Support

**Dashboard Insights Card:**
```
VoiceOver: "Insights. Carousel, 3 of 5. Plateau Alert. Bench Press hasn't progressed in 4 weeks. Button. See Recommendations."
Action: "Swipe left to next insight. Swipe right to previous insight. Double-tap to open details."
```

**Strength Trends Chart:**
```
VoiceOver: "Strength trends chart. Bench Press, 85 kilograms, up 2 kilograms from last month. Squat, 120 kilograms, up 5 kilograms. Deadlift, 145 kilograms, up 8 kilograms. All lifts progressing. Double-tap to hear data points."
Action: "Swipe left/right to navigate between data points. Double-tap to hear detailed breakdown."
```

**Muscle Balance Radar:**
```
VoiceOver: "Muscle balance chart. Balance score 72 out of 100. Chest, 42 sets. Back, 38 sets. Legs, 22 sets, undertrained. Shoulders, 24 sets. Arms, 12 sets. Recommendation: Add 8 to 12 leg sets per week. Button."
```

**Similar Workouts:**
```
VoiceOver: "Similar workouts. 3 results. Result 1. Push Day A, February 2nd, 92 percent similar. 3 exercises match. Volume 12,100 kilograms. Buttons: View Details, Copy as Template."
```

---

### Chart Data Accessibility

**Provide audio summaries:**
- Each chart has "Hear Summary" button
- VoiceOver reads: trend, current value, change, interpretation
- Data table fallback for screen readers

**Example Audio Summary:**
```
User taps "Hear Summary" on Volume Trends Chart:
"Training volume over the last 12 weeks. Current weekly volume: 68 sets. 4-week average: 64 sets. Trend: gradually increasing. Status: within optimal range. No action needed."
```

---

### Dynamic Type Support

**Text Scaling:**
- All text respects Dynamic Type (iOS accessibility setting)
- Charts scale labels appropriately
- Minimum hit target: 44x44 points (Apple HIG)

**Layout Adjustments:**
- At largest text size, insights cards stack vertically (no 2x2 grid)
- Chart legends move below graph (not overlaid)
- Button labels wrap if needed

---

### Color Contrast (WCAG AA Compliance)

**Dark Theme Palette:**
- Background: #121212 (black)
- Surface: #1E1E1A (dark gray)
- Primary: #F2CC0D (yellow/gold)
- Text on Background: #FFFFFF (white) - 15.5:1 contrast ✓
- Text on Surface: #FFFFFF (white) - 12.8:1 contrast ✓
- Primary on Background: #F2CC0D on #121212 - 11.2:1 ✓

**Status Colors (Accessible):**
- Success (🟢): #34D399 (green) - 7.5:1 contrast ✓
- Warning (🟡): #F2CC0D (yellow) - 11.2:1 contrast ✓
- Danger (🔴): #EF4444 (red) - 5.8:1 contrast ✓

**Chart Lines:**
- Use distinct colors (not just hue)
- Add patterns for colorblind users (dashed/dotted lines)
- Labels directly on lines (not just legend)

---

### Reduced Motion Support

**Respect `UIAccessibility.isReduceMotionEnabled`:**

| Animation | Standard | Reduced Motion |
|-----------|----------|----------------|
| Insight reveal | Slide up + bounce | Fade in |
| Score count-up | 0→85 animated | Show final instantly |
| Confetti | Particle burst | Static ✓ icon |
| Chart data | Animate bars | Show final instantly |
| Carousel swipe | Spring physics | Crossfade |
| Sheet present | Slide up | Fade in |

**Example Implementation:**
```swift
if UIAccessibility.isReduceMotionEnabled {
    // Instant state change
    withAnimation(.none) {
        showScore = true
    }
} else {
    // Animated count-up
    withAnimation(.easeOut(duration: 1.2)) {
        score.animateCountUp(to: finalScore)
    }
}
```

---

### Alternative Text for Charts

**Provide text summaries below each chart:**

**Example (Strength Trends):**
```
Text below chart:
"Summary: Your squat has increased from 115kg to 120kg (+5kg) over the last 4 weeks. Bench press increased from 83kg to 85kg (+2kg). Deadlift increased from 137kg to 145kg (+8kg). All lifts are progressing steadily."
```

**Example (Muscle Balance):**
```
Text below chart:
"Summary: Your weekly training volume is 42 sets for chest, 38 sets for back, 22 sets for legs, 24 sets for shoulders, and 12 sets for arms. Legs are undertrained compared to upper body. Consider adding 8-12 leg sets per week."
```

---

### Haptic Feedback Preferences

**User setting (Settings → Haptics):**
- Full (default)
- Reduced (only critical alerts)
- None (no haptics)

**Intensity:**
- Critical alerts: Medium impact
- Success feedback: Light impact
- Navigation: Soft tap

---

## Copy & Tone

### Voice & Personality

**Core Principles:**
- Encouraging, never judgmental
- Clear and specific (avoid jargon)
- Actionable (always suggest next step)
- Personal (use "you" and "your")
- Celebrate wins, reframe setbacks

**Example:**
- ✗ Bad: "Plateau detected. Suboptimal volume distribution."
- ✓ Good: "Your bench press hasn't moved in 4 weeks. Try reducing volume to 20 sets per week."

---

### Insight Messages

#### Plateau Alert

**Title:** "Plateau Alert"

**Message:**
```
"Your {exercise} hasn't progressed in {X} weeks.

Here's what might help:
• Reduce volume to {Y} sets per week
• Add an extra rest day between sessions
• Try pause reps or tempo work

When you reduced volume in {month}, you broke through a similar plateau in 2 weeks."
```

**Tone:** Problem-solving, hopeful

---

#### Muscle Balance

**Title:** "Muscle Balance"

**Message (Imbalance):**
```
"Your legs are getting less attention than your upper body (48% less volume).

Try adding:
• 2 leg exercises per week
• Goblet Squats, Romanian Deadlifts

Balanced training leads to better overall strength and injury prevention."
```

**Message (Balanced):**
```
"Nice balance! Your muscle groups are getting similar volume.

Current split:
• Chest: 42 sets/week
• Back: 38 sets/week
• Legs: 40 sets/week

Keep it up!"
```

**Tone:** Informative, supportive

---

#### Recovery Status

**Title:** "Recovery Status"

**Message (Ready):**
```
"Your chest and legs are well-rested and ready to train today.

Last trained:
• Chest: 72 hours ago (18 sets)
• Legs: 96 hours ago (16 sets)

Go crush it!"
```

**Message (Caution):**
```
"Your back might need more recovery time before training again.

Last trained:
• 36 hours ago (24 sets - high volume)

Consider waiting 12 more hours, or train a different muscle group today."
```

**Tone:** Coach-like, protective

---

#### Volume Optimization

**Title:** "Training Volume"

**Message (Optimal):**
```
"Your volume is right in the sweet spot for growth.

Current: 68 sets/week
Optimal range: 55-75 sets

Keep doing what you're doing!"
```

**Message (Too High):**
```
"You might be doing a bit too much volume.

Current: 88 sets/week
Optimal range: 55-75 sets

More isn't always better. Try reducing by 10-15 sets to see if recovery improves."
```

**Message (Too Low):**
```
"You could benefit from a bit more volume.

Current: 42 sets/week
Optimal range: 55-75 sets

Try adding 1-2 exercises per workout, or an extra workout day."
```

**Tone:** Educational, non-judgmental

---

#### Strength Trends

**Title:** "Strength Progress"

**Message (Progressing):**
```
"All your lifts are moving in the right direction!

This month:
• Squat: +5kg
• Bench: +2kg
• Deadlift: +8kg

You're doing great. Keep up the consistency."
```

**Message (Stalled):**
```
"Your bench press has been stuck at 85kg for 4 weeks.

Your squat and deadlift are still progressing, so you're not overtrained. Try:
• Switching to 5×5 instead of 3×10
• Adding pause reps or tempo work
• Reducing frequency from 3x to 2x per week

Check the Plateau Alert for more details."
```

**Tone:** Motivating, strategic

---

#### Exercise Recommendations

**Title:** "Recommended for You"

**Message:**
```
"Based on your recent workouts, these exercises would be great additions:

Bench Press
✓ You PR'd last week (65kg)
✓ Low volume this month

Overhead Press
✓ Complements Bench Press
✓ Great for shoulder strength

Try adding one of these to your next push workout."
```

**Tone:** Helpful, personalized

---

#### Similar Workouts

**Title:** "Workouts Like This"

**Message (Matches Found):**
```
"Found 3 similar workouts from your history.

These had the same exercises and volume:
• Push Day A (Feb 2) - 92% similar
• Upper Body (Jan 24) - 87% similar
• Push Workout (Jan 15) - 85% similar

Tap to see what worked before."
```

**Message (No Matches):**
```
"This workout is unique! You haven't done anything quite like this before.

Keep exploring new training styles."
```

**Tone:** Reflective, explorative

---

### Empty States

#### Not Enough Data (1-4 Workouts)

**Title:** "Keep Going!"

**Message:**
```
"Complete 3 more workouts to unlock:
• Workout quality scores
• Strength trend charts
• Exercise recommendations

Progress: 2/5 workouts completed"
```

**Illustration:** Person lifting weights (outline style)

**Tone:** Encouraging, gamified

---

#### No Plateau Detected

**Title:** "No Plateaus Here!"

**Message:**
```
"All your exercises are progressing steadily.

Keep up the great work. We'll let you know if anything stalls."
```

**Illustration:** Upward trending arrow

**Tone:** Positive, reassuring

---

#### Muscle Balance Perfect

**Title:** "Perfectly Balanced"

**Message:**
```
"Your muscle groups are getting equal attention.

This is great for long-term progress and injury prevention."
```

**Illustration:** Balance scale (even)

**Tone:** Congratulatory, affirming

---

### Error States

#### Analytics Unavailable

**Title:** "Analytics Temporarily Unavailable"

**Message:**
```
"We're having trouble calculating your insights right now.

Your workout data is safe. Try again in a few minutes."
```

**Action:** [Retry] button

**Tone:** Calm, reassuring

---

#### Sync Failed

**Title:** "Couldn't Sync Data"

**Message:**
```
"Your workouts are saved locally, but we couldn't sync with the cloud.

Check your internet connection and try again."
```

**Action:** [Retry Sync] button

**Tone:** Informative, solution-oriented

---

### Motivational Copy

**Consistency Streak:**
```
"7-day streak! 🔥
You've worked out every day this week. That's dedication."
```

**Monthly Milestone:**
```
"20 workouts this month! 💪
That's your best month yet. Keep it up."
```

**PR Celebration:**
```
"New PR! 🏆
Bench Press: 85kg × 5 reps
You just beat your old record by 2.5kg. Nice!"
```

---

### Settings Copy

**Haptic Feedback:**
- Full (Recommended)
- Reduced
- None

**Push Notifications:**
- Plateau Alerts
- Recovery Reminders
- Weekly Summaries

**Analytics Privacy:**
- Share anonymous workout patterns to improve recommendations
- [Learn More]

---

## Implementation Notes

### Design System Tokens

```swift
// STColors (existing)
static let primary = Color(hex: "F2CC0D")        // Yellow/gold
static let background = Color(hex: "121212")      // Black
static let surface = Color(hex: "1E1E1A")         // Dark gray
static let border = Color(hex: "333129")          // Border
static let textPrimary = Color.white
static let textSecondary = Color(hex: "94A3B8")  // Light gray
static let success = Color(hex: "34D399")         // Green
static let danger = Color(hex: "EF4444")          // Red

// New: Analytics colors
static let warning = Color(hex: "F2CC0D")         // Yellow (reuse primary)
static let info = Color(hex: "3B82F6")            // Blue
static let chartLine1 = Color(hex: "F2CC0D")      // Yellow (primary)
static let chartLine2 = Color(hex: "34D399")      // Green
static let chartLine3 = Color(hex: "3B82F6")      // Blue
static let chartLine4 = Color(hex: "EC4899")      // Pink
static let chartLine5 = Color(hex: "8B5CF6")      // Purple
```

---

### Animation Tokens

```swift
// STAnimations (new)
enum STAnimations {
    static let insightReveal: Animation = .spring(response: 0.5, dampingFraction: 0.7)
    static let scoreCountUp: Animation = .easeOut(duration: 1.2)
    static let chartDataFill: Animation = .easeOut(duration: 0.8)
    static let carouselSwipe: Animation = .spring(response: 0.3, dampingFraction: 0.75)
    static let sheetPresent: Animation = .spring(response: 0.35, dampingFraction: 0.9)
    static let hapticDelay: TimeInterval = 0.05
}
```

---

### Priority Implementation Order

**Phase 1 (MVP):**
1. Dashboard Insights Card (basic)
2. Post-Workout Quality Score
3. Similar Workouts (basic matching)
4. Strength Trends (per-exercise charts)

**Phase 2 (Core Analytics):**
5. Plateau Detection
6. Muscle Balance
7. Exercise Recommendations
8. Recovery Timeline

**Phase 3 (Advanced):**
9. Volume Optimization
10. Cycle Comparisons
11. Predictive Analytics
12. Advanced Pattern Matching

---

### Testing Scenarios

**User Personas to Test:**
- Beginner (1-5 workouts)
- Intermediate (20-50 workouts)
- Advanced (100+ workouts)

**Edge Cases:**
- User with sporadic training (gaps >2 weeks)
- User with single muscle group focus (e.g., only legs)
- User with very high volume (powerlifter)
- User with very low volume (busy parent)

**Accessibility Testing:**
- VoiceOver navigation through all insights
- Dynamic Type at largest size
- Reduced Motion enabled
- Color blindness simulation (Protanopia, Deuteranopia)

---

## Appendix: Vector Similarity Algorithm Notes

**For developers implementing vector-based workout matching:**

### Workout Embedding Strategy

**Features to embed (normalized 0-1):**
1. Exercise IDs (one-hot encoded, aggregated)
2. Volume (total kg lifted)
3. Duration (minutes)
4. Muscle groups (weighted by sets)
5. Intensity (avg % of 1RM)
6. Rest times (avg seconds)
7. Exercise order (sequence similarity)

**Distance Metric:** Cosine similarity (0-1 scale)

**Similarity Thresholds:**
- 🟢 High: 0.90+ (very similar)
- 🟡 Medium: 0.75-0.90 (somewhat similar)
- 🔴 Low: <0.75 (not similar)

**Filtering:**
- Only show top 10 matches
- Minimum threshold: 0.70 (don't show poor matches)
- Sort by similarity DESC, then by date DESC

---

### Plateau Detection Logic

**Definition of Plateau:**
- Top weight for exercise unchanged for 4+ consecutive workouts
- AND at least 2 weeks elapsed
- AND user attempted same/similar rep range

**False Positive Prevention:**
- Ignore if user switched to different rep scheme (5 reps → 10 reps)
- Ignore if gap >2 weeks between workouts (deload, injury, vacation)
- Ignore if volume increased significantly (progressive overload via reps)

**Alert Timing:**
- Show on Dashboard after 4th consecutive workout
- Show on Exercise Detail page immediately

---

### Volume Optimization Ranges (Research-Backed)

**Beginner (0-1 year):**
- Optimal: 30-50 sets/week
- Too low: <25
- Too high: >60

**Intermediate (1-3 years):**
- Optimal: 50-75 sets/week
- Too low: <40
- Too high: >90

**Advanced (3+ years):**
- Optimal: 60-100 sets/week
- Too low: <50
- Too high: >120

**Per-Muscle Group:**
- Optimal: 10-20 sets/week per muscle group
- Too low: <8
- Too high: >25

---

## Conclusion

This UX design provides a comprehensive, user-centered approach to vector-based workout analytics in StrengthTracker. The design prioritizes:

1. **Progressive Disclosure** - Users unlock features as they generate data
2. **Actionable Insights** - Every insight includes a clear next step
3. **Accessibility** - Full VoiceOver support, Dynamic Type, high contrast
4. **Delight** - Thoughtful animations, haptics, and celebrations
5. **Personalization** - Insights based on the user's unique training history

**Key Design Decisions:**
- Keep existing 5-tab structure (Apple HIG max 5; analytics is exploratory, not transactional)
- Analytics Dashboard is a pushed screen from Dashboard Insights Card, not a tab
- Four contextual entry points: Dashboard Insights Card, Post-Workout Sheet, History Detail, Exercise Detail
- Progressive disclosure (5/10/20/50 workout thresholds) prevents empty screens and overwhelm
- Push critical alerts (plateau, recovery), pull exploratory insights (trends, volume)
- Warm, encouraging tone (coach, not judge)

**Next Steps for Implementation:**
1. Review with stakeholders (product, engineering, design)
2. Create high-fidelity Figma mockups
3. Build vector similarity service (backend)
4. Implement Phase 1 (MVP: Insights Card, Quality Score, Similar Workouts)
5. User test with 10 beta users (beginners + intermediates)
6. Iterate based on feedback
7. Ship Phase 2 (Plateau, Balance, Recovery)

---

**Document Version:** 1.0
**Last Updated:** 2026-02-16
**Status:** Ready for Review
