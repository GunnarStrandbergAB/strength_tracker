# ExerciseDB pilot and integration plan

Status: planned; provider selected, implementation not started. Updated 3 November 2026.

Add optional exercise demonstrations using the downloadable ExerciseDB.io dataset. Start with its free sample, validate a small licensed pilot, then expand to reviewed matches across the app's existing exercise library. Keep the current exercise identities, instructions, workout logging and analytics authoritative.

## Decisions and boundaries

- Use **ExerciseDB.io downloadable data and GIFs**, not a similarly named API or third-party repository. No ExerciseDB API key or per-request subscription is required.
- Target **Starter first**. Its advertised price is $199 for 1,394 exercise entries and 180/360px GIFs. Pro is $599 and adds higher resolutions and richer metadata. Compare the sample's 360px and 720px versions before choosing; do not assume an upgrade discount. Future dataset updates are not included. [Pricing](https://exercisedb.io/pricing)
- Native GIF playback is the initial implementation. GIF-to-MP4 conversion, background removal and other asset transformations are not assumed to be licensed; clarify those rights separately if needed.
- Display demonstrations with their associated exercise information. Preserve the purchased EULA and version record; do not publish the purchased archive or offer a raw dataset export. [Terms](https://exercisedb.io/terms)
- Start on iPhone. Watch and widgets receive no media, new navigation or asset downloads in this release.
- Do not generate or alter the Xcode project, schemes, signing, entitlements, package references or resource build phases. Do not add a dependency to obtain GIF playback.
- This plan does not authorize a purchase, vendor contact, hosting deployment or application implementation. Those actions follow implementation approval and any specific purchase/deployment authorization needed at that time.

ExerciseDB permits hosting or bundling purchased files and describes the licence as perpetual. The sample demonstrates package structure and media sizes; it is not the complete library. The purchased ZIP contains its EULA. Keep the free-sample pilot internal until sample distribution rights are established, and use licensed assets for external TestFlight testing. [FAQ](https://exercisedb.io/faq)

## Existing code and integration points

| Area | Current location and planned treatment |
| --- | --- |
| Exercise identity | `StrengthTracker/Shared/Models/Domain/Exercise.swift` has stable UUIDs and no media reference. Resolve demonstrations separately by UUID; avoid a SwiftData migration or changes to workout snapshots. |
| Built-in catalogue | `StrengthTracker/Shared/Services/ExerciseSeedData.swift` contains 344 exercises, with identities derived from seed names. Match against the existing IDs; never rename seeds to match provider names. |
| Seeding | `StrengthTracker/Shared/Services/ExerciseSeeder.swift` refreshes non-custom exercise records. Keep personal demonstration choices in a separate store so seeding cannot overwrite them. |
| Exercise details | `StrengthTracker/iOS/Features/ExerciseLibrary/Views/ExerciseDetailView.swift` already shows instructions and logging conventions. Add a demonstration preview and a route to the reusable viewer. |
| Workout entry | `StrengthTracker/iOS/Features/Workout/Views/ExerciseCardView.swift` provides the exercise header and menu. Add an explicit, accessible Demo action for available matches. |
| Workout presentation | `StrengthTracker/iOS/Features/Workout/Views/ActiveWorkoutView.swift` owns the workout flow. Own the demonstration sheet here and commit active numeric input before presentation. |
| Source inclusion | `StrengthTracker/Package.swift` discovers shared sources by directory, while the checked-in Xcode project explicitly lists iOS/test files. Add shared types under the existing shared target; place iOS helpers and tests in appropriate existing compiled files. Leave both project and package configuration unchanged. |

## Phase 1 — Internal sample pilot

Prove that the visuals and playback are suitable before purchasing or mapping the whole library.

1. Inspect the current sample archive and document its contents and permitted evaluation use. The previously inspected sample supplied bench-press media at several resolutions; do not assume it contains 15 complete exercise demos.
2. Build a development-only preview of that exercise using temporary/local sample files, outside tracked app resources. Do not copy paid/sample archives into Git or change resource build phases.
3. Compare 180px, 360px and 720px at the actual intended presentation sizes on an iPhone. Preserve the original aspect ratio and full equipment/body framing. Use a rounded neutral media surface within the dark screen; avoid cropping away feet, hands or equipment to hide the white background.
4. Prototype a native ImageIO/UIKit GIF renderer with explicit Play/Pause, preserved frame timings and a bounded frame buffer. Decode away from the main thread. Stop decoding/animation when dismissed, offscreen or backgrounded; respect Reduce Motion with an initially static view.
5. Record sample file sizes, first-frame latency, playback memory, visual clarity and the resolution decision. Compare opening/closing the viewer with a baseline build on the same device.

**Exit criteria:** 360px is accepted for the intended size, or Pro is justified by a visible improvement; looping and text are clear; dismissing/backgrounding releases playback work; repeated presentation shows no retained-player growth or noticeable scrolling/input regression. If the source motion itself is unsuitable, stop expansion and resolve that limitation rather than buying higher resolution as an assumed fix.

Deliverable: a short pilot report with device/OS, captures, measurements and the selected package/resolution. No external beta distribution yet.

## Phase 2 — Licensed pilot of approximately 15 exercises

After the sample passes and the selected package is acquired, ingest its actual data and add a narrowly scoped user-facing pilot.

### Mapping and content review

Choose representative existing exercises, including bench press, dumbbell press, Bulgarian split squat, one-arm dumbbell row, a kneeling single-arm cable row/custom variant, hip thrust, squat, Romanian deadlift, push-up, chin-up, ring pull-up, ring row, cable triceps work, a leg machine and a static hold.

- Review the actual demonstration for equipment, grip, support, body position, range of motion and unilateral/bilateral execution. A similar name alone is insufficient.
- Classify candidates as **exact**, **reviewed equivalent**, **unmatched** or **rejected**. Record why an equivalent is acceptable; do not disguise a materially different variation as the same exercise.
- Resolve by the app's exercise UUID, never by fuzzy matching during a workout. Automated name/alias matching can suggest candidates only during content preparation.
- Include at least one deliberately unmatched exercise and one custom machine variant in the pilot. These must have a useful instructions-only state.
- Demonstrations do not determine whether weight is entered per dumbbell, combined, per side, or as added bodyweight. Display the app's existing logging explanation where relevant, including workout-specific conventions when opened from a workout.

### User experience

| Location | Behaviour |
| --- | --- |
| Exercise detail | A static preview and labelled Play demo action next to the instructions. Playback starts only after an explicit tap. |
| Active workout | A compact Demo button with at least a 44-point hit target, separate from the drag handle and set controls. Route it through the workout owner, not a sheet on every row. |
| Reusable viewer | Opaque dark background, exercise name, contained animation, Play/Pause, instructions, relevant logging explanation and visible Close control. Keep text scrollable at large Dynamic Type sizes. |
| Loading or failure | Fixed-size placeholder; existing instructions remain readable. Offer retry after a failed request. Closing never waits for a download. |
| No mapping | Preserve instructions. In details, show a quiet “No demonstration linked” state and later the selection action. Do not show a broken play button in workout cards. |

Before opening from a workout, call the established `STNumericTextField.commitActiveInput()` path and honour failure. Preserve pending saves, workout scroll position, set completion state and the rest timer. Coordinate with other sheets so the demonstration cannot stack behind an editor or leave a blocking overlay.

**Exit criteria:** every pilot mapping is visually reviewed; exercises remain correctly identified; loading/offline/failure states work; logging and timers survive repeated open/close cycles; a physical iPhone passes the keyboard, background/resume and overlay checks.

## Phase 3 — Delivery and offline cache

Use app-controlled HTTPS asset hosting and lazy local caching as the default production delivery design. This keeps the app binary small and avoids adding asset resources to the Xcode project. It removes the ExerciseDB runtime dependency, but it does introduce hosting ownership and operating costs that must be settled before release.

1. Store the acquired archive privately. Publish only the media needed for approved app mappings, through an app-controlled delivery domain. Disable directory listings and archive/catalogue download endpoints; keep origin credentials outside the app.
2. Keep a versioned mapping and essential exercise text in the compiled shared source. Each media reference carries provider ID, catalogue version, resolution, expected byte size and SHA-256 checksum. Preserve provider IDs as strings, including leading zeros.
3. Fetch an asset only when the user requests its demo. Do not download media during startup, scrolling, analytics calculation or background seeding. Deduplicate concurrent requests for the same asset.
4. Use an actor-isolated loader/cache. Validate HTTPS origin, redirects, response status, MIME/signature, byte limits, dimensions/frame limits and checksum before atomically installing a download. A malformed file must never replace a valid cached copy.
5. Key cached files by provider ID, dataset version and resolution. Start with a configurable **100 MiB disk-cache budget**, evict least-recently-used files, and provide Clear downloaded demos in Settings. Treat this as a product budget to tune from pilot measurements.
6. Offline, play cached media. If it has never been downloaded or was evicted, show the instructions and a clear connection-needed message. Do not promise that every exercise is available offline. Bulk offline packs are deferred.
7. Cancel presentation-specific work on dismissal and reject stale results after exercise changes. Respond to memory pressure by releasing decoded frames. Bound retry/timeout behaviour so media never holds up the workout UI.

**Exit criteria:** offline cached playback, first-use offline fallback, cache eviction, corrupted responses, cancellation and slow-network tests pass. A hosting owner, expected bandwidth/cost and recovery procedure are recorded. No permanent credentials or raw provider archive enter the repository or app binary.

## Phase 4 — Full library coverage and personal choices

Review all 344 built-in exercises against the acquired catalogue. Full integration means every exercise has a reviewed outcome, not a claim that every exercise has a correct GIF.

- Produce a coverage report listing app UUID/name, provider ID/name, match status, reviewer decision and unresolved differences. Keep unmatched exercises explicit; prioritise common movements and the specialised ring/cable/unilateral cases already raised by users.
- Reject duplicate mappings for an app UUID, missing provider records and mismatched media IDs. Allow several app variants to use one demo only when explicitly reviewed as appropriate, with differences explained where necessary.
- Ship a compact catalogue of licensed metadata for the in-app demo selector, with thumbnails fetched only on demand. Do not import all provider exercises into the user's training library or duplicate existing exercises.
- Add Choose/Change demonstration, Remove demonstration and Reset to library default in exercise details. Let users search by name/equipment and preview before choosing. Do not accept arbitrary web URLs in the first release.
- Persist overrides separately as a versioned store keyed by exercise UUID. Distinguish “use library default”, “use this provider ID” and “show no demo”; absence and explicit removal must not mean the same thing. Use atomic writes and keep the last valid state on read/write failure.
- Custom exercises start without a demo. Duplicating an exercise as a variant offers an explicit choice to retain its demo; never infer compatibility solely from a copied name. Renaming an exercise preserves its selection because its UUID is unchanged.
- Resolve precedence as explicit disable/selection first, reviewed library mapping second, instructions-only fallback last. Invalid or withdrawn provider references fall back safely rather than selecting a different exercise automatically.
- Keep the mapping store independent of seeding and workout history. Document persistence as local to the installation; do not promise iCloud or cross-device sync. If the app offers an exercise export/import path, include optional versioned selections without media bytes and preserve compatibility with older backups.

**Exit criteria:** all built-ins are reviewed, accepted matches pass content checks, unmatched cases are documented, and custom selections survive relaunch/seeding without modifying exercise metrics or history.

## Phase 5 — Grok and remaining entry points

Reuse the same resolver and viewer wherever an exercise is already identifiable. Existing exercise-detail routes from history, templates and plans should gain the feature through that shared screen rather than acquire independent players or navigation stacks.

For Grok, extend the existing exercise lookup tool response with the app exercise ID, reviewed instructions, demo availability and match qualification. Render a tappable View demonstration action associated with that ID. Resolve the media inside the app; do not send GIF bytes, storage credentials or bulk provider data into chat. Read-only lookup must not open a sheet automatically or navigate away while the assistant is responding.

ExerciseDB markets its structured information as retrieval context for AI products. Use only the selected package's fields and review its EULA before enabling provider-text retrieval. Do not introduce Pro substitution/progression logic or replace existing training-plan tools as part of this feature. [AI dataset use](https://exercisedb.io/ai-fitness-app-dataset)

**Exit criteria:** supported exercise requests lead to the correct viewer on user tap; unknown/unmatched IDs give an honest unavailable response; Grok cannot invent a media URL or change a mapping through a read tool. Chat scrolling, input visibility and return navigation remain intact.

## Verification and release

Use deterministic test fixtures, temporary cache directories and a stubbed network transport. Automated tests must not depend on live ExerciseDB or production hosting. Use synthetic tiny GIF fixtures for decoder edge cases and licensed samples only for the appropriate internal visual checks.

| Test area | Required coverage |
| --- | --- |
| Mapping | UUID stability; leading-zero provider IDs; exact/equivalent/unmatched states; missing media; duplicate app entries; wrong equipment/side candidates rejected during review. |
| Overrides | Default/selected/disabled precedence; rename; variant copy choice; seed refresh; relaunch; invalid references; interrupted/corrupt storage; old backup compatibility if applicable. |
| Loader | Success, 404, timeout, offline, wrong MIME, checksum failure, oversized content, redirect outside allowed origin, concurrent requests, cancellation and late responses. |
| Cache | Atomic writes, cache hits without network, eviction, version changes, clearing, low disk space and corrupted cached files. |
| Playback | Frame timing, pause/resume, Reduce Motion, dismissal/background stop, bounded decoding, malformed GIF and repeated presentation without retained players. |
| Workout regressions | Edited Kg/Reps/RPE survive opening/closing; invalid input blocks presentation; rest timer remains correct; no accidental completion/reordering; Finish and other sheets still work. |
| Data regressions | Exercise IDs/count and user instructions unchanged; dumbbell, bodyweight and iso-lateral volume/try-weight results unchanged; templates, plans, PRs and history unaffected. |
| Grok | Existing lookup responses remain compatible; correct ID-based action; no invented links; unknown IDs; unavailable/offline media; chat keyboard and scroll behaviour. |
| Accessibility and UI | Small phone width, large text, VoiceOver labels/focus, 44-point targets, white GIF surface within dark theme, visible Close and opaque sheets. |

For each implementation increment, run the relevant tests. Before the pilot beta and broad release, build the existing iOS simulator scheme and run the existing test suite with coverage. Record the actual destination, commands, pass/fail counts and result bundle; do not inherit old test counts from another branch. No project regeneration, dependency refresh or signing changes are needed for this work.

Capture checksums/diffs of `project.pbxproj`, shared schemes, `project.yml`, `Package.swift`, package resolution files, entitlements and Info.plist before and after verification. Any unintended setup change fails the release check. Verify iPhone, Watch and widget targets still build through the existing scheme.

Physical-device checks must include repeated demo presentation during a real active workout, an active rest timer, input editing, rapid dismissal, background/resume, a cold launch and a launch from the widget. Confirm no black persistent overlay, unexpected dashboard/history navigation or keyboard obstruction returns.

Release in two steps: a small TestFlight pilot with the reviewed set, then a broader build with the completed coverage report and personal selections. Enable entry points behind a shared feature flag; disabling it must restore the existing instructions-only experience without migrating user training data. A bad individual mapping can also be withdrawn without disabling the entire feature. Use the existing crash-reporting setup and beta feedback; do not add a telemetry service solely for this rollout.

## Delivery sequence

| Increment | Deliverable | Decision before continuing |
| --- | --- | --- |
| 1 | Sample playback prototype and pilot report | Accept rendering quality and choose Starter or Pro. |
| 2 | Licensed 15-exercise pilot, shared viewer and mapping resolver | Accept form matches and active-workout UX. |
| 3 | Production delivery, cache and failure handling | Confirm hosting and pass offline/performance checks. |
| 4 | Review of all built-ins, custom selection and persistence | Accept coverage report and data compatibility. |
| 5 | Grok action and shared detail routes | Pass chat/navigation regression checks. |
| 6 | TestFlight expansion and final validation record | Release only with unchanged project setup and passing tests/build. |

Deferred: importing the full provider catalogue as new training exercises, altering analytics or recommendations, Watch playback, autoplay in lists, bulk offline downloads and media conversion without confirmed rights.
