# Strong Workout Tracker App - Feature Research

> Research compiled from app store listings, user reviews, feature documentation, and community discussions. Strong is available on iOS, Apple Watch, and Android. This document focuses on the iOS/Apple Watch experience.

---

## 1. Exercise Library and Categorization

### Built-in Library

- Ships with approximately **300+ exercises** pre-loaded in the database.
- Each exercise entry includes:
  - **Name** (e.g., "Barbell Bench Press", "Dumbbell Curl")
  - **Primary muscle group** targeted
  - **Secondary muscle groups** engaged
  - **Equipment required** (barbell, dumbbell, cable, machine, bodyweight, etc.)
  - **Exercise type/category** (barbell, dumbbell, machine, cable, bodyweight, cardio, duration-based, etc.)
  - **Instructions**: Step-by-step text description of proper form
  - **Images**: Static illustrations showing the movement (typically two images depicting start and end positions). These are drawn/illustrated rather than photographs.
  - Strong does NOT include video demonstrations in the exercise library (a common user request). Users see static images only.

### Muscle Group Organization

Exercises are organized by the following muscle groups: Chest, Back, Shoulders, Biceps, Triceps, Forearms, Core/Abs, Quads, Hamstrings, Glutes, Calves, Full Body/Other. Users can filter by muscle group when browsing. The app shows a body map/muscle diagram on workout summaries indicating which muscles were worked.

### Equipment Categories

Exercises can be filtered by equipment: Barbell, Dumbbell, Machine, Cable, Bodyweight, Kettlebell, Resistance Band, Other/Miscellaneous.

### Custom Exercises

- Users can create custom exercises with: custom name, primary muscle group, equipment type, exercise category (determines tracking type: weight+reps, bodyweight+reps, duration, distance+duration, etc.)
- Custom exercises appear alongside built-in exercises in search results but do NOT support custom images or instructions.
- Free tier limits custom exercises; Pro removes the limit.

### Search and Filter

- **Search bar** at the top of the exercise picker with instant/local partial matching.
- **Filter chips** for muscle group and equipment type.
- **Recent** section shows recently used exercises.
- **Favorites** mechanism -- exercises can be starred for a dedicated favorites filter.

### Exercise Tracking Types

| Category | Fields Tracked |
|----------|---------------|
| Weight and Reps | Weight (lbs/kg), Reps |
| Bodyweight and Reps | Reps only (optionally +added weight) |
| Duration | Time (mm:ss) |
| Distance and Duration | Distance (mi/km), Time |
| Weight and Duration | Weight, Time |
| Reps Only | Reps |

---

## 2. Workout Logging

### Core Logging Interface

- **Active workout view** occupies the full screen. Workout title editable at top. Elapsed timer always visible.
- Each exercise displayed as a **card/section** with: exercise name, set table (columns: set number, previous performance, weight, reps, checkmark), and "Add Set" button.
- **Add Exercise button** always available mid-workout.

### Set Logging

- Each set row shows: set number, **previous performance** (what user did last time, e.g., "135 lb x 10" -- key UX feature), weight input, reps input, checkmark button.
- **Numeric keypad** optimized for quick weight entry.
- Completing a set (checkmark) highlights the row green and **auto-starts rest timer**.
- Swipe left to delete sets; long-press to reorder.

### Set Types

- **Normal** (default), **Warm-up (W)** (excluded from volume/PR), **Drop set (D)**, **Failure (F)**
- Toggle by tapping the set number indicator.

### Supersets

- Group 2+ exercises together. Visually connected with a colored bar/bracket on the left.
- Rest timer can be configured to start only after the full superset round.

### Rest Timer

- **Auto-starts** after completing a set.
- **Per-exercise configurable** (e.g., 90s for bench, 60s for curls) with a global default fallback.
- **Push notification** when timer expires (works backgrounded). **Apple Watch haptic** tap.
- **Skip, +30s, -30s buttons** available.

### Workout Templates

- Store: workout name, ordered exercises, target sets/reps/weight, superset groupings, per-exercise rest times.
- **Template-first home screen**: templates listed prominently for one-tap launch.
- **Quick Start**: "Start Empty Workout" button for ad-hoc sessions.
- Free tier: ~3 templates. Pro: unlimited. Pro also adds **template folders**.

### Additional Logging Features

- Notes per exercise and per workout.
- Auto-fill weight/reps from previous session.
- Drag-and-drop exercise reorder mid-workout.
- Replace exercise mid-workout.
- Cancel/discard workout option.

### Workout Summary (Post-Workout)

Total duration, total volume, sets completed, PRs broken (highlighted), muscle group body map, share as image option.

---

## 3. History and Progression

### Workout History

- **History tab**: Reverse chronological list with date, name, duration, volume, exercises.
- **Calendar view**: Monthly view with dots on workout days.
- Searchable/filterable by exercise name and date range.

### Personal Records (PRs)

- Tracks: **estimated 1RM** (Epley/Brzycki), **max weight**, **max volume (single set)**, **max reps at weight**.
- PR sets highlighted with **trophy/medal icon** during and after workout.
- Exercise detail screen shows full PR history.

### Progression Charts

- Per-exercise line charts: estimated 1RM, max weight, total volume, best set volume over time.
- Time range filters: 1mo, 3mo, 6mo, 1yr, all time.
- Workout-level stats: total workouts, avg duration, total volume, frequency, streaks.
- Muscle group volume distribution (body map or pie chart).

