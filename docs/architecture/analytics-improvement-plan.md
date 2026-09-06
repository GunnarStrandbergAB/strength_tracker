# Analytics improvement plan

Code and screenshot review · 6 September 2026 · Revised after quality-score and widget feedback · Proposal, not an implementation

The recommendation is to keep two destinations, **Analytics** and **Training patterns**, promote Training Load and Progressive Overload to Analytics, and replace five abstract cards with one explainable Training State module. Retain the workout-count card. Remove Plateau Warnings, Recommendations, the duplicate verdict, and the Volume Response graphs from the normal UI.

This review traces the current checkout, rather than assuming that every screenshot was produced by this exact build. It does not have the underlying 115 workouts, so it identifies reproducible code behavior and likely causes, not a recalculation of your personal results. No application code has been changed. Small independent arithmetic checks were run; the Swift test suite and iOS simulator were not run for this planning task.

## 1. Proposed navigation and card order

### Analytics: what should I pay attention to?

| Order | Card | Behavior |
|---|---|---|
| 1 | Workouts completed | Keep the large number, with explicit “All time.” Slightly reduce vertical padding. |
| 2 | Coach verdict | One headline, one action, at most two reasons. Tap “Why?” for evidence and all possible verdicts. |
| 3 | Training load | Promote from Advanced. Keep the ratio, explain it in plain language, and offer a dated trend in detail. |
| 4 | Progressive overload | Promote from Advanced; optionally title it “Exercise progress.” Show 4–5 pinned/recent lifts and “View all exercises.” |
| 5 | Best training time | Promote. Show sample counts and a score-point difference; expand for like-for-like comparisons. |
| 6 | Training quality | Preserve the existing 0–100 score, components and smoothing; correct baselines and explain the session-to-aggregate connection. |
| 7 | Muscle balance → Muscle coverage | Direct and indirect working sets, visible date range, personal targets only where available. |
| 8 | Recovery estimate | Compact summary of recently trained muscles; expand to all muscles and optional check-in. |
| 9 | Explore training patterns → | A clear navigation row: “Training state, workout types and changes over time.” No unrelated summary data. |

Each long card is a preview, not a whole report. The five most useful cards should be reached before any multi-screen list. Training patterns can also be reached through a small header action so it is not only available after scrolling. Keep the existing five app tabs and navigation stack; this does not need a sixth tab.

### Training patterns: how is my routine changing?

1. **Training State** — current pattern, observed changes, dated timeline, and clear explanation of possible states.
2. **Workout types** — readable groups, counts and frequencies for one shared window; tap a type for its actual sessions.
3. **What changed** — an expandable section of Training State with raw before/after values, plus dated unusual sessions only when useful. This is not another permanent alert card.

Progression, load and recovery each open their own focused detail screen from Analytics. They are not duplicated on Training patterns. If retaining the name “Advanced Insights” is preferable, the same structure still works; “Training patterns” more accurately describes the remaining content.

## 2. How the current system works

The SwiftUI views read `WorkoutAnalyticsViewModel`. It loads a `WorkoutInsights` aggregate from `WorkoutAnalyticsService`, then separately calculates aggregate quality and volume response. Raw workouts and exercise metadata come from repositories; vector analytics use persisted 18-dimensional workout vectors. The services run on device. Templates choose highlights; Apple Intelligence can rewrite their wording.

The orchestrator computes plateaus and balance first, feeds them to exercise recommendations, calculates recovery and population volume landmarks, then computes load/progression/verdict and vector-based features after the Advanced gate. It excludes deloads from progression, balance, drift, anomalies and archetypes, but includes them for load/recovery and phase detection.

The current AI tool `get_analytics_insights` reads the orchestrator. It returns plateaus, balance, load zone, verdict, deload and highlights. **It does not expose the volume-response calculation, full progression series or recovery details.** Volume response currently lives outside the aggregate, in the view model.

Sources: [view model](../../StrengthTracker/Shared/ViewModels/WorkoutAnalyticsViewModel.swift), [orchestrator](../../StrengthTracker/Shared/Services/Analytics/WorkoutAnalyticsService.swift), [read tools](../../StrengthTracker/Shared/Services/AI/Tools/ReadTools.swift). All code links below are relative to this document.

## 3. Card-by-card findings and decisions

### Workouts completed — keep

Counts completed workouts across all history, including deloads. This is straightforward and useful. Label it “All time”; a selected analysis window must not silently redefine this number.

### Coach verdict — keep once, improve evidence and confidence

There are three model kinds and four visible headlines:

| Headline | Current trigger/precedence |
|---|---|
| Deload in progress | Latest completed session is tagged deload and within 7 days; internally a Hold verdict. |
| Hold steady | A layoff of at least 10 days, moderate fatigue recommendation, load zone 1.3–<1.5, broad regression, or persistent estimated fatigue. |
| Deload recommended | Load zone ≥1.5, at least two primary deload triggers, or urgency ≥0.5. |
| Clear to progress | Fallback after the above rules. |

The shared advisor is a good architectural foundation. Keep it, but fix these issues:

- “No fatigue signals” can mean missing evidence. Add **Building baseline / insufficient evidence**, rather than interpreting absent inputs as clearance.
- A load ratio alone can trigger a deload. Use neutral load context and corroborating performance/effort/user feedback before strong advice.
- Fatigue checks require at least three fatigued groups AND that none were just trained. One just-trained group suppresses the whole rule, even if three other groups remain fatigued. Filter out just-trained groups first, then count the remainder.
- The deload verdict persists for at least five days and requires non-deload evaluations on two distinct days to release unless a deload is logged. Explain persistence; refresh evidence even while retaining the recommendation. “Clear days” currently also counts raw Hold outcomes, not only Progress.
- A low load ratio does not establish “room to add work”; a low baseline or missing logs can produce the same observation.
- A “recent deload session” is not necessarily a planned deload week. Prefer explicit plan/user context for that claim.

