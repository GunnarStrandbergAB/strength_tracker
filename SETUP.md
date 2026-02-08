# StrengthTracker - MacBook Setup Guide

Step-by-step instructions to build and run the app on a MacBook with Apple Silicon (M1/M2/M3).

## Prerequisites

- macOS 14 (Sonoma) or later
- Apple Developer account (free works for simulator, paid for device + HealthKit)

## Step 1: Install Xcode

Download from the Mac App Store: [Xcode](https://apps.apple.com/app/xcode/id497799835)

You need **Xcode 15.3 or later** (for Swift 6.0 support). The download is ~7 GB and installation takes a while.

After installing, open Xcode once to accept the license and install components:

```bash
sudo xcodebuild -license accept
xcode-select --install
```

Verify it works:

```bash
swift --version
# Should show: Swift version 6.0 or later
```

## Step 2: Install Homebrew (if not installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Step 3: Install XcodeGen

```bash
brew install xcodegen
```

Verify it installed:

```bash
xcodegen --version
```

## Step 4: Clone the repository

```bash
git clone https://github.com/GunnarStrandbergAB/strength_tracker.git
cd strength_tracker
```

## Step 5: Generate the Xcode project

```bash
cd StrengthTracker
xcodegen generate
```

You should see:

```
Generated StrengthTracker.xcodeproj
```

## Step 6: Open in Xcode

```bash
open StrengthTracker.xcodeproj
```

## Step 7: Configure signing

1. In Xcode, select the **StrengthTracker** project in the navigator (blue icon, top left)
2. For each target, set your team:
   - **StrengthTracker** (iOS app) -> Signing & Capabilities -> Team -> select your account
   - **StrengthTrackerWatch** (watchOS app) -> same
   - **StrengthTrackerWidgets** (widget extension) -> same
   - **StrengthTrackerTests** -> same
3. Xcode will auto-create provisioning profiles

If you don't have a paid developer account, HealthKit entitlements won't work on device. You can still run on simulator (HealthKit has limited simulator support).

## Step 8: Select scheme and destination

1. In the toolbar, select scheme: **StrengthTracker**
2. Select destination: **iPhone 15 Pro** (or any iOS 17+ simulator)

## Step 9: Build and run

Press **Cmd + R** or click the play button.

The first build will take a minute or two as it resolves the Swift Package and compiles everything.

## Running on Apple Watch Simulator

1. In Xcode, select destination: **Apple Watch Series 9 (45mm)** paired with your iPhone simulator
2. Or: Run the iOS app first, then separately build the Watch target
3. The Watch app appears in the Watch simulator automatically when paired

## Troubleshooting

### "No such module 'StrengthTrackerShared'"

The Swift Package hasn't resolved yet. Try:

```bash
cd StrengthTracker
xcodegen generate
```

Then in Xcode: File -> Packages -> Resolve Package Versions

### Build errors in HealthKit/WatchConnectivity code

These frameworks require Apple platforms. All platform-specific code is wrapped in `#if canImport(...)` guards, so this shouldn't happen. If it does, clean the build:

- Xcode: Product -> Clean Build Folder (Cmd + Shift + K)
- Then rebuild (Cmd + B)

### Signing errors

If you see "Signing for X requires a development team":

1. Select the failing target
2. Signing & Capabilities -> Team -> pick your Apple ID
3. If using free account, you may need to change the bundle ID to something unique (e.g., `com.yourname.strengthtracker`)

### Widget not showing

1. Build and run the main iOS app first
2. On the simulator, long-press the home screen -> tap "+" to add widgets
3. Search for "StrengthTracker"

### HealthKit authorization not appearing

HealthKit has limited simulator support. For full testing, deploy to a physical iPhone and Apple Watch.

## Project Structure

```
StrengthTracker/
  Shared/              # Domain models, ViewModels, services, repositories (all platforms)
  iOS/                 # iPhone app (SwiftUI views, design system)
    App/               # Entry point, ContentView, tab navigation
    Features/          # Feature modules (Dashboard, Workout, Exercises, etc.)
    WidgetExtension/   # Home screen & lock screen widgets
    Resources/         # Info.plist, entitlements
  WatchApp/            # Apple Watch app
    App/               # Watch entry point
    Features/          # Watch-specific views
    Services/          # WatchHealthKitManager
    Resources/         # Watch Info.plist, assets, entitlements
  Tests/               # Unit tests (153 tests)
  Package.swift        # Swift Package Manager manifest
  project.yml          # XcodeGen project definition
```

## Key Commands

| Action | Command |
|--------|---------|
| Generate Xcode project | `xcodegen generate` |
| Build | Cmd + B |
| Run | Cmd + R |
| Test | Cmd + U |
| Clean | Cmd + Shift + K |
| Run on device | Select your device in destination, then Cmd + R |

## After First Successful Build

The app will launch with a seeded exercise library (65 exercises). You can:

1. Go to the **Workout** tab and tap "Start Workout"
2. Tap "Add Exercise" to pick from the library
3. Log sets inline (weight + reps), tap the checkbox to complete
4. Rest timer auto-starts after completing a set
5. Tap "Finish" to save the workout
