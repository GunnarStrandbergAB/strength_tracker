# VBT + AI Coaching Module: Technical Design Report

> Research compiled February 2026 for the StrengthTracker (HellBentIron) iOS app.
> Covers on-device barbell velocity tracking via computer vision, Gemini-powered coaching, competitive landscape, and integration architecture.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Market Landscape & Competitive Analysis](#2-market-landscape--competitive-analysis)
3. [VBT Science & Algorithms](#3-vbt-science--algorithms)
4. [On-Device Computer Vision for Barbell Tracking](#4-on-device-computer-vision-for-barbell-tracking)
5. [Gemini AI Coaching Layer](#5-gemini-ai-coaching-layer)
6. [iOS Architecture & Integration](#6-ios-architecture--integration)
7. [Implementation Roadmap](#7-implementation-roadmap)
8. [References](#8-references)

---

## 1. Executive Summary

### What We're Building

A velocity-based training (VBT) module that:
1. **Measures barbell velocity** in real time using the iPhone camera (no external hardware)
2. **Sends post-set video + velocity data** to Google Gemini for AI-powered coaching feedback
3. **Integrates with the existing StrengthTracker** app architecture (MVVM, SwiftData, AppContainer DI)

### Why It's Feasible

| Component | Feasibility | Evidence |
|-----------|-------------|----------|
| Phone-based bar velocity | Proven | Metric VBT achieves r=0.93 vs linear encoders; Qwik VBT matches gold-standard in PLOS ONE 2024 |
| 60fps CV on iPhone | Comfortable | Vision framework tracking: 2-5ms/frame on A16. YOLOv8-nano: ~17ms FP16. Well within 16.7ms budget |
| Gemini video analysis | Mature API | File API accepts MOV directly, 30s clip costs ~$0.003 with 2.5 Flash, 8-23s latency fits rest periods |
| Accuracy for training use | Sufficient | 60fps + subpixel tracking yields ~0.018 m/s precision; VBT needs ~0.04 m/s |

### Why It's Differentiated

No existing app combines all three of:
- Zero-hardware camera-based velocity tracking
- AI video coaching (form analysis, fatigue detection, technique comparison)
- Full training platform (programming, logging, progression — already built in StrengthTracker)

The closest competitor (Metric VBT) has velocity tracking but no AI coaching. Gemini coaching without velocity data would be qualitative-only. The combination is the product.

### Cost Per User

| Scenario | Monthly Cost (Gemini 2.5 Flash) |
|----------|-------------------------------|
| All sets analyzed (320 sets/mo) | ~$1.13 |
| Selective analysis (compounds only) | ~$0.57 |
| Velocity-only (no Gemini) | $0.00 |

---

## 2. Market Landscape & Competitive Analysis

### 2.1 Market Size

The VBT market is estimated at ~$350M USD in 2025, projected to reach $600M+ by 2030 (11-13% CAGR).

### 2.2 Phone-Based VBT Apps

| App | Tracking | Real-Time | Accuracy | Platform | Price |
|-----|----------|-----------|----------|----------|-------|
| **Metric VBT** | Auto plate detection, 60fps | Yes | r=0.93 vs LPT (v4.5+) | iOS only | Free / $65/yr |
| **Qwik VBT** | Manual plate tap, post-processing | No | Best app: RMSE 0.01-0.03 m/s, 0 missed reps | iOS + Android | Free / one-time |
| **MyLift** | Auto plate detection | Partial | Poor: missed 84% of bench reps in PLOS ONE 2024 | iOS + Android | Free/paid |
| **My Jump Lab** | AI pose tracking | Partial | r>0.90 for barbell, primary focus is jumps | iOS | ~$10 one-time |
| **Spleeft** | Camera + Apple Watch hybrid | Yes | Good for camera, limited for Watch | iOS | Low |

**Key finding from PLOS ONE 2024 study**: Three apps tested against Vicon 3D motion capture and RepOne linear encoder. Qwik VBT matched or exceeded RepOne. Metric VBT missed 9% of reps. MyLift missed 30% overall (84% of bench reps).

### 2.3 Hardware Devices

| Device | Type | Accuracy | Price |
|--------|------|----------|-------|
| GymAware RS | Linear position transducer | Gold standard | ~$2,500-3,500+ |
| Vitruve | Linear position transducer | Excellent (CV 2.61%) | $447 |
| RepOne Tether | Linear position transducer + 3D angle | Excellent | ~$399 |
| GymAware FLEX | Laser-based | Excellent | <$500 |
| PUSH Band 2.0 | Wrist/bar IMU | Moderate (r=0.62-0.70 bench) | ~$300-400 |
| Perch | Overhead camera system | Excellent | Institutional lease |

### 2.4 Market Gaps (Our Opportunity)

1. **No app combines VBT + AI coaching + full training platform.** Metric has VBT but no AI. Training apps have no velocity.
2. **No real VBT-to-program integration.** Velocity data lives in silos, separate from training logs and progression plans.
3. **No autoregulation UX.** The science exists (daily 1RM estimation from warm-up velocity), but no app proactively says "use 85kg today instead of 90kg."
4. **No readiness integration.** Nobody connects HRV/sleep data to velocity targets.
5. **Android exclusion.** Metric (the best all-round app) is iOS-only. Qwik (best accuracy) has no training platform.

### 2.5 What Users Complain About

- Tripod/phone mount requirement (biggest friction)
- Other gym-goers walking in front of the camera
- Lighting problems (fluorescent flicker, dark corners)
- Phone occupied while recording (no music control)
- VBT data siloed from training logs
- No practical autoregulation guidance

---

## 3. VBT Science & Algorithms

### 3.1 The Load-Velocity Relationship

There is a strong, consistent inverse linear relationship between %1RM and mean concentric velocity:

```
velocity = a - b * (%1RM)
```

| Exercise | R² | MVT at 1RM (m/s) |
|----------|-----|-------------------|
| Bench Press | 0.97-0.98 | 0.14-0.17 |
| Back Squat | 0.96-0.97 | 0.27-0.32 |
| Deadlift | 0.89-0.97 | 0.22-0.28 (highly variable) |
| Overhead Press | ~0.95-0.97 | ~0.16-0.22 |

This means: if you know someone's load-velocity profile (calibrated from 2-4 data points), you can estimate their 1RM from any single set's velocity. And day-to-day 1RM fluctuates ±18%, so velocity-based autoregulation is far more accurate than fixed %1RM programming.

### 3.2 Key Velocity Metrics

| Metric | Definition | Best For |
|--------|-----------|----------|
| **Mean Concentric Velocity (MCV)** | Average velocity across entire concentric phase | L-V profiling, 1RM estimation, session tracking |
| **Mean Propulsive Velocity (MPV)** | Average velocity during propulsive phase only (acceleration > -g) | Intra-session readiness, autoregulation |
| **Peak Velocity (PV)** | Maximum instantaneous velocity in concentric | Power/ballistic exercises, explosive training |
| **Time to Peak** | Duration from concentric start to PV | Rate of force development assessment |

### 3.3 Velocity Zones

| Zone | Velocity (m/s) | Intensity | Training Quality |
|------|---------------|-----------|-----------------|
| Absolute Strength | 0.15-0.50 | >85% 1RM | Max strength, neural drive |
| Accelerative Strength | 0.50-0.75 | 75-85% | Strength-endurance |
| Strength-Speed | 0.75-1.00 | 60-75% | Power at moderate loads |
| Speed-Strength | 1.00-1.30 | 45-60% | Explosive power, RFD |
| Speed | >1.30 | <45% | Reactive/ballistic |

### 3.4 RPE-Velocity Mapping via Velocity Loss

Intra-set velocity loss maps to RPE/RIR independent of exercise and load:

```
velocity_loss_% = (first_rep_velocity - current_rep_velocity) / first_rep_velocity * 100
```

| Velocity Loss | RPE | RIR | Fatigue Level |
|--------------|-----|-----|---------------|
| ~5% | ~7 | ~3 | Minimal |
| ~10% | ~7.5-8 | ~2 | Moderate (good working zone) |
| ~15% | ~8-8.5 | ~1-2 | Substantial |
| ~20% | ~8.5-9 | ~1 | Approaching failure |
| ~30-35% | ~9.5-10 | ~0 | At/near volitional failure |

**Training goal thresholds:**
- Power/explosive: stop at 5-10% loss
- Maximal strength: stop at 10-15% loss
- Hypertrophy: stop at 20-30% loss
- Strength-endurance: 30-40% loss

### 3.5 Core Algorithms

#### Concentric Phase Detection

1. Smooth position signal: 4th-order Butterworth low-pass, 10 Hz cutoff (or Savitzky-Golay)
2. Compute velocity via central finite differences
3. Detect zero crossings (direction changes) with minimum duration (200ms) and displacement (5cm) thresholds
4. Validate rep boundaries

```swift
// Central differences
velocity[i] = (position[i+1] - position[i-1]) / (2 * dt)
```

#### 1RM Estimation from Load-Velocity Profile

```swift
func estimate1RM(points: [LoadVelocityPoint], mvt: Double) -> Double? {
    guard points.count >= 3 else { return nil }
    let n = Double(points.count)
    let sumLoad = points.map(\.loadKg).reduce(0, +)
    let sumVel = points.map(\.meanVelocity).reduce(0, +)
    let sumLoadVel = points.map { $0.loadKg * $0.meanVelocity }.reduce(0, +)
    let sumLoadSq = points.map { $0.loadKg * $0.loadKg }.reduce(0, +)

    let denominator = n * sumLoadSq - sumLoad * sumLoad
    guard denominator != 0 else { return nil }
    let b = (n * sumLoadVel - sumLoad * sumVel) / denominator
    let a = (sumVel - b * sumLoad) / n
    guard b < 0 else { return nil }
    return (a - mvt) / (-b)
}
```

Two-point method (Garcia-Ramos): Use one light load (~45% 1RM) and one heavy load (~85% 1RM). SEE of 2.8-4.9 kg. Sufficient for practical training autoregulation.

#### Autoregulation

```swift
func autoregulatedLoad(firstSetVelocity: Double, prescribedLoad: Double,
                        lvProfile: LoadVelocityProfile, targetPercent1RM: Double) -> Double {
    let todayEstimated1RM = lvProfile.estimateOneRM(fromVelocity: firstSetVelocity, atLoad: prescribedLoad)
    let adjustedLoad = todayEstimated1RM * targetPercent1RM
    return (adjustedLoad / 2.5).rounded() * 2.5  // round to nearest plate
}
```

### 3.6 Accuracy Requirements

| Use Case | Minimum Precision | Notes |
|----------|-------------------|-------|
| Training zone classification | ±0.05 m/s | Zone widths are 0.25-0.50 m/s |
| Intra-set velocity loss | ±0.02-0.03 m/s | 10% loss of 0.5 m/s = 0.05 m/s change |
| 1RM estimation | ±0.02 m/s | Each 0.01 m/s error ≈ 1-3 kg |
| Session readiness | ±0.03 m/s | Day-to-day variation is ~±5-15% 1RM |

**Key insight**: Consistency matters more than absolute accuracy. An individualized L-V profile built on the same device absorbs systematic bias. Random error is the real enemy.

---

## 4. On-Device Computer Vision for Barbell Tracking

### 4.1 Recommended Architecture

```
Detection (once per set):  YOLOv8-nano CoreML model → plate bounding box
                           OR user taps plate in preview frame
                                    ↓
Tracking (every frame):    VNTrackObjectRequest (.accurate, Rev3 on iOS 17+)
                                    ↓
Subpixel refinement:       Lucas-Kanade optical flow on 15x15 patch (vDSP)
                                    ↓
Calibration:               Known plate diameter (450mm) → meters/pixel
                                    ↓
Velocity calculation:      Position differentiation + Butterworth smoothing
```

### 4.2 Detection Options

**Option A: YOLOv8-nano (automatic)**

Custom-trained single-class ("plate") detector. Export to CoreML FP16.

| Model | Quantization | Device | Latency |
|-------|-------------|--------|---------|
| YOLOv8-nano | FP16 | iPhone 14 Pro (A16) | ~17-22ms |
| YOLOv8-nano | INT8 | iPhone 15 Pro (A17) | ~10-12ms |

Run once to seed tracking. No per-frame inference needed.

**Option B: User tap (simplest, most reliable)**

User taps the plate in a preview frame. Tap point + known plate diameter gives initial bounding box. Zero ML dependency for detection.

**Option C: Color marker (optional enhancement)**

Bright-colored sticker on bar end cap. Metal HSV kernel + VNDetectContoursRequest. ~1-3ms per frame. Highest precision when marker is visible.

### 4.3 Tracking: Apple Vision Framework

```swift
class BarbellTracker {
    private let sequenceHandler = VNSequenceRequestHandler()

    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let request = trackingRequest else { return }
        try? sequenceHandler.perform([request], on: pixelBuffer, orientation: .right)
    }

    private func handleTrackingResult(request: VNRequest, error: Error?) {
        guard let observation = request.results?.first as? VNDetectedObjectObservation,
              observation.confidence >= 0.3 else { return }

        let centroid = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
        // Feed back for next frame
        trackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation,
                                               completionHandler: handleTrackingResult)
        trackingRequest?.trackingLevel = .accurate
        recordCentroid(centroid, at: timestamp)
    }
}
```

Performance: 2-5ms per frame at `.accurate` on A16. Well within 16.7ms budget at 60fps.

### 4.4 Subpixel Accuracy (Why It Matters)

At 60fps with 0.003 m/pixel scale:

| Localization | Velocity precision |
|-------------|-------------------|
| Integer pixel (1.0 px) | ±0.18 m/s (useless) |
| Subpixel (0.1 px) | ±0.018 m/s (meets VBT requirements) |

**Subpixel tracking is mandatory**, not optional. Lucas-Kanade optical flow on a 15x15 patch via vDSP achieves ~0.05-0.1 pixel precision in ~0.5ms.

### 4.5 Spatial Calibration

Olympic plate diameter = 450mm. Calibrate once per set:

```swift
struct SpatialCalibration {
    let metersPerPixel: Double

    init(plateRadiusNormalized: CGFloat, imageSize: CGSize) {
        let plateRadiusPixels = plateRadiusNormalized * imageSize.width
        self.metersPerPixel = 0.225 / Double(plateRadiusPixels)  // 450mm / 2
    }
}
```

Assumption: camera roughly perpendicular to bar (plate appears circular, not elliptical). LiDAR (Pro models) can remove this assumption by providing direct depth.

### 4.6 Frame Rate Analysis

| FPS | Subpixel | Velocity Precision | Recommendation |
|-----|----------|-------------------|----------------|
| 30 | 0.1 px | ±0.009 m/s | Sufficient with subpixel |
| 60 | 0.1 px | ±0.018 m/s | Recommended operating point |
| 120 | 0.1 px | ±0.036 m/s per sample | Better peak velocity precision |

**Target: 60fps at 1080p.** Enable 120fps on supported devices for improved peak velocity.

### 4.7 Processing Budget at 60fps (16.7ms per frame)

| Stage | Time | Hardware |
|-------|------|----------|
| AVFoundation callback | ~0.1ms | CPU |
| Vision tracking | 2-5ms | Neural Engine |
| Subpixel refinement | ~0.5ms | CPU (vDSP) |
| Velocity calculation | ~0.1ms | CPU |
| UI update dispatch | ~0.5ms | CPU |
| **Total** | **~3.5-6.5ms** | Headroom: 10ms+ |

### 4.8 Why Not MediaPipe / Wrist Tracking?

MediaPipe pose landmarks (wrist joints) introduce 1-2cm of noise from wrist-to-bar offset and grip changes. This corrupts velocity readings. Direct plate center tracking is necessary for VBT-grade accuracy. MediaPipe is useful as a secondary signal for rep boundary detection (detect knee/hip extension patterns).

---

## 5. Gemini AI Coaching Layer

### 5.1 API Capabilities

| Feature | Detail |
|---------|--------|
| Video upload | File API: up to 2GB, 48-hour retention. Accepts MOV directly. |
| Token cost | 258 tokens/sec (video) + 32 tokens/sec (audio) at default resolution |
| Inference latency | 8-23s (P50) for 30s clip on Flash models |
| Output | Structured JSON via `response_mime_type: "application/json"` |

**Recommended model: Gemini 2.5 Flash** (non-thinking). 84.7% VideoMME benchmark vs 85.2% for Pro, at 4x lower cost.

### 5.2 What Gemini Can Analyze

| Capability | Quality | Notes |
|------------|---------|-------|
| Bar path deviation | Good | Qualitative — "bar drifted forward" |
| Joint angles | Good | Qualitative — "knee cave on rep 4" |
| Left/right asymmetry | Good | "Left shoulder dipping" |
| Spine position | Good | Rounding, hyperextension visible from side angle |
| Speed assessment | Qualitative only | "Rep 5 was noticeably slower" — combine with sensor data for numbers |
| Range of motion | Good | "Reaching parallel but not full depth" |
| Safety concerns | Good | Rack height, collar placement, spotter position |
| Cross-set comparison | Excellent | Compare two video URIs in one request |

### 5.3 What Gemini Cannot Do

- Quantitative velocity in m/s (1fps internal sampling)
- Real-time feedback (cloud latency is seconds)
- Precise angle measurements in degrees (without additional prompting)

This is exactly why the hybrid architecture matters: **on-device CV provides the numbers, Gemini provides the coaching intelligence**.

### 5.4 Prompt Templates

#### Post-Set Form Review (primary use case)

```swift
static func formReview(exercise: String, setNumber: Int,
                        velocityData: SetVelocityData) -> String {
    """
    You are a strength training coach reviewing a video of a \(exercise) set.

    VELOCITY DATA (from on-device sensor):
    \(velocityData.toJSONString())

    Respond ONLY with valid JSON:
    {
      "overallFormRating": "good" | "acceptable" | "needs_attention" | "unsafe",
      "repCount": <integer>,
      "keyObservations": ["<specific, actionable observation>", ...],
      "primaryCoachingCue": "<single most important cue for next set>",
      "speedObservation": "<comment on rep speed, referencing velocity data>",
      "safetyFlags": []
    }
    """
}
```

#### Session Summary (end of workout)

Aggregate all per-set analyses + velocity trends. Enable thinking mode for deeper cross-exercise reasoning.

#### Cross-Set Comparison

Send two video file URIs in one request: "Compare set 1 to set 4. What technique changes occurred under fatigue?"

#### Progression Decision (no video needed)

Feed historical velocity data only. "Is the athlete ready for the proposed load increase?"

### 5.5 Cost Model

**Per-set (30s video, Gemini 2.5 Flash):**

```
Video tokens:  30s × 258 = 7,740
Audio tokens:  30s × 32  =   960
Prompt + JSON:            ~   600
Output:                   ~   250
────────────────────────────────
Input cost:  9,300 / 1M × $0.30 = $0.00279
Output cost:   250 / 1M × $2.50 = $0.000625
Per-set total:                     ~$0.0034
```

| Usage Pattern | Monthly Cost |
|--------------|-------------|
| All 320 sets/month | $1.13 |
| Compounds only (~160 sets) | $0.57 |
| User-triggered only (~80 sets) | $0.28 |

### 5.6 Latency UX: Rest Period Window

```
[Set ends] → [Rest timer starts: 90s]
               ↓ (2-5s)
           [Video uploading...]
               ↓ (2-10s)
           [Analyzing form...]
               ↓ (3-8s)
           [Coaching card appears: ~15s into rest]
               ↓
           [User reads feedback, starts next set]
```

P50: ~12s. P95: ~35-45s. Both fit within typical 90-180s rest periods.

### 5.7 Privacy

- **Explicit consent UI** before first video upload
- **Immediate file deletion** via File API after analysis (don't rely on 48-hour auto-expiry)
- **Strip user identifiers** from API calls
- **GDPR**: Establish DPA with Google; gym video may qualify as biometric data
- **App Store**: Disclose third-party AI in app description and first-use flow
- **On-device fallback**: Vision framework pose detection + FoundationModels (iOS 26+) for privacy-first users

### 5.8 Three-Tier Privacy Architecture

```
Tier 1 (always on-device): Vision framework VNDetectHumanBodyPose3DRequest
  → Rep counting, ROM %, joint angles

Tier 2 (on-device text, iOS 26+): Apple FoundationModels
  → Convert measurements to coaching text

Tier 3 (opt-in cloud): Gemini 2.5 Flash
  → Full video + velocity analysis for consenting users
```

---

## 6. iOS Architecture & Integration

### 6.1 Module Structure

```
iOS/Features/VBT/
├── Services/
│   ├── CameraService.swift              # AVCaptureSession, 60fps, recording
│   ├── BarTrackingService.swift         # Vision tracking, delegate bridge
│   ├── VelocityCalculationService.swift # Position → velocity math, filtering
│   └── GeminiCoachingService.swift      # File API upload, generateContent
├── Views/
│   ├── VBTRecordingView.swift           # Full-screen camera + velocity HUD
│   ├── CameraPreviewView.swift          # UIViewRepresentable wrapper
│   ├── BarTrackingOverlayView.swift     # Trajectory visualization
│   ├── VelocityHUDView.swift            # Real-time velocity display
│   ├── VBTControlsView.swift            # Start/stop recording, calibrate
│   └── PostSetAnalysisView.swift        # Coaching card, velocity breakdown
└── ViewModels/
    └── VBTViewModel.swift               # @MainActor @Observable, coordinates UI

Shared/Models/Domain/VBT/
├── VelocityProfile.swift                # Per-rep data
├── SetVelocityData.swift                # Per-set aggregate
├── LoadVelocityPoint.swift              # For L-V curves
└── ExerciseVelocityHistory.swift        # Historical per-exercise

Shared/Services/VBT/
└── VBTAnalyticsService.swift            # L-V profiles, 1RM estimation (no AVFoundation)

Shared/Persistence/SwiftData/Entities/
├── SetVelocityDataEntity.swift          # JSON blob for [VelocityProfile]
└── ExerciseVelocityHistoryEntity.swift  # JSON blob for [LoadVelocityPoint]

Shared/Persistence/Mappers/
└── VBTMapper.swift                      # toDomain / toEntity / updateEntity

Shared/Repositories/Protocols/
└── VBTRepository.swift

Shared/Persistence/SwiftData/Repositories/
└── SwiftDataVBTRepository.swift
```

### 6.2 Data Model

Following the existing JSON blob pattern (like `ProgressionPlanEntity.exercisesJSON`) to avoid deep relationship graphs:

```swift
struct VelocityProfile: Codable, Sendable {
    let id: UUID
    let meanVelocity: Double          // m/s
    let peakVelocity: Double          // m/s
    let timeToPeak: Double            // seconds
    let rangeOfMotionCm: Double?
    let concentricDurationSeconds: Double
    let eccentricDurationSeconds: Double
    let repNumber: Int
}

struct SetVelocityData: Codable, Sendable {
    let id: UUID
    let setId: UUID                   // FK to ExerciseSet.id
    let exerciseId: UUID              // FK to Exercise.id
    let repProfiles: [VelocityProfile]
    let velocityLossPercent: Double
    let setMeanVelocity: Double
    let setPeakVelocity: Double
    let loadKg: Double?
    let recordedAt: Date
    let videoRelativePath: String?    // Documents/VBT/{setId}.mp4
}

struct LoadVelocityPoint: Codable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let loadKg: Double
    let meanVelocity: Double
    let peakVelocity: Double
    let recordedAt: Date
}
```

SwiftData entities use UUID foreign keys (not relationships) to link to existing `WorkoutEntity` — consistent with `WorkoutVectorEntity.workoutId` pattern.

### 6.3 AppContainer Integration

```swift
// In AppContainer (iOS-only):
#if canImport(AVFoundation) && !os(watchOS)
public let vbtRepository: any VBTRepository
public let vbtAnalyticsService: VBTAnalyticsService

// Factory — CameraService/BarTrackingService created fresh per session
// (they hold AVCaptureSession, not shareable)
public func makeVBTViewModel(exerciseId: UUID, setId: UUID) -> VBTViewModel {
    let camera = CameraService()
    let calc = VelocityCalculationService()
    let tracker = BarTrackingService(cameraService: camera, velocityCalcService: calc)
    camera.frameDelegate = tracker
    return VBTViewModel(
        cameraService: camera, barTrackingService: tracker,
        velocityCalcService: calc, vbtAnalyticsService: vbtAnalyticsService,
        geminiService: GeminiCoachingService(), vbtRepository: vbtRepository
    )
}
#endif
```

### 6.4 Integration with Workout Flow

```swift
// In ActiveWorkoutView / ExerciseCardView:
.fullScreenCover(isPresented: $showingVBT) {
    VBTRecordingView(viewModel: container.makeVBTViewModel(
        exerciseId: exercise.id, setId: currentSetId
    ))
}
```

When `VBTViewModel.finishSet()` completes:
1. Persists `SetVelocityData` via `VBTRepository`
2. Updates `ExerciseVelocityHistory` (L-V profile point)
3. Uploads video to Gemini in background
4. Coaching feedback arrives during rest period

`WorkoutViewModel` doesn't need to know about VBT — data linked by UUID.

### 6.5 Camera Pipeline

```swift
// CameraService: 60fps, 1080p, back wide camera
session.sessionPreset = .hd1920x1080
device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
output.alwaysDiscardsLateVideoFrames = true  // drop, don't queue
output.setSampleBufferDelegate(tracker, queue: captureQueue)
```

**Critical rules:**
- Never retain CVPixelBuffer past delegate callback (starves buffer pool)
- Use `isProcessingFrame` gate to prevent Vision queue saturation
- Throttle SwiftUI updates to 10Hz (every 6th frame) via `frameUpdateCounter % 6 == 0`
- Stop camera between sets (battery/thermal)

### 6.6 Performance Budget

| Resource | Budget | Notes |
|----------|--------|-------|
| CPU | 25-38% | Camera decode + Vision + velocity math |
| Battery | 3-5% per 5min active | Stop camera between sets |
| Thermal | ~15min continuous before throttle | Mitigated by inter-set pauses |
| Memory | ~15MB buffer pool | 5 × 3MB frames at 1080p |

Thermal mitigation: observe `ProcessInfo.thermalStateDidChangeNotification`, drop to 30fps if `.serious` or `.critical`.

### 6.7 Permissions

```
NSCameraUsageDescription:
  "HellBentIron uses the camera to measure barbell velocity in real time.
   Video is processed on-device and not uploaded unless you choose AI coaching."
```

No photo library access needed — store videos in `Documents/VBT/` with relative paths.

---

## 7. Implementation Roadmap

### Phase 1: Core Velocity Tracking (MVP)

**Goal:** Measure barbell velocity from camera, display in real time, persist per-set data.

- CameraService (60fps capture)
- BarTrackingService (Vision VNTrackObjectRequest, user-tap initialization)
- VelocityCalculationService (position differentiation, Butterworth smoothing, rep detection)
- Spatial calibration (plate diameter reference)
- VBTRecordingView with velocity HUD overlay
- SwiftData entities + repository
- Integration point in ActiveWorkoutView

**No Gemini, no ML detection, no L-V profiling yet.**

### Phase 2: Analytics & Autoregulation

**Goal:** Build individualized load-velocity profiles, estimate daily 1RM, provide autoregulation.

- VBTAnalyticsService (L-V regression, 1RM estimation)
- ExerciseVelocityHistory accumulation across sessions
- Velocity loss thresholds (configurable per training goal)
- Warm-up velocity → daily 1RM → load recommendation
- L-V profile visualization chart
- Integration with ProgressionPlan (feed VBT-estimated 1RM into plan exercises)

### Phase 3: Gemini AI Coaching

**Goal:** Post-set video analysis with form coaching, session summaries, progression decisions.

- GeminiCoachingService (File API upload, generateContent, file deletion)
- Privacy consent flow
- PostSetAnalysisView (coaching card during rest)
- Session summary at workout end
- Cross-set technique comparison
- Offline queue for poor connectivity
- Cost management (selective analysis toggle)

### Phase 4: Advanced Features

- YOLOv8-nano plate detector (auto-initialization, no user tap)
- Color marker optional mode (Metal HSV kernel)
- 120fps mode on supported devices
- Apple Watch companion (display velocity on wrist)
- Video recording + playback with bar path overlay
- On-device fallback (Vision pose + FoundationModels, iOS 26+)
- HealthKit integration (HRV → readiness → velocity targets)

---

## 8. References

### Published Validation Studies

- PLOS ONE 2024: "Concurrent validity of novel smartphone-based apps for VBT" — [Link](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0313919)
- Sagovac 2024: Metric VBT v4.5 bench press validation (r=0.93 vs Vitruve)
- González-Badillo & Sánchez-Medina 2010: Movement velocity as a measure of loading intensity (R²=0.98 bench press)
- Banyard et al. 2017: Reliability of individualized load-velocity profiles
- Garcia-Ramos et al. 2018-2023: Two-point method for 1RM estimation
- Zourdos et al. 2016: Novel RPE scale measuring repetitions in reserve
- Helms et al. 2017: RPE-velocity relationships for squat/bench/deadlift in powerlifters
- Pareja-Blanco et al. 2020: Velocity loss thresholds for hypertrophy vs strength
- Nature Scientific Reports 2023: Reproducibility of velocity monitoring technologies

### Apple Developer Documentation

- [VNTrackObjectRequest](https://developer.apple.com/documentation/vision/vntrackobjectrequest)
- [VNDetectHumanBodyPose3DRequest](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-3d-with-vision)
- [AVCameraCalibrationData](https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata)

### Google Gemini API

- [Video Understanding](https://ai.google.dev/gemini-api/docs/video-understanding)
- [Files API](https://ai.google.dev/gemini-api/docs/files)
- [Pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Context Caching](https://ai.google.dev/gemini-api/docs/caching)

### Competitive Products

- [Metric VBT](https://www.metric.coach)
- [Qwik VBT](https://apps.apple.com/us/app/qwik-vbt-velocity-and-barpath/id1660094818)
- [Vitruve](https://vitruve.fit)
- [RepOne](https://www.reponestrength.com)
- [GymAware](https://gymaware.com)
- [Perch](https://www.perch.fit)