Use scoped copy: “Overall: continue your planned progression” can coexist with “Hip thrust: stable over the last 6 weeks.” It must not promise that every exercise is progressing or every muscle is recovered.

Sources: [TrainingAdvisor](../../StrengthTracker/Shared/Services/Analytics/TrainingAdvisor.swift), [verdict model](../../StrengthTracker/Shared/Models/Domain/Analytics/TrainingVerdict.swift), [DeloadDetectionService](../../StrengthTracker/Shared/Services/Analytics/DeloadDetectionService.swift).

### Training quality — preserve the concept, improve reliability and explanation

**Revised direction:** retain an evaluative 0–100 quality score with fixed scoring rules, Volume, Intensity, Rest Rhythm and the existing Balance contribution. Keep session scoring, the aggregate and deload-aware scoring connected. Do not replace this with plan adherence, require a training plan, remove Rest Rhythm, or introduce a new composite simply to redesign the screen.

“Absolute” here means the same scoring rubric and score bands, rather than a percentile ranking or completion percentage of a plan. The existing volume/intensity inputs are personalized against history, so it is not an absolute measure comparable between people. That distinction should be clear in “How this is scored,” without complicating the main card.

**The session and aggregate scores are already connected:** `WorkoutQualityScoreService` produces the per-workout components and overall score. `computeAggregateScore` calls that same scorer for completed workouts and smooths the resulting overall and component values. Workout detail, the completion summary and the widget use this service/model too. With the current equal weights and identical smoothing, the aggregate overall equals the average of its four aggregate components before display rounding. Preserve this identity.

**Current volume calculation:** completed non-warmup set volume, including effective bodyweight load and drop segments, is attributed 70% to the primary muscle and 30% divided between secondary muscles. For each muscle used in the session, compare current volume with average volume per session involving that muscle in the last 12 weeks, excluding deloads and the current workout. Average those muscle scores equally.

The muscle score is `min(100, 100 × ratio / 0.8)`: 40% of historical average gets 50 points; 80%, 100% and 200% all get 100. This is not simply total session volume, but it still compares different exercises through kg×reps and treats matching 80% of historical volume as perfect.

The overall workout score equally averages four components:

| Component | Current rule | Concern |
|---|---|---|
| Volume | Per-muscle comparison above | Exercise substitutions and split changes affect tonnage without proving better/worse training. No upper penalty; omitted muscles are not evaluated. |
| Intensity | Mean set e1RM / exercise best e1RM over six months, capped at 100 | Performance relative to a best is not the same as effort or intended intensity. |
| Balance | 12-week intensity-weighted volume across six presumed opposing pairs | A rolling program characteristic is repeatedly scored as session quality. |
| Rest rhythm | Variation of completion-to-completion intervals | Includes set duration/transitions. Uniform timing is not necessarily appropriate timing. |

The aggregate is an exponentially weighted moving average: `Qnew = 0.3 × sessionScore + 0.7 × Qprevious`. About **91.8% of weight belongs to the last seven sessions**, once enough history exists. “Based on 115 recent workouts” describes the number processed, not the effective window. The trend compares with an EWMA near four weeks ago; the fallback index can also compare against the first workout when the requested boundary is absent.

Important hard-coded assumptions: 12-week volume/balance windows; six-month best e1RM; equal 25% component weights; 0.8 volume threshold; 0.3 smoothing; 70/30 attribution; default scores of 72/75/80; rest intervals restricted to 15–600 seconds, with variation cutoffs 0.25 and 0.8. Deload scoring uses fixed volume and intensity target bands.

**Correctness issue:** historical workouts are rescored using cutoffs anchored to `Date()` and potentially later workouts. Historical balance includes the current 12-week history. Old scores therefore incorporate future information and do not mean “quality at the time.”

**First fix the hidden-component mismatch.** `WorkoutQualityScoreView` intentionally displays only Volume, Intensity and Rest Rhythm because Balance describes the wider program, but still displays the four-component overall score. Keep the current 25% weights initially and show a fourth, clearly distinguished row: **Program balance · prior 12 weeks including this session**. Explain that it contributes 25% of the overall score. The completion sheet can stay compact, with a link to the same four-part breakdown. Do not create a separate three-component headline score for one surface.

Incremental improvements, in order:

