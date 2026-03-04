# HellBentIron — App Store Release Guide

Step-by-step guide for releasing HellBentIron to the App Store, covering subscriptions, HealthKit, Watch app, and common pitfalls.

---

## Phase 1: Legal & Financial Prerequisites

These must be done first — everything else depends on them.

### 1.1 Agreements, Tax & Banking

In [App Store Connect > Agreements, Tax & Banking](https://appstoreconnect.apple.com/agreements/):

- [ ] **Sign the Paid Applications Schedule (Schedule 2)** — required for subscriptions. Only the Team Agent (Legal role) can sign this.
- [ ] **Add banking information** — IBAN/SWIFT for your Swedish bank account. Apple won't process subscription revenue without this.
- [ ] **Complete tax forms** — US W-8BEN form (required for all non-US developers selling on US App Store).

Without these, subscriptions cannot go live even if the app is approved.

### 1.2 Privacy Policy & Terms of Service

Both URLs are hardcoded in the app (`ProUpgradeView.swift`). They **must be live** before submission — Apple reviewers will tap them.

- [ ] **<https://hellbentiron.com/privacy>** — must include:
  - What data is collected (workout logs, health data via HealthKit)
  - Explicit statement: HealthKit data is **not** used for advertising, **not** sold or shared with data brokers
  - How users can request data deletion
  - Contact information
- [ ] **<https://hellbentiron.com/terms>** — must include:
  - Subscription pricing ($4.99/month, $39.99/year)
  - Auto-renewal terms: renews unless cancelled at least 24 hours before period ends
  - Payment charged to user's Apple ID account
  - How to manage/cancel: Settings > Apple ID > Subscriptions

---

## Phase 2: Apple Developer Portal Setup

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/):

### 2.1 Register App IDs

Register these three App IDs (if not already done) with the listed capabilities:

| App ID                                         | Capabilities                           |
| ---------------------------------------------- | -------------------------------------- |
| `se.gunnarstrandberg.hellbent.ios`             | HealthKit, App Groups, In-App Purchase |
| `se.gunnarstrandberg.hellbent.ios.watchkitapp` | HealthKit, App Groups                  |
| `se.gunnarstrandberg.hellbent.ios.widgets`     | App Groups                             |

- [ ] Register App Group: `group.se.gunnarstrandberg.hellbent.shared`

### 2.2 Distribution Certificate

- [ ] Create an **Apple Distribution** certificate (unified — covers iOS + watchOS + extensions)
- [ ] Download and install in Keychain Access

### 2.3 Provisioning Profiles

If using **Automatic Signing** in Xcode (recommended): skip this — Xcode handles it.

If using manual signing, create **App Store** distribution profiles for all three bundle IDs.

---

## Phase 3: App Store Connect — App Record

### 3.1 Create the App

