# Plan: Watch Workout Set List — Editable Sets with Vertical Scrolling

## Context

On the Watch, once you tap "FINISH SET" there's no way to go back and correct weight/reps. The +/- buttons are close to the FINISH SET button causing accidental taps. The only recourse is long-press delete + re-enter. On iOS this is solved because all sets are visible and inline-editable. The user wants a competitor-style pattern where sets are rows in a vertical list that can be scrolled and tapped to edit, with the rest timer shown inline between sets.

## Current Architecture

The exercise tab in `WatchActiveWorkoutView` has a flat VStack:
1. Metrics bar (HealthKit)
2. Exercise name + "Set X/Y"
3. `WatchSetInputView` (weight/reps +/- cards + FINISH SET button) — OR `exerciseCompletionView`
4. Exercise navigation (< counter > flag)
5. Horizontal set chips (small, long-press-to-delete only)

`WatchSetInputView` is a standalone view with `@State weight/reps`, Digital Crown bindings, `inputCard()` helper, and the FINISH SET button. It calls `viewModel.logSet()`.

`WatchWorkoutViewModel` has `logSet()` (complete set + start rest) and `removeSetFromCurrentExercise()` (delete set) but no method to update an existing completed set.

## Design

Replace the flat "input view + chips" layout with a **vertical scrollable set list**. Each set is a row. The active/editing set expands with input controls. Completed sets are compact tappable rows. The rest timer shows as a compact inline indicator.

### Layout (exercise tab, top to bottom)

```
┌─────────────────────────┐
│  ❤️56  🔥42  ⏱️12:30    │  ← metrics (unchanged)
│  BENCH PRESS             │  ← exercise name (unchanged)
├─────────────────────────┤
│  ✓ S1  60 × 10          │  ← completed set row (tappable to edit)
│  ── REST 1:23 ────────  │  ← compact rest indicator
│  ✓ S2  60 × 10          │  ← completed set row
│  ── REST ─────────────  │
│ ┌─────────────────────┐ │
│ │ S3          SET 3/5  │ │  ← active set (expanded)
│ │ [- 60 +]  [- 10 +]  │ │  ← input cards (Digital Crown)
│ │ [═══ FINISH SET ═══] │ │
│ └─────────────────────┘ │
│    S4  60 × 10  ○       │  ← planned/future (dimmed)
│    S5  60 × 10  ○       │
├─────────────────────────┤
│  ◁    2/4    ▷     🏁   │  ← exercise nav (unchanged)
└─────────────────────────┘
```

When tapping a completed set to edit:
```
│ ┌─────────────────────┐ │
│ │ S1       EDITING     │ │  ← now expanded
│ │ [- 60 +]  [- 10 +]  │ │
│ │ [═══ UPDATE SET ═══] │ │  ← UPDATE instead of FINISH
│ └─────────────────────┘ │
│  ✓ S2  60 × 10          │
│  ○ S3 (next)             │  ← active new-set row hidden while editing
```

### Row states

| State | Appearance | Height | Interaction |
|-------|-----------|--------|-------------|
| **Completed** | `✓ S1  60×10` on dark bg | ~32pt | Tap → expand to edit. Long-press → delete. |
| **Active/Editing** | Input cards + FINISH/UPDATE button | ~110pt | Weight/reps +/-, Digital Crown, action button |
| **Planned** (template) | `○ S3  60×10` dimmed | ~28pt | Not interactive (waiting) |

## Implementation

### Step 1: ViewModel additions (`Shared/ViewModels/WatchWorkoutViewModel.swift`)

Add state for editing:

```swift
public var editingSetId: UUID? = nil
```

Add method to update an existing completed set **without restarting rest timer**:

```swift
public func updateSet(setId: UUID, weight: Double?, reps: Int?, rpe: Double? = nil) {
    guard var workout = activeWorkout,
          currentExerciseIndex < workout.exercises.count,
          let setIndex = workout.exercises[currentExerciseIndex].sets.firstIndex(where: { $0.id == setId })
    else { return }
    workout.exercises[currentExerciseIndex].sets[setIndex].weight = weight
    workout.exercises[currentExerciseIndex].sets[setIndex].reps = reps
    if let rpe { workout.exercises[currentExerciseIndex].sets[setIndex].rpe = rpe }
    activeWorkout = workout
    connectivityManager.sendWorkoutSnapshot(workout)
    editingSetId = nil
}
```

Add begin/cancel editing:

```swift
public func beginEditing(setId: UUID) { editingSetId = setId }
public func cancelEditing() { editingSetId = nil }
```

Reset `editingSetId = nil` at end of: `logSet()`, `nextExercise()`, `previousExercise()`.

### Step 2: Create `WatchSetRowView.swift` (`WatchApp/Features/ActiveWorkout/`)

New ~160-line view. Three visual states based on props:

**Props:**
- `viewModel: WatchWorkoutViewModel`
- `set: ExerciseSet`
- `setIndex: Int`
- `isExpanded: Bool` — true for active-new-set or editing-existing-set
- `isPlanned: Bool` — true for incomplete template sets that aren't the next one
- `initialWeight: Double?`, `initialReps: Int?` — pre-fill values

**When collapsed (completed):**
- HStack: set order, weight × reps, checkmark icon
- `.onTapGesture { viewModel.beginEditing(setId: set.id) }`
- `.onLongPressGesture { viewModel.removeSetFromCurrentExercise(at: setIndex) }`

**When collapsed (planned/future):**
- HStack: set order, target weight × reps (dimmed), circle outline icon
- Not interactive