1. **Correct time anchoring and consistency.** Score each workout against history available before that workout; include the workout itself only where intended, such as its resulting rolling balance. Anchor the 12-week and six-month windows to the workout date, not today. Store/cache the score with workout ID, relevant history revision, model version and baseline provenance. Recompute dependent scores after a history correction; later training should not rewrite an earlier causal baseline. Guard the workout-detail state by workout ID so concurrent loads cannot show another workout's score.
2. **Keep the volume rubric initially.** Retain the current per-muscle comparison and `min(100, 100 × ratio/0.8)` curve, including its ceiling. Explain that 100 means “met this volume benchmark,” not “maximal growth stimulus.” Do not award extra points for doubling volume, or add a new hard-coded penalty for doing more. Show actual volume and baseline in detail. First correct windows and no-data handling; then improve comparability using the same exercise/equipment mix or a stable session family where enough samples exist. Fall back to the existing per-muscle baseline with a visible comparability note for changed routines. Keep tonnage comparisons within comparable exercises; do not silently equate leg-press and squat kilograms or switch the metric to hard sets in this revision. Retain 0.8 as an explicit product parameter until historical replay justifies changing it.
3. **Keep intensity as performance relative to the exercise baseline.** Retain the mean set-e1RM / historical-best score, cap and six-month baseline initially. Explain this definition; it does not measure RPE or proximity to failure. Fix the shared non-monotonic 5-to-6-rep transition and flag poorly modeled exercise/rep types. Review outlier bests before they depress months of scores. RPE can appear as context, without quietly becoming a new weighted component or requiring every set to have RPE.
4. **Keep Rest Rhythm.** It measures regularity of logged set intervals. Preserve the coefficient-of-variation concept, but calculate variation within comparable exercise/rest blocks when enough intervals exist, rather than penalizing legitimate differences between heavy sets and accessories. Exclude exercise changes, pauses and known superset/drop transitions using available metadata. Check whether actual timer/start events exist before calling the intervals “rest duration”; completion-to-completion gaps also include lifting time. Explain the current 15–600-second filters and 0.25/0.8 variation cutoffs. Keep the current curve initially and calibrate any change against representative sessions, including intentionally varied rest. With too few trustworthy intervals, report a provisional component rather than imply excellent or poor timing.
5. **Retain Balance as transparent program context.** Anchor its rolling window to the scored session. Keep its current weight while auditing the six pair definitions, missing-side treatment and muscle taxonomy. Its intensity-weighted-volume method is different from the dashboard's raw-tonnage balance method; do not automatically replace it when Muscle Coverage changes. Explain that this is an app-defined distribution benchmark, not a diagnosis or a requirement that every muscle receive identical work. Improvements to pair rules require a documented formula revision and replay, not an unreviewed new set of ratios.
6. **Make insufficient evidence explicit without redesigning the score.** If a fallback value is used, attach a provisional flag and explanation to that component and the overall. The 72/75/80 defaults must not appear as observed measurements or generate “quality improved” claims. Do not renormalize remaining weights silently. The aggregate can retain its existing smoothing, but should exclude incomplete/provisional sessions from a definitive trend and state coverage; if evidence is not sufficient, show a building-baseline state. A provisional session can still show its available component values. All consumers must share the same inclusion rule.
7. **Keep EWMA at 0.3.** Label Analytics **Recent training quality** and detail **Latest session** separately. Example: prior aggregate 70 and new session 80 produces 73, not 80. Use identical components/weights on every surface. Explain that recent sessions dominate; replace “115 recent workouts” with “115 sessions scored · weighted toward your latest sessions,” plus coverage when needed. Use score-point changes versus a correctly selected prior boundary. For post-workout “above your average,” compare with the aggregate *before* this workout; the current debrief passes all workouts and can include the very session being compared.
8. **Use consistent fixed colors.** The session view uses score bands (80/60/40), while Analytics colors the aggregate and all its component bars from the overall historical percentile. This mixes absolute and relative presentation. Use the same fixed score-color rules across session, aggregate and widget, with each component colored by its own score. Historical percentile may remain an optional detail, not the main grade.
9. **Keep explicit deload scoring.** Preserve the lighter-volume/intensity rubric for tagged deloads, describe it as a different intentional-session rubric, and fix its baseline comparability. A good deload may score well; it must not create a “push harder” message. Avoid penalizing intentional deloads in widget fallbacks.

No plan-adherence conversion or wholesale score replacement is proposed. Separate mechanical corrections from later calibration: deliver transparent weights, fixed colors, correct baselines and connected displays first. Keep existing constants until evidence supports targeted changes. Corrections that alter scores still need a model version and an explicit historical recomputation policy; never splice differently scored histories into one unexplained trend. The score remains an app-defined training-quality index, rather than a clinically validated measure.

Sources: [WorkoutQualityScoreService](../../StrengthTracker/Shared/Services/Analytics/WorkoutQualityScoreService.swift), [session breakdown](../../StrengthTracker/iOS/Features/Analytics/Views/WorkoutQualityScoreView.swift), [completion summary](../../StrengthTracker/iOS/Features/Workout/Views/PostWorkoutSummaryView.swift), [score models](../../StrengthTracker/Shared/Models/Domain/Analytics/WorkoutQualityScore.swift), [post-workout comparison](../../StrengthTracker/Shared/Services/Analytics/CoachingInsightService.swift).

### Muscle balance — keep as Muscle coverage

There really is an apples-to-pears comparison. The card sizes bars by attributed kg×reps, but labels them with direct working-set counts. A muscle can have a bar and “0 sets” because secondary contribution affects one metric but not the other. Fields called `weeklyVolume` and `weeklySetCount` are actually totals across the selected window, normally four weeks. The API's default 30 days is truncated to four whole weeks here.

Six fixed pairs are compared: chest/back, quads/hamstrings, biceps/triceps, shoulders/lats, core/lower back, glutes/hip flexors. Weight-volume equality is assumed desirable; ratio thresholds 1.25, 1.5 and 2 drive severity. The recommendations then prescribe another 1–2 sets, +20–30%, or +30–40%, without knowing your goal, intended split, equipment or exercise mechanics. Zero-volume sides are skipped, which can even yield a perfect balance score for narrow coverage. The quality card handles missing sides differently, creating another disagreement.

Replace this with direct working sets plus separately visible estimated indirect credits, divided by the actual number of weeks. Draw and label the same metric. Compare each muscle with its own prior period and user/plan target, not a different muscle's tonnage. Use neutral “less represented” language unless a target is known. Group overlapping muscle names consistently and audit exercise metadata. Let users expand “Back” to lats/traps, without double-counting parent and child totals.

Fractional set counting has research support as an analytical convention, but the app's **0.5 divided across all secondary muscles** is not the same as counting each relevant indirect set as 0.5. Treat attribution as an explicit, versioned approximation; never call it measured muscle stimulus. [Pelland et al., dose-response meta-regressions](https://pubmed.ncbi.nlm.nih.gov/41343037/).

Sources: [MuscleBalanceService](../../StrengthTracker/Shared/Services/Analytics/MuscleBalanceService.swift), [recommendation text](../../StrengthTracker/Shared/Models/Domain/Analytics/MuscleBalance.swift), [shared attribution](../../StrengthTracker/Shared/Services/Analytics/AnalyticsCalculations.swift).

### Volume response — remove UI, preserve and improve analysis for AI tools

The implementation is more thoughtful than the presentation suggests: effective sets, trailing dose, normalized exercise e1RM changes, robust bin summaries, exercise continuity and explicit data sufficiency. It compares pre/post windows around a week, needs at least two populated bins for a best-range claim, and at least three observations to populate a bin. Low confidence is currently visible.