In [App Store Connect > My Apps](https://appstoreconnect.apple.com/apps), click **+**:

| Field            | Value                              |
| ---------------- | ---------------------------------- |
| Platform         | iOS                                |
| Name             | HellBentIron                       |
| Primary Language | English                            |
| Bundle ID        | `se.gunnarstrandberg.hellbent.ios` |
| SKU              | `hellbentiron-001`                 |

### 3.2 App Information

| Field              | Value                              |
| ------------------ | ---------------------------------- |
| Primary Category   | Health & Fitness                   |
| Secondary Category | Sports (optional)                  |
| Privacy Policy URL | `https://hellbentiron.com/privacy` |
| Age Rating         | Complete questionnaire (likely 4+) |

### 3.3 Version Metadata (v1.0)

- [ ] **Description** (up to 4000 chars) — describe what the app does, what Pro unlocks. Do **not** mention pricing in the description.
- [ ] **Keywords** (up to 100 chars) — e.g. `strength training,workout tracker,weightlifting,gym log,progressive overload,barbell`
- [ ] **Support URL** — e.g. `https://hellbentiron.com/support`
- [ ] **What's New** — leave blank or write intro for v1.0

### 3.4 Screenshots

**Required:**

| Device                          | Requirement                                                          |
| ------------------------------- | -------------------------------------------------------------------- |
| 6.7" iPhone (iPhone 16 Pro Max) | Required — covers all iPhone sizes                                   |
| 12.9" iPad Pro                  | Required (your app targets iPad via `TARGETED_DEVICE_FAMILY: "1,2"`) |

**Optional but recommended:**

- Apple Watch screenshots (41mm and 45mm)

Specs: PNG or JPEG at native resolution. 1-10 per device size. App preview videos optional.

### 3.5 App Privacy Details (Nutrition Labels)

In your app record under **App Privacy**, declare:

| Data Type        | Category      | Purpose           | Linked to Identity? |
| ---------------- | ------------- | ----------------- | ------------------- |
| Health & Fitness | Workout data  | App Functionality | No (on-device only) |
| Health & Fitness | Exercise data | App Functionality | No                  |

If you use **no** analytics SDKs, crash reporters, or tracking: declare "Data Not Collected" for all other categories.

---

## Phase 4: Subscription Setup in App Store Connect

The `.storekit` file is for local Xcode testing only. You must recreate products in App Store Connect for real transactions.

### 4.1 Create Subscription Group

In your app record > **In-App Purchases** > **+** > Auto-Renewable Subscription:

- [ ] **Reference Name**: `HellBentIron Pro`

### 4.2 Create Products

Within the group, create two subscriptions:

**Monthly:**

| Field              | Value                                            |
| ------------------ | ------------------------------------------------ |
| Reference Name     | Pro Monthly                                      |
| Product ID         | `hellbent.pro.monthly` (must match code exactly) |
| Duration           | 1 Month                                          |
| Price              | Tier 5 ($4.99)                                   |
| Subscription Level | 1                                                |
| Display Name       | HellBentIron Pro Monthly                         |
| Description        | Unlock all Pro features monthly                  |

**Yearly:**

| Field              | Value                                           |
| ------------------ | ----------------------------------------------- |
| Reference Name     | Pro Yearly                                      |
| Product ID         | `hellbent.pro.yearly` (must match code exactly) |
| Duration           | 1 Year                                          |
| Price              | ~Tier 40 ($39.99)                               |
| Subscription Level | 1                                               |
| Display Name       | HellBentIron Pro Yearly                         |
| Description        | Unlock all Pro features — save 33%              |

### 4.3 Subscription Review Screenshot

- [ ] For each product, under **Review Information**, upload a screenshot of the in-app paywall (`ProUpgradeView`). This is separate from App Store screenshots.

### 4.4 Submit Subscriptions with v1.0

Both products must be submitted **together** with the first app version. You cannot submit them independently for v1.0.

---

## Phase 5: Codebase Preparation

### 5.1 Privacy Manifest

`iOS/Resources/PrivacyInfo.xcprivacy` is in place, declaring:

- [x] No tracking (`NSPrivacyTracking: false`)
- [x] Health data + fitness data + purchase history collected for app functionality, not linked to identity
- [x] `UserDefaults` API usage declared with reason `CA92.1`

### 5.2 GitHub Link in Settings

Removed — the bare `https://github.com` link was replaced by Privacy Policy and Terms of Service links in a new "Legal" section.

### 5.3 Widget Version Mismatch

Fixed — `project.yml` now sets `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` on the widget target, and the widget Info.plist uses `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` so versions stay in sync automatically.

### 5.4 Version & Build Number

Before each submission, increment the build number:

| Field                     | Where                     | Current |
| ------------------------- | ------------------------- | ------- |
| `MARKETING_VERSION`       | project.yml (all targets) | 1.0.0   |
| `CURRENT_PROJECT_VERSION` | project.yml (all targets) | 1       |

The marketing version stays `1.0.0` for launch. Increment build number (`2`, `3`, ...) for each upload.

### 5.5 Verify No Hardcoded Prices

The app correctly uses `Product.displayPrice` from StoreKit 2 in `ProUpgradeView`. Never hardcode `"$4.99"` — Apple reviewers are in the US but global users see localized pricing.

---

## Phase 6: Pre-Submission Checklist (In-App Requirements)

Apple reviewers will check all of these. Missing any one causes rejection.

### 6.1 Paywall Screen (`ProUpgradeView`)

- [x] Subscription name shown
- [x] Price shown via `Product.displayPrice`
- [x] Duration shown via subscription period
- [x] Feature list of what Pro unlocks
- [x] Restore Purchases button
- [x] Privacy Policy link
- [x] Terms of Service link
- [x] Auto-renewal disclosure text (below product cards, above legal links)

### 6.2 Settings Screen

- [x] Subscription status shown
- [x] Restore Purchases button
- [x] Manage Subscription button (calls `AppStore.showManageSubscriptions`)
- [x] Privacy Policy link (in "Legal" section)
- [x] Terms of Service link (in "Legal" section)

### 6.3 HealthKit

- [x] `NSHealthShareUsageDescription` set (iOS + Watch)
- [x] `NSHealthUpdateUsageDescription` set (iOS + Watch)
- [x] Entitlements include `com.apple.developer.healthkit`
- [x] Watch has `WKBackgroundModes: workout-processing`
- [x] `WKCompanionAppBundleIdentifier` matches iOS bundle ID

---

## Phase 7: Archive & Upload

### 7.1 Regenerate Project

```bash
cd StrengthTracker && xcodegen generate
```

### 7.2 Archive (Xcode UI)

1. Select scheme **StrengthTracker**
2. Set destination to **Any iOS Device (arm64)**
3. **Product > Archive**
4. Wait for archive to complete — Organizer opens automatically

The Watch app and Widget extension are embedded automatically. No separate archive needed.

### 7.3 Upload

1. In Organizer, select the archive
2. Click **Distribute App**
3. Select **App Store Connect**
4. Select **Upload**
5. Choose **Automatically manage signing** (or select manual profiles)
6. Review summary — verify all three targets are listed (iOS + Watch + Widget)
7. Click **Upload**

### 7.4 Alternative: Command Line

```bash
cd StrengthTracker
xcodegen generate

xcodebuild -project StrengthTracker.xcodeproj \
  -scheme StrengthTracker \
  -destination "generic/platform=iOS" \
  -archivePath build/HellBentIron.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath build/HellBentIron.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

You'd need an `ExportOptions.plist` with `method: app-store-connect`.

---

## Phase 8: Submit for Review

### 8.1 Select Build

In App Store Connect, under your v1.0 version, click **+** next to Build and select the uploaded build. It may take 5-15 minutes to process after upload.

### 8.2 App Review Notes

Write in the "Notes for Review" field:

> HellBentIron is a strength training tracker. The app uses HealthKit to read and write HKWorkout data for completed strength training sessions (exercise name, sets, reps, weight). Heart rate data is read from Apple Watch during live workout sessions.
>
> HealthKit data is used only for workout tracking within the app. It is not shared with third parties and is not used for advertising.
>
> The app includes auto-renewable subscriptions (Pro Monthly at $4.99/month, Pro Yearly at $39.99/year). The Restore Purchases button is on the subscription screen and in Settings > Subscription.
>
> No login is required. The Watch app pairs automatically via WatchConnectivity.

### 8.3 Sandbox Test Account

- [ ] Provide a sandbox Apple ID in the review notes so the reviewer can test purchases without real payment.

### 8.4 Release Type

Choose **Manually release this version** — lets you control exactly when it goes live after approval.

### 8.5 Submit

- [ ] Ensure both subscription products show status "Ready to Submit"
- [ ] Click **Submit for Review**

---

## Phase 9: After Submission

### Review Timeline

| Scenario                | Typical Wait                                                 |
| ----------------------- | ------------------------------------------------------------ |
| First submission (v1.0) | 24-72 hours (up to 1 week for HealthKit + subscription apps) |
| After rejection fix     | ~24 hours                                                    |

### If Rejected

Common rejection reasons for this type of app:

| Guideline | Issue                                                | Status / Fix                                   |
| --------- | ---------------------------------------------------- | ---------------------------------------------- |
| 3.1.2     | Missing auto-renewal disclosure on paywall           | Done — disclosure text added                   |
| 3.1.2     | Can't find Restore Purchases                         | Done — on paywall + Settings                   |
| 5.1.3     | HealthKit data used for non-health purpose           | Ensure no analytics SDK touches HealthKit data |
| 5.1.3     | Privacy policy doesn't mention HealthKit             | Update privacy policy                          |
| 2.1       | App crashes on fresh install                         | Test clean install on device                   |
| 5.1.1     | Privacy nutrition labels don't match actual behavior | Re-check App Privacy declarations              |

### After Approval

- Click **Release This Version** when ready
- App appears on App Store within a few hours, all storefronts within 24 hours
- TestFlight continues to work independently
- Future updates go through the same review process

### Phased Release (Updates Only)

Not available for v1.0, but for v1.1+: enable phased rollout (1% → 2% → 5% → 10% → 20% → 50% → 100% over 7 days). Can be paused for up to 30 days if you find a critical bug.

---

## Quick Reference Checklist

### Before Building

- [ ] Agreements, Tax & Banking completed in App Store Connect
- [ ] Privacy policy live at hellbentiron.com/privacy
- [ ] Terms of service live at hellbentiron.com/terms
- [x] PrivacyInfo.xcprivacy created
- [x] Widget version mismatch fixed
- [x] Auto-renewal disclosure added to ProUpgradeView
- [x] Privacy/Terms links added to SettingsView

### In Apple Developer Portal

- [ ] App IDs registered with correct capabilities
- [ ] App Group registered
- [ ] Distribution certificate created (or use Automatic Signing)

### In App Store Connect

- [ ] App record created
- [ ] Description, keywords, support URL, privacy URL filled in
- [ ] Screenshots uploaded (6.7" iPhone + 12.9" iPad minimum)
- [ ] Subscription group created
- [ ] `hellbent.pro.monthly` product created with correct Product ID
- [ ] `hellbent.pro.yearly` product created with correct Product ID
- [ ] Paywall screenshots uploaded for each subscription product
- [ ] App Privacy details completed

### Submit

- [ ] Archive and upload via Xcode
- [ ] Select build in App Store Connect
- [ ] Submit subscriptions together with v1.0
- [ ] App Review notes written (HealthKit usage, subscription details)
- [ ] Sandbox test account provided
- [ ] Release type set to "Manual"
- [ ] Click Submit for Review
