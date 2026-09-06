# Complementary statistics implementation

## Contract with the analytics remake

Keep the dashboard card order, coach verdict, recent 12-week progression classification, four-component quality score and 0.3 EWMA, load calculation, and direct/indirect set attribution. New period controls affect historical presentation only. No project generation, project/scheme edits, model migrations, or new coaching thresholds.

## Implementation sequence

1. Add tested, shared session history calculations: completed working sets, drop segments counted once, exercise-specific metrics, missing-value handling, deload marking, period filters, three-observation medians and descriptive comparisons. Keep legacy ProgressViewModel outputs compatible.
2. Replace the exercise-library graph and analytics exercise detail with one opaque, dark history screen. Add 4W/3M/6M/1Y/All plus YTD/custom dates, metric preferences, observations, selected-session evidence, workout navigation and supporting averages. Preserve a separately labelled recent 12-week verdict.
3. Complement the existing Exercise progress card with up to four persisted pins, miniature histories and descriptive period changes. Keep automatic selections when no exercises are pinned and search across logged exercises, including limited-history exercises.
4. Add history destinations to Quality, Muscle coverage and Load. Score full history before filtering; never restart smoothing at a selected boundary. Show individual quality observations/provisional reasons, weekly direct and indirect exposure, and both load indices. Existing dashboard calculations remain authoritative.
5. Extend existing compiled test files with regression coverage, build the existing simulator scheme and run the full suite with coverage. Verify project and scheme checksums are unchanged.

## Interpretation rules

- Performance changes compare the median of the first three and last three non-deload observations; require six observations, no overlap, and observations within the first/last quarter of the selected interval. They are descriptive changes, not a second coaching verdict.
- Activity totals compare the selected interval with the immediately preceding equal elapsed duration only when history covers that interval; today's figures are partial. No percentage when the preceding value is zero. All-time activity has no preceding-period comparison.
- Three-session trailing median is optional; raw points remain visible. Gaps over 21 days break the displayed line and smoothing window. This is a presentation convention, not a training threshold.
- Fixed-rep and fixed-load metrics match recorded efforts, without estimating missing sets. Bodyweight uses the app's existing effective-load model and current resolved bodyweight retrospectively. Negative added loads are labelled as assistance where present; no new inferred assistance model.
- No combined kg-per-rep headline across different exercises. Supporting averages are within one exercise, using only complete load/repetition evidence and explicit denominators.
- Duration/distance show recorded activity, not inferred strength or performance. Exercise technique, machine and range-of-motion differences remain limitations.

## Deferred

Combined strength index, population rankings, RPE-adjusted strength, and changes to training advice. The new histories complement the remake; only the two old exercise charts are replaced by a shared screen.

## Completion and validation — 6 September 2026

Implemented all five stages in existing compiled source/test files. Both exercise entry points now share the history view; the searchable list includes logged exercises with limited evidence. Pins and per-exercise metric/rep/load choices persist locally. Session lists start at 12 with explicit expansion. Strength axes fit observations and explicitly disclose that they may start above zero.

Quality history preserves the aggregate inclusion policy and cold start; its regression tests reconcile all five final values. Load defaults to its existing 56 displayed days, with an optional full-history request for the new detail. Completed history now loads before the quality feature unlock, allowing new lifters to inspect logged exercises; quality scoring and volume-response feature gating stay intact.

Validation:
- Existing simulator scheme build: **BUILD SUCCEEDED**.
- Final full suite with coverage enabled: **1,105 tests passed** (334 XCTest + 771 Swift Testing), zero failures. Includes 11 new statistics regression tests and one new render test at phone/accessibility sizes.
- Rendered screenshots inspected for readable exercise names, solid dark backgrounds, period controls and chart readability.
- `git diff --check`: clean.
- Existing `project.pbxproj` and shared scheme SHA checksums match their pre-implementation values. No generation command or project/signing edit was used.

Local artifacts: `/tmp/complement-stats-build.log`, `/tmp/complement-stats-final-tests.log`, `/tmp/complement-stats-final-tests.xcresult`, `/tmp/complement-stats-final-attachments/`.

The workout drill-down is a read-only evidence view with the user's resolved units/bodyweight context. This work does not add workout editing, infer historical bodyweight, or change coaching/AI/widget classifications.