However:

- Adjacent observations reuse weeks, so observation counts overstate independent evidence. Within each observation pre/post windows are separate, but successive observations overlap.
- The dose average skips zero/absent muscle weeks rather than consistently representing a calendar-week average. Missing logs, rest weeks and excluded deloads need separate treatment.
- The maturity cutoff includes the week whose W+3 is the current, unfinished week; require its full follow-up window to have ended.
- IQR whiskers describe spread, not confidence intervals of the estimated mean/median.
- Strength proxy changes are not measurements of muscle growth or proof that a dose caused an improvement.
- `bestObservedSoFar` covers a best bin at either boundary. The sentence always says “highest tested range,” explaining the contradictory biceps text.
- The upper-bound routine also says “not yet tested above” when higher bins exist but show no qualifying decline. Distinguish “tested, no clear limit” from “not tested.”
- Small data and overlapping IQRs cannot identify a personal maximum recoverable volume. Population `VolumeLandmarkService` is a separate model, yet highlights can present its hard-coded limits as MRV facts.

Move analysis ownership into a shared query service, retaining the existing full weekly e1RM series even if the visible progression window becomes shorter. Add `get_volume_response(muscle_group, lookback_weeks)` to the existing registry. Return bins, raw observation counts, independent-block coverage, observed date range, metric definition, missingness, confidence reasons, tested range, model version and `interpretation: observational`. Return an explicit insufficient-data result. Never rely only on generated prose. Do not automatically send extra history to Grok; the existing tool call should request and receive the scoped result.

Sources: [VolumeResponseService](../../StrengthTracker/Shared/Services/Analytics/VolumeResponseService.swift), [VolumeLandmarkService](../../StrengthTracker/Shared/Services/Analytics/VolumeLandmarkService.swift), [AI registry](../../StrengthTracker/Shared/Services/AI/Tools/AIToolRegistry.swift).

### Plateau warnings — remove; consolidate its consumers

The Hip Thrust contradiction has a plausible direct cause: plateau detection uses recent week-to-week best-e1RM comparisons, while overload fits all historical trained weeks. An exercise can have a positive long-run slope and a recent flat period. The UI gives neither scope. Plateau thresholds also differ by training status: >2% improvement for beginners, any improvement for intermediate, and tolerance of nearly 2% decline for advanced. Missing weeks can count as stalled time.

Removing the card alone is insufficient. Early highlights, recommendations and AI output also use the plateau service. Migrate them to the same exercise-progress result. Distinguish “no recent exposure,” “maintaining,” “uncertain” and “possible plateau.” If long- and short-term views differ, state “Up over 12 weeks; stable in the last 4,” rather than issue conflicting standalone verdicts.

Source: [PlateauDetectionService](../../StrengthTracker/Shared/Services/Analytics/PlateauDetectionService.swift).

### Recommendations — remove

The service picks the first catalog candidate targeting a presumed gap or stalled muscle and assigns fixed confidence 0.9/0.85/0.7. It is not a personal ranking model. It also assumes repository input order when selecting recent workouts. Keep exercise choices in the existing contextual AI/plan flow, where goals and constraints can be considered. Remove these recommendations from early highlights too; audit non-dashboard consumers before deleting the service.

Source: [ExerciseRecommendationService](../../StrengthTracker/Shared/Services/Analytics/ExerciseRecommendationService.swift).

### Advanced Insights entry — replace with navigation

The current link pairs a phase label with the first highlight's detail while omitting that highlight's title. Thus “General” can sit above a Hip Thrust improvement sentence with no named exercise. Replace with a full-width navigation row, descriptive subtitle and prominent chevron. Add native navigation accessibility semantics.

Source: [AdvancedInsightsCardView](../../StrengthTracker/iOS/Features/Analytics/Views/AdvancedInsightsCardView.swift).

### Smart highlights — preserve the shared feature and widgets; remove only the redundant card

Templates choose up to five items: verdict/load warnings, population volume limits, two progressing lifts, load praise, phase, drift and recovery. Progressing lifts are selected even while holding/deloading. They can be true observations but must not become instructions to push harder. At lower workout counts, a separate early generator uses plateaus, balance and recommendations.

Apple Intelligence rewrites the selected details with a “motivating coach” instruction. For these highlights the prompt does not explicitly preserve numbers, uncertainty or time windows and there is no output validation. The enthusiastic screenshot text is consistent with this rewriting path, though the device execution was not observed.

Use structured facts with scope, dates, confidence and source IDs. Coach Verdict owns action advice; the other cards own observations. Any generated prose must preserve protected facts and be validated or fall back to deterministic text. Remove automatic cheerleading for “General” and remove unsupported “over MRV” certainty. Reuse summaries in chat/digests without duplicating another dashboard card. **Removing Smart Highlights from Advanced must not delete the generator, empty widget payloads or remove useful glanceable insights.**

The follow-up audit confirms these consumers:

| Surface | Current behavior | Revised plan |
|---|---|---|
| Advanced Insights | Shows generated highlights as a full card | Remove the redundant card; keep the shared feed and make every widget insight explainable in the app. |
| Training Hub small widget | Rotates one of up to three highlights through 30-minute timeline entries | Keep a useful glanceable observation; pin an active Hold/Deload action while valid rather than rotate into conflicting encouragement. Rotate compatible observations when no priority action needs pinning. |
| Training Hub medium widget | First two highlights; quality/stat fallbacks when fewer exist | One priority action, when relevant, plus one compatible observation. Do not duplicate a quality value already displayed nearby. |
| Training Hub large widget | First three highlights alongside weekly/workout context | Up to three distinct, useful items; fewer is acceptable. Keep active-workout controls unchanged. |
| AI analytics tool | Includes up to five highlights | Keep evidence-linked highlights with actual windows, not just rewritten text. |
| Phone completion summary | Separate `CoachingInsightService` bullets, including quality comparisons and progression | Retain this contextual summary; reuse canonical facts and action compatibility rules. |
| Watch app | Workout logging, metrics and finish summary; no analytics-highlight display found | No watch feature removal. Do not add a watch analytics screen as part of this revision. |
| Watch widget | Rest-timer display/controls, not the Training Hub analytics feed | Preserve it. Future analytics support would require an explicit sync/display feature. |

