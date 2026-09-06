# Analytics makeover implementation

Implements the reviewed [plan](analytics-improvement-plan.md). The [layout study](analytics-layout-preview.html) remains illustrative; the revised four-component quality and shared widget requirements govern the implementation.

## Views

Analytics now presents: completed workouts, one coach verdict, training load, exercise progress, best training time, training quality, muscle coverage, recovery estimates, and an explicit Training patterns navigation card. Progress has a searchable full list and dated exercise detail; load history, calculation explanations, full muscle lists and check-ins expand on demand.

Training patterns replaces Advanced Insights with an explained Training state, dated weekly set chart, stable workout types with actual session drill-downs, and four-week comparisons. Notable sessions compare working sets with prior matching routines. Empty/insufficient evidence is stated explicitly. Lower-rep work is named literally because rep changes alone cannot establish heavier loading or training intent.

The redundant plateau, recommendation, Smart Highlights, duplicate verdict, fingerprint, drift and block-similarity cards are removed. Volume response remains computed and available through the registered `get_volume_response` AI tool.

## Calculations and consistency

- Quality retains four equal weights, the 80% volume benchmark ceiling, intensity relative to prior exercise bests, Rest Rhythm and EWMA lambda 0.3. Program balance is now visible in session detail. Baselines are anchored to each session; volume prefers at least three sessions with the same exercise mix and labels the per-muscle fallback. Provisional values are identified and excluded from a definitive aggregate when measured sessions exist. Differences are score points. Cache identity includes workout/history content, bodyweight and model version.
- The e1RM estimator uses one monotonic Epley formula for the supported 1–15 rep range. Historical analytics are recalculated under model version 2. A serialized one-time migration re-elects automatic personal records, preserves manual records, refreshes derived caches and marks success only after the record rebuild succeeds. Raw workout loads/reps are unchanged; derived PR badges can change.
- Progress uses elapsed calendar weeks in a recent 12-week window. Classification accounts for slope uncertainty and a bounded observed loading resolution alongside a relative floor. Stale or ambiguous results are neutral; maintaining does not mean an unwanted plateau. Detail exposes the uncertainty margin and observation count. The shared advisor excludes inactive/unclear lifts from its assessed denominator.
- Training load retains daily short/long EWMAs and zero-load rest days. Optional RPE recording no longer changes the load index. Displayed zones describe baseline comparison, not safety. The chart is retrospectively standardized with current exercise bests and resolved bodyweight, which is disclosed. Cached snapshots expire after 60 seconds; foreground and visible-screen refresh advance time-dependent metrics without a workout edit.
- Muscle coverage uses direct working sets/week and separately attributed indirect credits, with a common denominator and no universal muscle-balance prescription. The existing quality Program balance rubric remains a separate, explained index.
- Recovery aggregates all exercises before calculating muscle exposure, attenuates small indirect doses, accounts for overlapping sessions, and scales against a person's usual exposure. Optional daily ready/sore check-ins make bounded, prior-weighted adjustments. These are estimates, not measured recovery times or validated readiness predictions.
- Workout types use stable template/exercise-composition identity. Duplicate display labels do not overwrite fingerprint counts. Frequencies share one trailing-window denominator.
- Best training time compares matched routines with sufficient measured scores in both buckets, uses correct time boundaries and reports score points. Weak evidence produces no directional finding.
- Volume response requires complete dose windows and fully elapsed response weeks, distinguishes observed zero dose from unlogged weeks, reports independent-block coverage, and avoids the erroneous highest-tested-bin claim. Its tool explicitly describes observational evidence, spread, missingness and bodyweight provenance.

## Shared highlights and integrations

The template generator owns compatible advice and observations for the app and phone widgets. Hold/deload actions take priority; widgets no longer invent independent volume or quality praise. Analytics advice and post-workout numerical facts bypass unrestricted text rewriting.

Highlights carry stable topic/entity destinations and explicit expiry. Small widgets open the displayed exercise; medium/large rows link to relevant explanations. Expiry survives active-workout-only writes, and scheduled expiry entries suppress stale advice even without a fresh app computation. Older payloads decode safely and do not become fresh merely because a timeline entry is new. Existing Pro access checks remain in navigation.

The AI analytics tool uses the same progress/coverage/advisor results and no longer exposes a separate raw deload action. Watch targets continue to build with the shared models; this change does not add an analytics feed to the watch protocol.

## Validation

Verified on the iPhone 17 Pro simulator (iOS 26.2): `xcodebuild clean build test` passed for the iOS app, phone widgets, watch app and watch widgets. All 1,093 tests passed (333 XCTest and 760 Swift Testing tests). Code coverage was enabled and the result bundle is `/tmp/strength-analytics-verified.xcresult`. Xcode reports 39.99% overall including test code; the shared-package target has no attributed source coverage in this report, so this is not a production analytics coverage percentage. Compact and accessibility-size rendering attachments were exported and visually inspected. Regression coverage includes causal historical scoring and cache invalidation, four-component/EWMA reconciliation, rest blocks, progression gaps/noise/small gains/staleness, RPE-independent load and clock expiry, recovery aggregation/check-ins, coverage units, stable grouping, matched time comparisons, AI tool output, widget expiry/legacy decoding and derived-record migration. Hosted rendering tests exercise production cards at compact and accessibility text sizes and attach screenshots for visual review.

Scientific calibration remains distinct from software verification. No private historical training dataset was supplied for held-out validation. Loading resolution is inferred and bounded, not a known equipment increment; recovery learning is deliberately conservative. The implementation does not claim that either improves real-world training outcomes. Manual recovery check-ins and prospective data would be needed to establish that.
