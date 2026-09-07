# Enhanced Grok tools implementation plan

Implement on `enhanced-grok-tools`. Use the existing Xcode project and scheme; never run project generation or change project/signing/package settings. SHA checksums are saved in `/tmp/enhanced-grok-project-before.sha`.

## Delivery checklist

- [x] Add explicit programme duration throughout domain persistence, all four generators, wizard and AI creation; preserve legacy plans.
- [x] Add stable programming origins and reversible deload prescriptions using percentages of normal scheduled weights. Protect these prescriptions from adaptive recalculation and historical replay.
- [x] Implement preview/apply plan edits: convert/insert/move/remove deload, repeat/extend, reschedule/skip, template/exercise/target changes, with explicit scope and protection of completed/in-progress sessions.
- [x] Wire a shared preview and version-checked save path into Grok confirmation cards and manual plan actions. Record adjustments and refresh plan views/Watch sessions.
- [x] Expand source queries with stable IDs, pagination, exact recorded precision and structured sets.
- [x] Expose preferences, quality, load, exercise progress, muscle coverage, training patterns, recovery and plan progress through the existing calculations. Correct duplicate plan-workout attribution.
- [x] Add regression and UI tests in existing compiled test files; build and run the complete simulator suite with coverage, review renderings, check project SHA checksums.
- [x] Prepare the implementation and PR description for delivery after verification.

## Behaviour

Converting a week keeps subsequent dates. Inserting a deload shifts the remaining open schedule by seven calendar days and retains all original sessions; multiple insertions extend the plan. Calendar weeks are addressed by dates across block boundaries. Closed and in-progress sessions cannot be structurally edited. Changes are previewed, revalidated and applied once; stale previews fail rather than overwriting newer work. Existing prescriptions are retained unless explicitly edited.

New plans support 4–52 programming weeks, including scheduled deloads. Existing defaults remain 12 weeks for linear/DUP/WUP and 10/9 for block plans. Inserted recovery weeks are additional schedule time. Block phase lengths are allocated deterministically for the chosen duration, with each phase represented.

Analytics tools return app-calculated results, source IDs, units, windows, data availability and limitations. They do not replace the current cards, scoring concepts or canonical coach verdict. Source data remains distinct from inferred or smoothed values.

## Verification cases

All programme types and levels; 4/8/12/16/52-week durations; legacy JSON round trips; midweek starts and DST; three inserted deloads with no lost sessions; conversion versus insertion; move/remove/undo semantics; partially completed weeks; in-flight phone/Watch workouts; preserved prescriptions after APRE and history replay; stale/repeated confirmation; save failures; immediate Watch refresh; structured pagination and sub-kilogram precision; source-to-calculation parity; missing versus zero; matching-session plan attribution; compact/accessibility manual and chat previews.

## Completed verification

- Existing-project simulator build: **BUILD SUCCEEDED** (`/tmp/enhanced-grok-build-final.log`).
- Full suite with code coverage enabled: **1,148 tests passed**, comprising 349 XCTest and 799 Swift Testing tests (`/tmp/enhanced-grok-tests-final.xcresult`). This adds 30 tests to the previous 1,118-test suite; the duration test also exercises 20 programme/duration combinations.
- Compact and accessibility confirmation screenshots reviewed. The overview uses expandable session details and retains the complete change list.
- `git diff --check` passed. Project and shared-scheme checksums match the pre-change files; no generation, signing or package-setting changes.
- Live Grok requests and physical Watch delivery were not exercised; the simulator builds include the Watch and widget targets. New tools use existing local services, with mock-backed source/calculation parity tests.

Legacy plans keep their existing prescriptions and unknown original duration. When editing a legacy deload without a saved normal prescription, the editor uses the nearest matching ordinary session and shows the resulting targets in the preview; it rejects changes if no such prescription is available.