The watch conclusion is based on the WatchApp views, watch view model, connectivity code and `SyncMessageType`: there is no analytics-highlight/quality snapshot message in the current protocol. Watch workouts can feed phone analytics after synchronization, but this does not mean the resulting highlights are displayed on the watch.

**The widget has a second source of interpretation today.** `WidgetRefreshService` takes the analytics highlights, prepends the verdict if needed using title-string matching, then may add “Volume Up/Down” from this-week versus last-week average session tonnage and a Quality item always classified as an improvement. `WidgetDataService` copies the first three into shared App Group storage. These widget-only fallbacks bypass the generator's verdict-aware rules:

- An intentional deload can still be paired with a “Volume Down” warning.
- Mixed session types can make a tonnage change look like improvement/regression.
- Any quality value, even low or provisional, can be labeled as an improvement.
- `weeklyQualityScore` actually receives the all-history EWMA aggregate; it is not quality from this calendar week.
- Title matching is not a reliable identity/duplicate-suppression rule.
- The volume percentage divides by last week's average without checking it is positive, despite a logged workout being able to have zero countable tonnage.

**Proposed shared feed:** retain `AnalyticsHighlight` as the concept, with a stable topic/entity key, source result ID, observation-versus-action kind, measured window, confidence/coverage, `computedAt`, `validUntil`, short text and detail destination. One selector ranks compatible facts for each surface. The widget may select/format for available space, but must not invent a different analytic conclusion. Route volume/quality fallbacks through that selector or omit them. Do not force three highlights when only one is meaningful.

Priorities: active actionable verdict; relevant recent progression or session achievement; meaningful load/quality change with its window. Avoid treating “Clear to Progress” as mandatory first content forever when there is no actionable change. A positive exercise observation may coexist with Hold/Deload only if its wording is descriptive and preserves the current action context; otherwise omit it from the small widget. Prefer deterministic concise wording in widgets, with no independent model call. Carry validated in-app facts into the widget payload.

**Freshness needs separate timestamps.** Training Hub's provider reads a saved payload and makes new timeline entries; rotating/reloading that timeline does not recompute analytics. `WidgetData.updatedAt` is also advanced when only active-workout state changes, while the old highlights remain. Add analytics-specific generation/expiry fields that are not refreshed by unrelated state writes. Future entries should suppress expired advice and show a dated neutral summary or open-app prompt; do not imply that the app recomputed the verdict at the timeline-entry date. Rebuild on existing foreground/workout/edit refresh paths after fixing the revision-only analytics cache. Request appropriate timeline updates, but make the saved snapshot safe even if no new computation arrives.

**Tap-through:** small/medium currently link to `strengthtracker://analytics`; the large analytics content lacks an equivalent per-highlight destination. Add stable topic/entity deep links to the relevant card/detail (or its explanation sheet), not a removed Smart Highlights card. Test all widget sizes, expired/missing evidence and navigation after the card removal. Retain payload decoding compatibility so an app/widget version mismatch falls back gracefully.

Sources for the additional audit: [WidgetRefreshService](../../StrengthTracker/Shared/Services/WidgetRefreshService.swift), [WidgetDataService](../../StrengthTracker/Shared/Services/WidgetDataService.swift), [widget payload](../../StrengthTracker/Shared/Models/Domain/WidgetData.swift), [Training Hub timeline](../../StrengthTracker/iOS/WidgetExtension/TrainingHubWidget.swift), [widget views](../../StrengthTracker/iOS/WidgetExtension/TrainingHubViews.swift), [watch summary](../../StrengthTracker/WatchApp/Features/Summary/WorkoutSummaryView.swift), [watch widget](../../StrengthTracker/WatchApp/WidgetExtension/WatchRestTimerWidget.swift), [sync protocol](../../StrengthTracker/Shared/Models/Domain/SyncMessage.swift).

Sources: [TemplateInsightGenerator](../../StrengthTracker/Shared/Services/Analytics/TemplateInsightGenerator.swift), [AppleIntelligenceInsightGenerator](../../StrengthTracker/Shared/Services/Analytics/AppleIntelligenceInsightGenerator.swift).

### Training load — keep and promote, with clearer interpretation

Current session load is the sum across completed non-warmup effective-load parts:

`reps × min(effective load / best exercise e1RM, 1.5) × RPE modifier`

The RPE modifier is RPE/10 when recorded, otherwise 1. Missing e1RM falls back to 0.75 relative load. Sessions on the same day are summed; rest days are zero through today. Acute EWMA uses 0.25 and chronic EWMA 0.069, corresponding approximately to 7- and 28-day spans using 2/(span+1). Their ratio is ACWR. These are smoothed daily load indices, **not 7-day and 28-day totals**. Deloads correctly contribute lower load.

The service requires eight workouts spanning fourteen days, but the orchestrator only calls it after 50 completed workouts. Replace this global gate with card-specific baseline sufficiency.

The formula is internally coherent as a relative-load indicator, but needs these changes:

- Missing RPE is treated like RPE 10. Identical 3×10 at 75% e1RM yields 22.5 units without RPE versus 18 with RPE 8: a 20% change just from recording effort. Prefer stable unmodulated load plus a separately reported effort trend unless RPE coverage supports a consistent alternative.
- One current six-month best-e1RM map and current bodyweight are applied across history. Define whether charts are historical estimates or retrospectively standardized indices; version and explain that choice. Do not silently mix the two.
- Per-muscle load uses primary muscles only and a rolling-sum ratio, unlike overall EWMA and other attribution services. Label or align it before exposing it.
- Use a warm-up/baseline-building state and handle near-zero chronic load. Do not interpret an inflated return-from-break ratio as automatic overload.
- At 0.77, say “Recent load is about 23% below your smoothed baseline.” Retain both component values with units and dates. Show today's partial-day status.
- Replace “undertraining / optimal / danger” with descriptive “below / near / above / well above baseline.” The hard-coded 0.6, 1.3 and 1.5 thresholds are product heuristics, not measured safety boundaries.