### Body Measurements

- Tracks: body weight, body fat %, circumference measurements (neck, chest, biceps L/R, forearms L/R, waist, hips, thighs L/R, calves L/R).
- Each has its own trend chart. Manual entry (Apple Health syncs body weight).

### Data and Backup

- Apple Health read/write integration (calories, duration, heart rate).
- Cloud sync across devices.
- **CSV export** of full history (date, workout name, exercise, set, weight, reps, distance, duration, notes, RPE).

---

## 4. Apple Watch Integration

### Watch Features

- Start workouts from Watch (templates or quick start).
- Log sets: see previous/target, adjust weight/reps via Digital Crown or +/- buttons, mark complete.
- Rest timer with countdown display and haptic completion tap.
- Pause, resume, finish workout controls.
- Scroll/swipe between exercises.

### Standalone vs Companion

- **Companion**: Real-time sync when iPhone nearby; log on either device.
- **Standalone**: Works without iPhone. Syncs back when reconnected.
- Initial setup requires iPhone.

### Mid-Workout Watch Experience

- Current exercise with set details prominent. Digital Crown for scrolling and value adjustment.
- Haptic feedback on set completion and rest timer.
- Active workout complication shows duration.
- Rest timer takes over display with large countdown.
- Heart rate collected and synced to Apple Health.

### Watch Limitations

- No template creation, custom exercise creation, history/charts, or exercise instructions on Watch.
- Weight editing requires more taps than phone.

---

## 5. Widgets and Notifications

### iOS Widgets

- **Small**: Workouts this week or last workout date.
- **Medium**: Recent workout summary.
- **Large**: Detailed stats, weekly volume, mini calendar.
- **Lock screen** (iOS 16+): Compact stats.

### Live Activity (iOS 16+)

- Lock screen and Dynamic Island during active workout: elapsed time, current exercise, rest timer countdown.

### Notifications

- Rest timer expiry (push notification with sound, backgrounded).
- Workout reminders (scheduled days/times).
- PR celebration (in-app).
- No spam/motivational notifications.

### Watch Complications

- Quick launch, last workout date, workouts this week, active workout duration.

---

## 6. Other Features

### Routines/Programs

- Templates for each workout day, organized in folders (Pro).
- No auto-progression or periodization engine.
- No built-in programs from trainers.

### Warm-Up Sets

- Manual: add sets and mark as "W" type. Excluded from volume/PR calculations.
- No automatic warm-up calculator.

### Plate Calculator

- Shows plates per side for barbell exercises.
- Configurable bar weight (default 45lb/20kg) and plate inventory.

### Unit Preferences

- Global metric/imperial setting.
- Per-exercise override available.
- Unit switching converts historical data.

### Social/Sharing

- Post-workout summary card sharing (image to social/messages).
- No in-app social feed, followers, leaderboards, or coach mode.

### RPE Tracking

- Optional RPE column (1-10 scale) per set.

### Apple Health

- Writes: workout sessions, duration, calories, active energy.
- Reads: body weight.
- Heart rate from Watch.

### Free vs Pro

| Feature | Free | Pro |
|---------|------|-----|
| Workout logging | Unlimited | Unlimited |
| Templates | ~3 | Unlimited |
| Custom exercises | Limited | Unlimited |
| History | Full | Full |
| Charts | Limited | Full |
| Folders | No | Yes |
| CSV export | Yes | Yes |
| Watch | Yes | Yes |

### Dark Mode

- Default dark theme. Follows iOS system setting.

---

## 7. UI/UX Patterns

### Navigation

- Bottom tab bar: Workout/Home, History, Exercises, Profile/Settings.

### Key Patterns

| Pattern | Implementation |
|---------|---------------|
| Progressive disclosure | Details hidden until tapped |
| Inline editing | Weight/reps edited in-row, no modals |
| Contextual reference | Previous performance always visible |
| Automatic actions | Rest timer auto-starts |
| Minimalist chrome | Content-first, minimal decoration |
| Swipe actions | Delete/reorder sets |
| Color coding | Green for completed, distinct warm-up styling |
| Celebration moments | PR trophy badges inline |
| Template-first home | Templates dominate home screen |
| Numeric keypad | Optimized for weight entry |

### Design Language

- **Colors**: Dark gray/black backgrounds, blue accents, green for positive states.
- **Typography**: SF system font; bold weight values and names; light gray secondary info.
- **Spacing**: Generous between exercises; compact within set rows.
- **Icons**: Minimal -- trophy, checkmark, plus.

---

## 8. Competitive Differentiators

### Strengths (from reviews)

1. Simplicity and lack of bloat
2. Speed of set logging
3. Previous performance always visible
4. Clean, best-in-class design
5. Strong Apple Watch app
6. CSV data export
7. Reliability and stability

### Weaknesses (from reviews)

1. No exercise video demos
2. No auto-progression / built-in programs
3. Limited free tier (~3 templates)
4. No social features or community
5. No web/desktop version
6. No trainer/coach mode
7. Subscription pricing friction
8. Limited cardio tracking (no GPS runs, no treadmill integration)

---

## 9. Technical Details

- **Platforms**: iOS, iPadOS, watchOS, Android
- **iOS**: Supports current and 2 prior major versions
- **watchOS**: 7+ approximately
- **App size**: ~50-80 MB
- **Offline**: Full logging works offline; syncs when connected
- **Storage**: Local SQLite + cloud sync
- **HealthKit**: Full read/write integration
