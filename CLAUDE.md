# CLAUDE.md

iOS strength training tracker (SwiftUI, SwiftData) with Watch and Widget extensions.

## Build

Build from the `StrengthTracker/` subdirectory, not the repo root:

```bash
cd StrengthTracker && xcodebuild -project StrengthTracker.xcodeproj \
  -target "StrengthTracker" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -configuration Debug clean build
```

- `swift build` does not work on macOS (ActivityKit is iOS-only). Always use `xcodebuild`.
- Use `clean build` to avoid stale module cache issues.
- Targets: `StrengthTracker`, `StrengthTrackerWatch`, `StrengthTrackerWidgets`. The `StrengthTracker` scheme builds all of them.

## Project structure

- SPM-based: `Package.swift` defines `StrengthTrackerShared`, `StrengthTrackeriOS`, `StrengthTrackerWatch`.
- The `.xcodeproj` is generated from `project.yml` by XcodeGen. After adding or removing `.swift` files (including under `Tests/`), run `xcodegen generate` from `StrengthTracker/`.

## Architecture

- MVVM + Repository + Mapper pattern.
- SwiftData for persistence, `@Observable` for ViewModels.
- `AppContainer` (DI) creates repositories, services, and cached ViewModels. ViewModels shared across views must be cached there as singletons.
- Weights are always stored in kg; convert at the UI boundary via the `WeightUnit` API.
- App Group ID: `group.se.gunnarstrandberg.hellbent.shared`.

## Gotchas

- SwiftData: update entities in place (match by ID); never delete-and-recreate with the same UUID — `@Attribute(.unique)` conflicts silently.
- SwiftData: `array.removeAll()` only clears the relationship; use `modelContext.delete()` to actually delete, and `modelContext.insert()` for new unattached entities. Set the parent reference when creating child entities in mappers.
- Tests: use in-memory mocks; `#Predicate` on a second `ModelContainer` crashes hosted tests.