ACWR has substantial methodological limitations as a predictor of injury or a basis for injury-prevention prescriptions. Keep its descriptive comparison without presenting a green zone as established safety or a ratio alone as a deload requirement. [Impellizzeri et al., conceptual issues and fundamental pitfalls](https://pubmed.ncbi.nlm.nih.gov/32502973/).

Sources: [TrainingLoadService](../../StrengthTracker/Shared/Services/Analytics/TrainingLoadService.swift), [AnalyticsCalculations](../../StrengthTracker/Shared/Services/Analytics/AnalyticsCalculations.swift), [load zones](../../StrengthTracker/Shared/Models/Domain/Analytics/TrainingLoad.swift).

### Training phase — replace with Training State

The app does not read a user-selected phase here. It matches weekly centroids to hand-tuned prototypes for accumulation, intensification, peaking and deload, using cosine similarity ≥0.85 and a winning margin ≥0.02. Otherwise it returns Mixed, displayed as General. That fallback means “no clear prototype match,” not necessarily “great variety.” The colored strip is a history of classified weeks, **not intensity scores**; it has no dates or legend. The smoothing pass leaves the latest week unsmoothed.

Vector assumptions further weaken the labels: volume is normalized by 20,000, average load by 150 kg, sets by 100, exercises by 15, duration by 90 minutes. “Compound ratio” actually means proportion of barbell exercises. Some dimensions include warmups. Missing RPE becomes zero. Absolute equipment loads and a normalized vector shape cannot establish training intention.

Build Training State from explainable changes in real units relative to the person's baseline. Proposed states: **Usual pattern; More volume; Heavier/lower-rep work; Lighter week; Returning after a break; Mixed changes; Building baseline.** These are descriptive labels, not grades. Planned phase, when available, is a separate “Plan says…” field. A detected lighter week is not automatically a logged deload.

Show a headline, two supporting changes and an eight-week dated timeline. Tap a week for working sets, median reps, relative load, session frequency, and comparison period. Missing weeks are explicitly missing or rest, depending on logging evidence. “What these states mean” lists every state and its criteria. Version/calibrate thresholds against user history; do not port the prototype arrays under new names.

Sources: [PhaseDetectionService](../../StrengthTracker/Shared/Services/Analytics/PhaseDetectionService.swift), [WorkoutVectorizer](../../StrengthTracker/Shared/Services/Analytics/WorkoutVectorizer.swift).

### Workout types — keep, fix identity and interpretation

K-means clusters normalized workout vectors, tries 2–8 groups and chooses a silhouette score winner. Different clusters can receive the same coarse name, hence two Mixed Training and two Full Body rows. Labels are assigned from normalized centroid values as if they were raw muscle proportions, so unrelated dimensions can affect the label. Random initialization can change groupings after recomputation.

Prefer explicit template identity/user names when available, then stable exercise-composition clusters for untemplated sessions. Use stable cluster IDs, deterministic initialization, and meaningful subtitles such as dominant exercises. Merge visually equivalent categories or give them descriptive distinctions; never merely append “2.” Calculate frequency for every group over the same visible window, including inactive time. Current frequency uses each cluster's first-to-last span, so an abandoned type can still show a high historical frequency. A generic 14-day stale warning should not imply the user must keep an obsolete routine.

Source: [WorkoutArchetypeService](../../StrengthTracker/Shared/Services/Analytics/WorkoutArchetypeService.swift).

### Training fingerprint — remove card; use only corrected supporting data

Variety is normalized Shannon entropy of workout-cluster distribution, not training quality. Stability is cosine similarity of current/prior distributions. The implementation keys distributions by **display label**, overwriting earlier clusters with the same name. It also normalizes entropy using cluster count while the label dictionary may have fewer categories. The reported 19% therefore cannot be trusted as implemented.

Fix identity first. Describe actual changes inside Training State, for example “Your last four weeks included fewer workout types.” Consistency can be intentional; fewer types must not automatically become red “regression.” Avoid another opaque percentage.

### Best training time — keep and promote, repair comparison

Uses all scored sessions, requires ten total and three per eligible time bucket, then shows only a best/worst gap above five points. It does not match workout type, plan, period or effort coverage. Morning is coded as 05:00–10:59 but labeled 06:00–11:00; night includes 22:00–04:59 but is labeled through 06:00. Correct labels/boundaries together.

79 versus 72 is **7 score points**, not 7% higher: the relative increase would be about 9.7%. Show “Morning sessions scored 7 points higher,” with sample counts and comparison dates. After quality is repaired, compare similar session types and training periods, expose uncertainty, and say “No clear difference yet” when appropriate. Do not assert that changing workout time will cause an improvement.

Source: [ChangePointDetectionService](../../StrengthTracker/Shared/Services/Analytics/ChangePointDetectionService.swift).

### Recovery status — keep as an estimate, fix aggregation before personalizing

Current recovery hours = fixed muscle baseline × `[1 + max(0, sets−4) × 0.08]` × `[0.8 + blended effort × 0.4]`. Baselines range from 36 to 64 hours; unlisted muscles default to 48. Effort blends e1RM-relative performance with RPE/10 when recorded. Ready means elapsed time ≥ estimated hours; Recovering starts at 70%; otherwise Fatigued.

For chest with ≤4 sets and blended effort 0.9, this predicts **74.2 hours**. The first four sets have the same volume modifier. This explains why even light exposures can appear to require days.

The larger implementation issue: it retains the first matching exercise on the most recent workout date, instead of aggregating that muscle across all exercises. Equal timestamps prevent subsequent updates. Secondary fractional credits are rounded to integers, yet even zero rounded credits reset the muscle's full timer. Earlier sessions' remaining fatigue is ignored. “Average recovery hours” is a heuristic estimate, not a measured personal average.

First fix session aggregation, preserve fractional exposure, distinguish direct/indirect work, avoid timer resets for negligible indirect exposure, and account for overlapping sessions with a bounded decay model. Use “Recently trained / Estimated recovering / Likely ready / Unknown” rather than diagnosing fatigue from time alone.

Personalization should learn cautiously from optional muscle soreness/readiness check-ins and comparable subsequent performance, with session dose relative to the person's usual dose. Use a population prior only as a labeled fallback, shrink estimates toward it when samples are sparse, expose confidence, and let feedback override a generic estimate. Training frequency alone is not evidence of full recovery. Optional sleep data may contextualize estimates but should not fabricate a precise muscle-ready time. Prefer a range and “Last trained 2 days ago” over a countdown asserting certainty.

Source: [RecoveryEstimationService](../../StrengthTracker/Shared/Services/Analytics/RecoveryEstimationService.swift).

### Progressive overload — promote and make exercise-specific

The service takes best e1RM per exercise per trained calendar week, requires four observed weeks, fits a straight line across **all history**, and applies a universal ±0.5 kg threshold. It sorts by absolute kg slope, making large lifts dominate. The regression uses 0,1,2… for observed weeks; gaps are compressed. Example: e1RM 100,101,102,103 in calendar weeks 0,2,4,6 displays +1 kg/week, although the actual slope is +0.5.

Use actual elapsed weeks; a default recent window (candidate 8–12 weeks) with selectable longer history; and last-observed date. Keep a separate full weekly series for research/tools. Compare the same exercise/equipment variant, use dated bodyweight where available, and distinguish bodyweight/leverage work and power exercises from ordinary loaded strength work. Jump-squat load alone cannot measure power progression.

Replace the universal threshold with a minimum meaningful change relative to each lift's baseline, equipment increments and observed variability. Report kg and percentage over the chosen window. A reliable +0.3 kg/week on a small lift can be progress; do not automatically replace 0.5 with another universal percentage. Use an uncertainty interval and persistence across comparable exposures. Broad/ambiguous estimates should be “Unclear”; maintenance should be neutral. Reserve “Possible plateau” for enough comparable recent exposures with a stated progression goal and no meaningful improvement. Planned maintenance should never be an alert.

Also audit the shared e1RM formula: it switches from Epley at 5 reps to Brzycki at 6, so 100×5 estimates 116.67 kg and 100×6 estimates 116.13 kg. An extra rep can lower the estimate. Reps above 15 are clamped, so improvements beyond 15 reps disappear. Define monotonic estimator behavior and use rep/effort records for movements where e1RM is inappropriate. Drop-segment maxima need comparable-set context.

Source: [OverloadTrackingService](../../StrengthTracker/Shared/Services/Analytics/OverloadTrackingService.swift), [shared e1RM](../../StrengthTracker/Shared/Services/Analytics/AnalyticsCalculations.swift).

### Training drift, block comparison, unusual sessions — fold into Training State detail

Drift is 1−cosine similarity between last 14 days and days 15–45. Block comparison is cosine similarity between adjacent four-week centroids. These are different windows, so 2% drift and 98% similarity need not be complementary. Normalized vector distance is not a percentage change in training dose; similar vector direction can hide meaningful magnitude changes. Remove these standalone percentages.

Anomalies compare historical sessions to one final EWMA centroid, then apply mean+2 SD and a 0.5 floor. Old sessions can look unusual relative to the newest routine; this is not necessarily a recent concern. The view omits workout name/date even though workout ID exists. “Lower effort” may also reflect missing RPE encoded as zero.

Use raw before/after metrics with dates in Training State. Surface an unusual session only against comparable earlier sessions, with a named workout link and a specific observation such as “35 minutes versus your usual 55–65.” Treat intentional shorter/lighter sessions neutrally. Retain vector calculations behind the scenes where useful, but do not convert their distances into literal human percentages.

Sources: [TrainingDriftService](../../StrengthTracker/Shared/Services/Analytics/TrainingDriftService.swift), [BlockComparisonService](../../StrengthTracker/Shared/Services/Analytics/BlockComparisonService.swift), [AnomalyDetectionService](../../StrengthTracker/Shared/Services/Analytics/AnomalyDetectionService.swift).

## 4. Cross-cutting architecture changes

1. **One analysis context:** pass `asOf`, calendar/timezone, data revision, model version and bodyweight provenance into services. Distinguish workout occurrence date from entry/completion time. Use explicit start/end dates for every metric.
2. **Refresh time-dependent data:** both view-model and orchestrator caches can return indefinitely for the same data revision. Recovery, load, days-since and verdict need expiry on foreground/day changes and relevant estimated transitions, even without a new workout. Cache raw reusable features separately from current-day interpretations.
3. **One exercise-progress result:** share status, window, observations, uncertainty and reasons across cards, AI, highlights, debriefs, recommendations and advisor. Consumers must not reclassify slopes.
4. **Shared metric definitions:** distinguish tonnage, direct sets, estimated indirect sets, relative-load index, effort and e1RM. Audit muscle metadata and historical load assumptions once. Do not force all metrics into a single attribution model when they measure different things.
5. **Separate evidence from wording:** results carry structured facts; the advisor produces actions; optional generated text is presentation only. Missingness and low confidence travel with the result through tool output.
6. **Card-specific availability:** stop requiring 50 total workouts for load/progression when their own data coverage is sufficient. Conversely, 115 sessions alone cannot unlock reliable volume-response or time-of-day conclusions.
7. **Accurate tool windows:** `time_window_days` currently changes balance's window while many other metrics use fixed/all-history windows. Return the actual window per metric and use scoped parameters. Preserve backward compatibility or version the output when migrating plateau fields.

## 5. Visual redesign

Preserve the app's dark surfaces and yellow identity. Improve hierarchy rather than add decoration:

- Sentence-case card titles, larger readable supporting text, tabular numbers only for aligned measurements, and semantic Dynamic Type styles instead of fixed 9–13 pt text.
- Reserve yellow for selection/actions, green for evidenced positive changes, amber for review and red for meaningful problems. A planned lighter week or narrower routine is neutral.
- Consistent full-width surfaces, 16–20 pt insets and 12–16 pt gaps. No nested verdict card, unexplained color strips or centered narrow drift island.
- Show one lead observation per card. Put formulas, secondary charts and complete lists behind clearly named drill-down actions.
- Every quantitative card shows dates and units. Every inferred card offers “Why?” with evidence and confidence. Chart labels must remain readable in dark mode; bars and right-side labels must encode the same quantity.
- Progression rows: exercise name, a small sparkline in detail, window change, neutral/progress/review label; allow long names to wrap and status to move below at accessibility sizes.
- Recovery: compact grouped rows and one optional check-in, rather than sixteen red/green judgments competing equally.
- Test the tab bar in push/pop, scroll and appearance transitions. Screenshot 4 shows a white tab bar; the current root already sets dark tab-bar styling, so reproducing this requires device/simulator testing rather than assuming the root cause. Verify bottom safe-area clearance and that the last content is reachable above the floating bar.

## 6. Delivery sequence and acceptance criteria

| Phase | Work | Exit criteria |
|---|---|---|
| P0: Trust | Time/cache context; progression calendar/e1RM issues; recovery aggregation; muscle unit mismatch; duplicate cluster identity; time-of-day copy; volume-response boundary wording | Deterministic examples pass; one snapshot has matching units/windows; no recent data is interpreted as missing evidence. |
| P1: Simpler UI | Shared preview components; reorder Analytics; remove requested cards while preserving widget highlights; explicit patterns navigation; readable theme/type/spacing; transparent four-component quality breakdown | Every existing card has an explicit keep/remove/merge destination; no full-list scroll traps; widget insights still resolve to explanations; all required drill-downs are reachable. |
| P2: Better interpretations | Calibrate exercise progression; incremental quality corrections with existing score/weights/EWMA retained; descriptive load zones; shared evidence/advice and widget selection; Training State; corrected workout types | Historical replay and expert review agree on representative scenarios; user can explain why a state or score appeared; widgets do not independently generate contradictory advice. |
| P3: Personalization and AI | Shared volume-response query/tool; response uncertainty fixes; recovery feedback calibration; matched time-of-day comparisons | UI and tools agree on a snapshot; low-data cases are explicit; personalization improves held-out performance over the fixed baseline before stronger claims ship. |

Dependencies: fix quality before promoting time-of-day conclusions as trustworthy; fix cluster identity before using fingerprint data; fix progression before wiring new advisor/highlight thresholds; fix recovery aggregation before learning recovery parameters. UI removals can ship independently, but they must not leave the same misleading claims in early highlights or AI tools.

Implementation should extend the existing Swift analytics tests, including AggregateQualityScoreTests, E1RMConsolidationTests, TrainingAdvisorTests, TemplateInsightGeneratorTests, VolumeResponseServiceTests and AI ReadToolsTests, plus focused progression/recovery/cluster coverage. Test meaningful behavior rather than restating threshold constants:

- Calendar gaps, stale exercises, tiny but consistent small-lift gains, noisy flat data, intentional maintenance and exercise substitutions.
- More reps at the same load never lowers the selected progression proxy; high-rep and power exercises receive appropriate metrics.
- Workout exercise order does not change recovery; multiple exercises add exposure; trivial secondary work does not reset full recovery; overlapping sessions and missing feedback remain explicit.
- A new day/foreground refresh updates readiness and decayed load without a workout edit; backdated edits invalidate relevant derived results.
- Later workouts cannot change an earlier causal baseline; missing RPE does not masquerade as RPE 10 or zero; default bodyweight is identified.
- Duplicate display names do not lose cluster counts; frequencies share a denominator; input reordering is deterministic.
- 05:00/06:00/11:00/22:00 boundaries, timezone changes, score-point copy, sparse time buckets and confounded workout types.
- Volume-response lowest-bin winner, higher bins without decline, overlapping observation windows, incomplete W+3, true zero-dose weeks and insufficient independent evidence.
- Highlights/tools/verdict agree on windows and actions, including active deload, mixed exercise directions and insufficient data.
- Session overall and Analytics aggregate reconcile with their four visible components and shared inclusion policy; EWMA 70 plus session 80 yields 73 at lambda 0.3. The completion sheet, detail and widget use the correct session/aggregate value and common score bands.
- Rest Rhythm handles exercise transitions, varying intended rest, pauses, supersets and missing intervals without labeling unavailable data as measured quality. Post-workout quality comparison excludes the new workout from its comparison baseline.
- Widgets retain useful highlights after the Advanced card is removed; no deload/volume-drop contradiction, provisional-quality praise, duplicate topic or zero-denominator percentage. Analytics expiry survives active-workout-only writes; an old snapshot is not made fresh by a new timeline-entry date.
- Small/medium/large widget selection, long exercise names, truncation, topic deep links and old payload decoding remain usable. Current watch logging, synchronization and rest-timer widgets remain unaffected; no watch analytics extension is implied.
- iPhone small/large widths, Dynamic Type, VoiceOver, dark/light appearance, Reduce Motion, push/pop and floating tab-bar clearance.

Begin with synthetic fixtures and historical replay where user data is available locally. The screenshots are acceptance examples for contradictions and presentation, not fixtures from which to reconstruct training records.

Revision scope: this document supersedes the initial proposal to replace quality with plan execution and the underspecified treatment of highlights. The earlier layout study remains an illustrative arrangement, not a scoring or widget specification. Implementation is tracked in [analytics-makeover-implementation.md](analytics-makeover-implementation.md). The preview remains an illustrative arrangement; the revised quality and widget requirements above take precedence.