**When expanded:**
- Migrated `inputCard()` from WatchSetInputView (the +/- card rendering)
- `@State var weight: Double`, `@State var reps: Double` initialized from `initialWeight`/`initialReps`
- Digital Crown bindings (`.focusable()`, `.digitalCrownRotation()`)
- Action button:
  - If `set.isCompleted` (editing existing): "UPDATE" → calls `viewModel.updateSet(setId:weight:reps:)`
  - If not completed (new set): "FINISH SET" → calls `viewModel.logSet(weight:reps:)`

### Step 3: Restructure `WatchActiveWorkoutView.swift` exercise tab

Replace lines 79-159 (set info label + WatchSetInputView/completionView + chips) with:

```swift
ScrollViewReader { proxy in
    ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 4) {
            // Set counter
            setCounterLabel

            ForEach(Array(current.sets.enumerated()), id: \.element.id) { index, set in
                let isEditing = viewModel.editingSetId == set.id
                let isNextIncomplete = !set.isCompleted
                    && current.sets.prefix(index).allSatisfy(\.isCompleted)
                    && viewModel.editingSetId == nil
                let isPlanned = !set.isCompleted && !isNextIncomplete

                WatchSetRowView(
                    viewModel: viewModel,
                    set: set,
                    setIndex: index,
                    isExpanded: isEditing || isNextIncomplete,
                    isPlanned: isPlanned,
                    initialWeight: set.weight ?? viewModel.currentTargetWeight,
                    initialReps: set.reps ?? viewModel.currentTargetReps
                )
                .id(set.id)
            }

            // Compact rest indicator (between completed and active)
            if viewModel.isResting {
                compactRestIndicator
            }

            // New set row (quickstart or extra sets beyond template)
            if !current.sets.contains(where: { !$0.isCompleted }) && viewModel.editingSetId == nil {
                if !viewModel.currentExercisePlannedSetsComplete || isAddingExtraSet {
                    WatchSetRowView(
                        viewModel: viewModel,
                        set: ExerciseSet.empty(order: current.sets.count + 1),
                        setIndex: current.sets.count,
                        isExpanded: true,
                        isPlanned: false,
                        initialWeight: viewModel.currentTargetWeight,
                        initialReps: viewModel.currentTargetReps
                    )
                    .id("new-set")
                } else {
                    exerciseCompletionView
                }
            }
        }
    }
    .onChange(of: viewModel.editingSetId) { _, id in
        if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
    }
    .onChange(of: viewModel.currentSetNumber) { _, _ in
        withAnimation { proxy.scrollTo("new-set", anchor: .center) }
    }
}
```

Remove: horizontal set chips ScrollView (lines 149-159) and `setChip()` function (lines 166-191).

Keep: `exerciseCompletionView` (unchanged), exercise navigation HStack (unchanged).

### Step 4: Add `ExerciseSet.empty()` convenience

In `Shared/Models/Domain/WorkoutSet.swift`, add a static factory for the "new set" placeholder row:

```swift
public static func empty(order: Int) -> ExerciseSet {
    ExerciseSet(
        id: UUID(),
        order: order,
        setType: .normal,
        weight: nil, reps: nil,
        durationSeconds: nil, distanceMeters: nil, rpe: nil,
        isCompleted: false, isPersonalRecord: false, completedAt: nil
    )
}
```

### Step 5: Handle `logSet` for new sets from the list

The current `logSet()` finds the first incomplete pre-populated set or appends. This still works:
- Template: the expanded "next incomplete" row calls `logSet()` → finds and completes that pre-populated set
- Quickstart / extra: the "new-set" row calls `logSet()` → appends a new completed set

No change to `logSet()` logic needed.

### Step 6: Delete `WatchSetInputView.swift`

Once WatchSetRowView handles all input, WatchSetInputView is unused. Delete `WatchApp/Features/ActiveWorkout/WatchSetInputView.swift`.

## Files Summary

| File | Action | Changes |
|------|--------|---------|
| `Shared/ViewModels/WatchWorkoutViewModel.swift` | Modify | Add `editingSetId`, `updateSet()`, `beginEditing()`, `cancelEditing()`. Reset editing in `logSet`/`nextExercise`/`previousExercise`. |
| `WatchApp/Features/ActiveWorkout/WatchSetRowView.swift` | **Create** | ~160 lines. Three-state set row (completed/expanded/planned). Migrates `inputCard()` from WatchSetInputView. |
| `WatchApp/Features/ActiveWorkout/WatchActiveWorkoutView.swift` | Modify | Replace lines 79-159 with ScrollViewReader + vertical set list. Remove `setChip()`. Keep exerciseCompletionView and nav. |
| `Shared/Models/Domain/WorkoutSet.swift` | Modify | Add `ExerciseSet.empty(order:)` static factory. |
| `WatchApp/Features/ActiveWorkout/WatchSetInputView.swift` | **Delete** | No longer referenced. |

## Verification

1. **Build:** `cd StrengthTracker && xcodebuild -project StrengthTracker.xcodeproj -target "StrengthTracker" -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -configuration Debug clean build`
2. **Quickstart flow:** Start quickstart → log set → see it as completed row → tap it → values load in expanded row → change weight → tap UPDATE → row collapses with new values → new active set row appears
3. **Template flow:** Start from template → see planned sets as dimmed rows → first set is expanded → finish set → rest timer shows inline → completed row + next set expands
4. **Accidental tap recovery:** Finish set by mistake → tap the completed chip → correct values → UPDATE → continue
5. **Exercise navigation:** Edit a set → tap > to next exercise → editing resets → navigate back with < → previous exercise shows its set list correctly
6. **Long-press delete:** Long-press completed row → set removed → remaining sets reorder
7. **Rest timer:** Finish set → rest timer auto-starts → compact indicator visible in set list → full-screen timer tab accessible via page swipe
