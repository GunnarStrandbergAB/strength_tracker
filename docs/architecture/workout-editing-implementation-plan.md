# Workout input implementation plan

## Scope and project protection

Implement the approved inline numeric-entry design on `edit-workout`. Keep native number/decimal keyboards. Defer wheels and extra +/- controls. Use existing compiled source and test files; never generate or modify the Xcode project, scheme, package references or signing settings. Compare project/scheme checksums before and after verification.

## Steps

1. Introduce a shared, tested numeric draft policy: comma/point input, at most two fractional digits for weight, integer reps, RPE/RIR range validation, blank vs zero, locale formatting and unchanged-value precision preservation.
2. Replace the workout numeric component with a native UITextField bridge. Select all on initial focus, retain normal cursor behavior within an active field, commit on editing end, and attach Previous/Next/Done directly to each field. Keep native accessibility, large scalable numerals, focus highlighting and dark keyboard/accessory styling.
3. Share the value editor between ordinary sets and drop segments. Move set metadata/previous values out of the narrow input grid; provide full-width readable values and an accessibility layout that stacks fields. Keep set completion a separate explicit action.
4. Flush editing before completion, Finish, navigation and backgrounding. Serialize active-workout UI operations and order persistence so async saves cannot revert newer edits. Retain identity checks, external-update safeguards, unit conversions and grouped-drop invariants.
5. Add tests in existing test sources for numeric policies, selection/replacement, field navigation and accessory lifecycle, untouched external updates, immediate Done/completion/Finish, delayed saves, drop segments and compact/accessibility layout rendering. Build the existing simulator scheme, run the full suite with coverage, inspect rendered images, and verify project checksums.

## Acceptance cases

- Tap 100, type 102,5, Done -> 102.5 kg; reopening selects the complete value.
- Tap 10, type 8 -> 8 reps; blank RPE -> 7,5; RIR zero remains a recorded zero.
- Typing a third meaningful fractional digit or an invalid character is rejected; pasting redundant trailing zeros is normalized. Invalid final RPE/RIR values never silently become a different recorded value.
- Focusing and leaving an existing lbs value without editing preserves the exact stored kg value. Display formatting is local to input and does not rewrite historical data.
- Previous/Next navigate the visible fields of a set; Done dismisses without completing it. Empty/invalid drafts have explicit commit behavior.
- Finishing immediately after typing waits for pending edit saves. A failed edit save must not finalize a workout as if it succeeded.
- External model updates do not overwrite active typing; leaving an untouched field adopts the newer model value. Removed/retyped rows cannot overwrite another row.
- Tests cover repeated keyboard opening, native toolbar presence, locale and units, ordinary/drop sets, delayed saves, and rendering at 375-point width and large accessibility text.

Physical-device confirmation of the user-reported intermittent keyboard disappearance remains a release check; simulator tests cannot establish that a device-only OS issue is resolved.

## Implemented and verified — 6 September 2026

- Shared native numeric editor is used by ordinary sets and drop segments, including editable workout history. Inputs are 52 points high at the default text size with scalable semibold digits; accessibility sizes stack vertically. Previous values sit above the fields.
- Fields select their value on initial focus, accept comma/point input, and own their dark Previous/Next/Done accessory. Focused input scrolls into view when the keyboard appears. Weight display uses up to two decimals without rewriting untouched stored values.
- Completion, Finish, field-hiding/reordering actions and history Done flush edits. Exercise/workout notes retain an explicit Done action and flush pending text before Finish. Ordered persistence prevents delayed saves from reverting newer input. Failed saves keep the draft and expose Retry Save; cancellation waits for in-flight saves before deleting the workout.
- Added 13 regression tests: 8 native-input/rendering tests and 5 save-ordering tests. Coverage includes locale parsing, optional values, invalid ranges, selection, navigation, repeated accessory presentation, external updates, note debounce flushing, delayed writes, immediate Finish, failed-save retry, cancellation and grouped-drop invariants.
- Existing simulator scheme built successfully. Final full suite passed **1,118 tests** (342 XCTest + 776 Swift Testing), with code coverage enabled. Result: `/tmp/edit-workout-verified-tests.xcresult`; log: `/tmp/edit-workout-verified-tests.log`.
- Visually inspected production row captures at 375-point width with default and accessibility text sizes. The initial window capture produced blank images; the corrected view-layer capture shows readable, unclipped controls. Captures are in `/tmp/edit-workout-final-renderings/`.
- The project file and shared scheme match their pre-work SHA checksums. No project generation or project-setting edits were performed.

Device-only keyboard behavior still needs confirmation on an iPhone.
