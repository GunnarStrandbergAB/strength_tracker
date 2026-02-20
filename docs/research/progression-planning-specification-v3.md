# Progression Planning Module — Technical Specification

**HellBentIron Strength Tracker**
**Version:** 3.0
**Date:** 2026-02-20

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Domain Models](#3-domain-models)
4. [Services Layer](#4-services-layer)
5. [Repository Layer](#5-repository-layer)
6. [SwiftData Persistence](#6-swiftdata-persistence)
7. [ViewModel Layer](#7-viewmodel-layer)
8. [UX Flow & Views](#8-ux-flow--views)
9. [Algorithms & Formulas](#9-algorithms--formulas)
10. [Integration with Existing Systems](#10-integration-with-existing-systems)
11. [Apple Intelligence Communication Layer](#11-apple-intelligence-communication-layer) ←**NEW in**
12. [Implementation Phases](#12-implementation-phases) ← Updated for
13. [Testing Strategy](#13-testing-strategy) ← Updated for
14. [Appendix: Research Foundation](#14-appendix-research-foundation)

---

## 1. Executive Summary

The Progression Planning Module transforms HellBentIron from a workout logger into an intelligent training coach. It introduces a**six-layer feedback loop** —**PLAN → DESIGN → EXECUTE → ANALYZE → CORRECT → COMMUNICATE** — that auto-generates periodized training programs, adjusts loads in real-time via auto-regulation, detects plateaus proactively, triggers reactive deloads when needed,**and explains every decision in contextual, personalized coaching language via Apple Intelligence.**

### Design Principles

-**Research-validated**: Every algorithm traces to peer-reviewed evidence (50+ sources)
-**Training-status-aware**: Beginners, intermediates, and advanced lifters receive fundamentally different programs
-**Auto-regulating**: APRE-based load adjustments respond to daily performance fluctuations (±18% 1RM variance documented by Jovanovic & Flanagan)
-**Non-destructive**: All existing workout, template, and analytics data remain untouched; the module layers on top
-**Progressive disclosure**: Features unlock as training history grows (mirrors existing `AnalyticsFeatureGate`)
-**Deterministic engine + LLM voice**: The engine computes; Apple Intelligence explains. Numbers never touch the model. The model never touches the numbers.

### Key Capabilities

- One-tap plan creation from dashboard (green "CREATE PROGRESSION PLAN" button)
-**Natural language plan creation via Apple Intelligence**: Describe goals in plain text, guided generation maps to structured input
- Four periodization models: Linear, DUP (Daily Undulating), WUP (Weekly Undulating), Block
- Automatic model selection based on training status and goals
- APRE-driven set-by-set load adjustments
- Reactive deload triggers (40–60% volume reduction, intensity maintained)
- Plateau prediction with preemptive exercise rotation
-**Contextual coaching explanations for every ProposedAdjustment**: Why this change, what happens if accepted/declined
-**Post-workout coaching summaries**: Narrative connecting today's session to the broader progression
-**Workout note signal extraction**: NLP-based fatigue, pain, and mood detection feeding into InsightReport
-**Siri integration**: "Hey Siri, what's my workout today?"
- Full integration with existing analytics pipeline (WorkoutVector, PlateauDetection, MuscleBalance)

---

## 2. Architecture Overview

### Six-Layer Feedback Loop (: +COMMUNICATE)

```
┌─────────────────────────────────────────────────────┐
│                    PLAN (Layer 1)                     │
│  User sets goals, selects exercises, inputs 1RM      │
│  → ProgressionPlan, PlanGoal, PlanExercise           │
│  : Natural language alternative via Guided Gen.    │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│                   DESIGN (Layer 2)                    │
│  ProgramDesignService generates periodized blocks     │
│  → TrainingBlock, TrainingWeek, PlannedSession        │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│                  EXECUTE (Layer 3)                    │
│  SessionExecutionService bridges plan ↔ workout       │
│  → WorkoutTemplate generation, APRE load adjustment   │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│                  ANALYZE (Layer 4)                    │
│  PlanAnalyticsService tracks adherence & progress     │
│  → PlanProgress, ExerciseProgress, BlockProgress      │
│  : + WorkoutNoteSignals (pain, fatigue, mood)      │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│                  CORRECT (Layer 5)                    │
│  AdaptiveAdjustmentService modifies plan in-flight    │
│  → PlanAdjustment, deloads, exercise swaps, reforecasts│
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│              COMMUNICATE (Layer 6) —  NEW          │
│  CoachingCommunicationService generates explanations  │
│  → CoachingExplanation, PostWorkoutSummary,          │
│     PlanNarrative, WorkoutNoteSignals                │
│  Apple Intelligence on-device (iPhone 15 Pro+)       │
│  Static template fallback on all other devices       │
└──────────────────────┴──────────────────────────────┘
         ▲                                    │
         └────────────── loops back ──────────┘
```

### The Safety Boundary

```
┌─────────────────────────────────────────────────┐
│              Progression Engine                  │
│  (deterministic, research-validated, safe)       │
│                                                  │
│  APRE tables → weight adjustments               │
│  EWMA → 1RM estimates                           │
│  Arbiter → prioritized proposals                │
│  Detraining → intensity reductions              │
│  Periodization → block/week/session structure   │
│                                                  │
│  OUTPUT: structured data (ProposedAdjustment,    │
│          InsightReport, PlanProgress)            │
└──────────────────────┬──────────────────────────┘
                       │ READ-ONLY data
                       ▼
┌─────────────────────────────────────────────────┐
│          Apple Intelligence Layer            │
│  (generative, contextual, personalized)         │
│                                                  │
│  ProposedAdjustment → coaching explanation      │
│  InsightReport → post-workout summary           │
│  Natural language → PlanCreationInput           │
│  Workout notes → fatigue/pain signal extraction │
│  Plan progress → milestone narratives           │
│                                                  │
│  HARD RULE: Never generates weight/rep/set      │
│  prescriptions. @Generable structs have no      │
│  fields for numerical training parameters.      │
│                                                  │
│  OUTPUT: human-readable text, extracted intents  │
└─────────────────────────────────────────────────┘
```

### Module Boundaries

```
┌── Existing Systems ──────────────────────────────────┐
│  WorkoutRepository  TemplateRepository  ExerciseRepo  │
│  PersonalRecordRepo  AnalyticsRepository              │
│  WorkoutAnalyticsService  PlateauDetectionService     │
│  MuscleBalanceService  WorkoutQualityScoreService     │
│  WorkoutVectorizer  VectorSearchService               │
│  AnalyticsFeatureGate                                 │
└──────────────────────────────────────────────────────┘
         ▲ reads from / writes through
┌── Progression Planning Module ───────────────────────┐
│  Domain Models (8 + 5  @Generable structs)         │
│  Services (5 + 2 : CoachingComm, AIAvailability)   │
│  Repository Protocol + SwiftData Implementation      │
│  ViewModels (3 +  NL plan creation)                │
│  Views (8 +  streaming coaching views)             │
│  AppContainer registrations                          │
│  : App Intents (Siri integration)                  │
└──────────────────────────────────────────────────────┘
```

---

## 3. Domain Models

All models live in `StrengthTracker/Shared/Models/Domain/Progression/`.

### 3.1 Enums

**File:** `ProgressionEnums.swift`

```swift
// MARK: - Training Status
/// Derived from workout history count + time span
enum TrainingStatus: String, Codable, CaseIterable {
    case beginner       // < 3 months consistent training OR < 50 workouts
    case intermediate   // 3–18 months OR 50–200 workouts
    case advanced       // > 18 months AND > 200 workouts

    var recommendedProgramType: ProgramType {
        switch self {
        case .beginner: return .linear
        case .intermediate: return .dailyUndulating
        case .advanced: return .block
        }
    }

    var weeklyFrequencyRange: ClosedRange<Int> {
        switch self {
        case .beginner: return 3...4
        case .intermediate: return 4...5
        case .advanced: return 4...6
        }
    }

    var progressionRate: String {
        switch self {
        case .beginner: return "Session-to-session (2.5–5 kg/week)"
        case .intermediate: return "Weekly (1–2.5 kg/week)"
        case .advanced: return "Monthly (0.5–1 kg/month)"
        }
    }

    /// : Coaching tone adapts to training status
    var coachingTone: String {
        switch self {
        case .beginner: return "Simple, encouraging language. Avoid jargon. Explain concepts."
        case .intermediate: return "Conversational, reference training concepts. Moderate detail."
        case .advanced: return "Technical, concise. Reference specific metrics and research."
        }
    }
}

// MARK: - Program Type
/// Periodization model
enum ProgramType: String, Codable, CaseIterable {
    case linear                 // Classic LP: volume ↓, intensity ↑ across mesocycle
    case dailyUndulating        // DUP: hypertrophy/strength/power rotate within week
    case weeklyUndulating       // WUP: weekly rep-scheme rotation
    case block                  // 3–4 week focused blocks (accumulation → transmutation → realization)

    var displayName: String {
        switch self {
        case .linear: return "Linear Periodization"
        case .dailyUndulating: return "Daily Undulating (DUP)"
        case .weeklyUndulating: return "Weekly Undulating (WUP)"
        case .block: return "Block Periodization"
        }
    }

    var shortDescription: String {
        switch self {
        case .linear: return "Steady weekly increases. Best for building a strength base."
        case .dailyUndulating: return "Vary intensity each session. Best for breaking plateaus."
        case .weeklyUndulating: return "Vary rep schemes weekly. Balanced progression."
        case .block: return "Focused 3–4 week phases. Best for peaking performance."
        }
    }

    var suitableFor: [TrainingStatus] {
        switch self {
        case .linear: return [.beginner, .intermediate]
        case .dailyUndulating: return [.intermediate, .advanced]
        case .weeklyUndulating: return [.intermediate, .advanced]
        case .block: return [.advanced]
        }
    }
}

// MARK: - Training Goal
enum TrainingGoal: String, Codable, CaseIterable {
    case strength               // 1–5 reps, 85–100% 1RM
    case hypertrophy            // 6–12 reps, 65–85% 1RM
    case muscularEndurance      // 12–20+ reps, 50–65% 1RM
    case powerlifting           // Competition peaking
    case generalFitness         // Mixed approach

    var repRange: ClosedRange<Int> {
        switch self {
        case .strength: return 1...5
        case .hypertrophy: return 6...12
        case .muscularEndurance: return 12...20
        case .powerlifting: return 1...5
        case .generalFitness: return 6...15
        }
    }

    var intensityRange: ClosedRange<Double> {
        switch self {
        case .strength: return 0.85...1.0
        case .hypertrophy: return 0.65...0.85
        case .muscularEndurance: return 0.50...0.65
        case .powerlifting: return 0.85...1.0
        case .generalFitness: return 0.60...0.80
        }
    }

    var restSeconds: ClosedRange<Int> {
        switch self {
        case .strength: return 180...300
        case .hypertrophy: return 60...120
        case .muscularEndurance: return 30...60
        case .powerlifting: return 180...300
        case .generalFitness: return 60...180
        }
    }
}

// MARK: - Block Phase
/// For block periodization
enum BlockPhase: String, Codable, CaseIterable {
    case accumulation       // High volume, moderate intensity (65–75% 1RM, 3–4×8–12)
    case transmutation      // Moderate volume, high intensity (78–88% 1RM, 4–5×4–6)
    case realization        // Low volume, peak intensity (88–100% 1RM, 3–5×1–3)
    case deload             // Recovery (40–60% normal volume, maintain intensity)

    var weekDuration: Int {
        switch self {
        case .accumulation: return 4
        case .transmutation: return 3
        case .realization: return 2
        case .deload: return 1
        }
    }
}

// MARK: - DUP Session Type
/// For daily undulating periodization
enum DUPSessionType: String, Codable, CaseIterable {
    case hypertrophy    // 3×8–12 @ 65–75% 1RM
    case strength       // 4–5×3–5 @ 80–88% 1RM
    case power          // 5×1–3 @ 88–95% 1RM

    var sets: Int {
        switch self {
        case .hypertrophy: return 3
        case .strength: return 4
        case .power: return 5
        }
    }

    var repRange: ClosedRange<Int> {
        switch self {
        case .hypertrophy: return 8...12
        case .strength: return 3...5
        case .power: return 1...3
        }
    }

    var intensityRange: ClosedRange<Double> {
        switch self {
        case .hypertrophy: return 0.65...0.75
        case .strength: return 0.80...0.88
        case .power: return 0.88...0.95
        }
    }
}

// MARK: - Plan Status
enum PlanStatus: String, Codable {
    case draft          // User still configuring
    case active         // Currently executing
    case paused         // Temporarily halted
    case completed      // All blocks finished
    case abandoned      // User quit early
}

// MARK: - Adjustment Type
enum AdjustmentType: String, Codable {
    case deload                 // Reactive volume reduction
    case loadIncrease           // Progressive overload
    case loadDecrease           // Regression due to missed targets
    case exerciseSwap           // Plateau-driven substitution
    case volumeAdjustment       // Set/rep modification
    case frequencyChange        // Training days adjustment
    case blockExtension         // Extra week in current phase
    case reforecast             // Revised timeline/targets
}

// MARK: - Deload Trigger
enum DeloadTrigger: String, Codable {
    case scheduledProgrammatic  // Every 4th week (beginner/intermediate)
    case reactivePerformance    // 2+ sessions below target RPE/reps
    case reactiveRecovery       // Recovery pattern indicates fatigue
    case reactivePlateau        // Plateau detected by existing service
    case userRequested          // Manual trigger
    case subjectiveSignal       // : From workout note analysis (pain, fatigue)
}
```

### 3.2 Core Models

**File:** `ProgressionPlan.swift`

```swift
/// Root model: a user's progression plan
struct ProgressionPlan: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var status: PlanStatus
    var trainingStatus: TrainingStatus
    var programType: ProgramType
    var primaryGoal: TrainingGoal
    var secondaryGoal: TrainingGoal?
    var weeklyFrequency: Int                    // Training days per week
    var startDate: Date
    var targetEndDate: Date?
    var actualEndDate: Date?
    var exercises: [PlanExercise]                // Selected exercises with 1RM
    var blocks: [TrainingBlock]                  // Generated program structure
    var adjustments: [PlanAdjustment]            // Historical modifications
    var createdAt: Date
    var updatedAt: Date
    var notes: String?
    var creationSource: PlanCreationSource?      // : How the plan was created

    // : Track how the plan was created
    enum PlanCreationSource: String, Codable {
        case structuredFlow          // Traditional 4-step creation
        case naturalLanguage         // Apple Intelligence guided generation
    }

    // MARK: - Computed Properties

    var totalWeeks: Int {
        blocks.reduce(0) { $0 + $1.durationWeeks }
    }

    /// Current block = first block that has incomplete weeks (session-count-based)
    var currentBlock: TrainingBlock? {
        blocks.first { !$0.allWeeksCompleted }
    }

    /// Current week = first incomplete week in the current block
    var currentWeek: TrainingWeek? {
        currentBlock?.currentWeek
    }

    var overallProgress: Double {
        guard !blocks.isEmpty else { return 0 }
        let totalSessions = blocks.flatMap(\.weeks).flatMap(\.sessions).count
        let completedSessions = blocks.flatMap(\.weeks).flatMap(\.sessions).filter(\.isCompleted).count
        guard totalSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessions)
    }

    var isActive: Bool { status == .active }

    /// Completed microcycles since plan start
    var completedWeeks: Int {
        blocks.flatMap(\.weeks).filter(\.allSessionsCompleted).count
    }

    /// Elapsed calendar weeks since start (for pace calculation)
    var elapsedCalendarWeeks: Int {
        Calendar.current.dateComponents([.weekOfYear], from: startDate, to: Date).weekOfYear ?? 0
    }

    // MARK: - Dynamic Date Projection (Review Fix #4)

    var averageDaysPerWeek: Double {
        guard completedWeeks > 0 else { return 7.0 }
        let firstCompletion = blocks.flatMap(\.weeks).flatMap(\.sessions)
            .compactMap(\.completedAt).min ?? startDate
        let lastCompletion = blocks.flatMap(\.weeks).flatMap(\.sessions)
            .compactMap(\.completedAt).max ?? Date
        let elapsed = lastCompletion.timeIntervalSince(firstCompletion)
        let days = max(1, elapsed / 86400)
        return days / Double(completedWeeks)
    }

    func projectedDateRange(forAbsoluteWeek weekNum: Int) -> (start: Date, end: Date) {
        let weeksFromStart = weekNum - 1
        let daysOffset = Int(Double(weeksFromStart)* averageDaysPerWeek)
        let start = Calendar.current.date(byAdding: .day, value: daysOffset, to: startDate)!
        let end = Calendar.current.date(byAdding: .day, value: Int(averageDaysPerWeek) - 1, to: start)!
        return (start, end)
    }

    var projectedEndDate: Date? {
        let remainingWeeks = totalWeeks - completedWeeks
        guard remainingWeeks > 0 else { return nil }
        let daysRemaining = Int(Double(remainingWeeks)* averageDaysPerWeek)
        return Calendar.current.date(byAdding: .day, value: daysRemaining, to: Date)
    }
}
```

**File:** `PlanExercise.swift`

```swift
/// An exercise selected for the progression plan with baseline metrics
struct PlanExercise: Identifiable, Codable, Equatable {
    let id: UUID
    let exerciseId: UUID                        // References Exercise domain model
    var exerciseName: String
    var primaryMuscleGroup: MuscleGroup
    var category: ExerciseCategory
    var estimated1RM: Double                    // In user's preferred weight unit
    var tested1RM: Double?                      // Actual tested value (if available)
    var oneRMSource: OneRMSource                // How 1RM was determined
    var targetPercentageIncrease: Double?       // Goal: e.g., 0.10 = 10% improvement
    var target1RM: Double?                      // Absolute target
    var current1RM: Double                      // Updated as plan progresses
    var personalRecordId: UUID?                 // Link to PR record
    var isCompound: Bool                        // Compound vs isolation
    var order: Int                              // Priority ordering
    var alternatives: [UUID]                    // Swap candidates (exercise IDs)

    enum OneRMSource: String, Codable {
        case tested             // Direct 1RM test
        case estimated          // Calculated from set data
        case userInput          // User entered manually
        case personalRecord     // From PersonalRecord store
        case naturalLanguage    // : Parsed from NL plan creation input
    }

    func targetWeight(atPercentage pct: Double) -> Double {
        (current1RM* pct).rounded(toNearest: 2.5)
    }
}
```

**File:** `TrainingBlock.swift`

```swift
/// A mesocycle block within the plan (3–6 weeks).
struct TrainingBlock: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var blockPhase: BlockPhase?
    var order: Int
    var durationWeeks: Int
    var weeks: [TrainingWeek]
    var isDeload: Bool
    var isCompleted: Bool
    var completedAt: Date?
    var volumeMultiplier: Double
    var intensityFloor: Double
    var intensityCeiling: Double
    var notes: String?

    var currentWeek: TrainingWeek? {
        weeks.first { !$0.allSessionsCompleted }
    }

    var progress: Double {
        guard !weeks.isEmpty else { return 0 }
        let completed = weeks.filter { $0.allSessionsCompleted }.count
        return Double(completed) / Double(weeks.count)
    }

    var allWeeksCompleted: Bool {
        !weeks.isEmpty && weeks.allSatisfy { $0.allSessionsCompleted }
    }
}
```

**File:** `TrainingWeek.swift`

```swift
/// A microcycle within a block.
///
///**Critical design note (Review Fix #4):** Weeks are NOT pinned to calendar dates.
/// Progression is driven by session completion count, not by the calendar advancing.
struct TrainingWeek: Identifiable, Codable, Equatable {
    let id: UUID
    var weekNumber: Int
    var absoluteWeekNumber: Int
    var sessions: [PlannedSession]
    var isDeload: Bool
    var isCompleted: Bool
    var completedAt: Date?

    var completedSessions: Int {
        sessions.filter { $0.completedWorkoutId != nil }.count
    }

    var allSessionsCompleted: Bool {
        !sessions.isEmpty && sessions.allSatisfy { $0.isCompleted }
    }

    var adherenceRate: Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(completedSessions) / Double(sessions.count)
    }
}
```

**File:** `PlannedSession.swift`

```swift
/// A single planned workout session
struct PlannedSession: Identifiable, Codable, Equatable {
    let id: UUID
    var dayOfWeek: Int?
    var scheduledDate: Date?
    var dupSessionType: DUPSessionType?
    var sessionLabel: String
    var plannedExercises: [PlannedExerciseSet]
    var estimatedDurationMinutes: Int
    var completedWorkoutId: UUID?
    var completedAt: Date?
    var notes: String?
    var userWorkoutNotes: String?               // : Free-text notes from completed workout

    var isCompleted: Bool { completedWorkoutId != nil }

    /// Review Fix #2: scheduledDate Precedence Rules
    var effectiveDate: Date? {
        completedAt ?? scheduledDate
    }

    func toWorkoutTemplate -> WorkoutTemplate {
        WorkoutTemplate(
            id: UUID,
            name: sessionLabel,
            notes: notes,
            sortOrder: 0,
            lastUsedAt: nil,
            timesUsed: 0,
            exercises: plannedExercises.enumerated.map { index, planned in
                TemplateExercise(
                    id: UUID,
                    exercise: planned.exercise,
                    order: index,
                    supersetGroup: nil,
                    notes: planned.notes,
                    restTimerSeconds: planned.restSeconds,
                    targetSets: planned.sets,
                    targetReps: planned.targetReps,
                    targetWeight: planned.targetWeight,
                    targetDurationSeconds: nil,
                    targetDistanceMeters: nil,
                    setTargets: planned.generateSetTargets,
                    isWarmUp: false
                )
            },
            isCustom: false
        )
    }
}
```

**File:** `PlannedExerciseSet.swift`

```swift
/// Target prescription for an exercise within a session
struct PlannedExerciseSet: Identifiable, Codable, Equatable {
    let id: UUID
    var planExerciseId: UUID
    var exercise: Exercise
    var sets: Int
    var targetReps: Int
    var targetWeight: Double
    var percentageOf1RM: Double
    var targetRPE: Double?
    var restSeconds: Int
    var isWarmup: Bool
    var notes: String?

    /// APRE adjustment: recalculate weight based on actual reps achieved.
    /// Review Fix #3: percentage-based, computed from ACTUAL workingWeight.
    func apreAdjustedWeight(
        actualReps: Int,
        workingWeight: Double,
        isCompound: Bool,
        isLowerBody: Bool
    ) -> Double {
        let adjustmentPct: Double
        switch (targetReps, actualReps) {
        // 3RM Protocol (strength focus)
        case (3, let actual) where actual <= 1:
            adjustmentPct = -0.05
        case (3, 2...3):
            adjustmentPct = 0
        case (3, 4...5):
            adjustmentPct = 0.025
        case (3, let actual) where actual >= 6:
            adjustmentPct = 0.05

        // 6RM Protocol (hypertrophy focus)
        case (6, let actual) where actual <= 3:
            adjustmentPct = -0.05
        case (6, 4...5):
            adjustmentPct = -0.025
        case (6, 6...7):
            adjustmentPct = 0
        case (6, 8...9):
            adjustmentPct = 0.025
        case (6, let actual) where actual >= 10:
            adjustmentPct = 0.05

        // 10RM Protocol (endurance focus)
        case (10, let actual) where actual <= 6:
            adjustmentPct = -0.05
        case (10, 7...8):
            adjustmentPct = -0.025
        case (10, 9...11):
            adjustmentPct = 0
        case (10, 12...14):
            adjustmentPct = 0.025
        case (10, let actual) where actual >= 15:
            adjustmentPct = 0.05

        default:
            let deviation = Double(actualReps - targetReps) / Double(targetReps)
            adjustmentPct = deviation.clamped(to: -0.10...0.10)
        }

        let rawAdjusted = workingWeight* (1.0 + adjustmentPct)

        let increment: Double
        if rawAdjusted < 40.0 || !isCompound {
            increment = 1.0
        } else {
            increment = 2.5
        }

        return max(0, rawAdjusted.rounded(toNearest: increment))
    }

    func generateSetTargets -> [TemplateSetTarget] {
        (0..<sets).map { index in
            TemplateSetTarget(
                id: UUID,
                order: index,
                targetReps: targetReps,
                targetWeight: targetWeight,
                targetDurationSeconds: nil,
                targetDistanceMeters: nil,
                setType: isWarmup ? .warmup : .normal
            )
        }
    }
}
```

**File:** `PlanAdjustment.swift`

```swift
/// Record of an automatic or manual plan modification
struct PlanAdjustment: Identifiable, Codable, Equatable {
    let id: UUID
    var adjustmentType: AdjustmentType
    var trigger: AdjustmentTrigger
    var description: String
    var affectedExerciseIds: [UUID]
    var affectedBlockIds: [UUID]
    var previousValues: [String: String]
    var newValues: [String: String]
    var appliedAt: Date
    var wasAccepted: Bool?
    var coachingExplanation: String?             // : Generated by Apple Intelligence (nil on unsupported devices)

    enum AdjustmentTrigger: String, Codable {
        case apre
        case plateauDetected
        case performanceDecline
        case recoverySignal
        case userManual
        case scheduledDeload
        case oneRMUpdate
        case subjectiveSignal                   // : From workout note NLP analysis
    }
}
```

### 3.3 Progress Tracking Models

**File:** `PlanProgress.swift`

```swift
struct PlanProgress: Identifiable, Codable {
    let id: UUID
    let planId: UUID
    var snapshotDate: Date
    var overallAdherence: Double
    var exerciseProgress: [ExerciseProgress]
    var blockProgress: [BlockProgress]
    var estimatedCompletionDate: Date?
    var isOnTrack: Bool
    var weeklyVolumeHistory: [WeeklyVolume]
    var deloadCount: Int
    var adjustmentCount: Int
}

struct ExerciseProgress: Identifiable, Codable {
    let id: UUID
    let planExerciseId: UUID
    var exerciseName: String
    var starting1RM: Double
    var current1RM: Double
    var target1RM: Double?
    var progressPercentage: Double
    var lastPerformedDate: Date?
    var totalSetsCompleted: Int
    var totalRepsCompleted: Int
    var totalVolumeLifted: Double
    var personalRecordsHit: Int
}

struct BlockProgress: Identifiable, Codable {
    let id: UUID
    let blockId: UUID
    var blockName: String
    var weeklyAdherence: [Double]
    var averageRPE: Double?
    var volumeTrend: Double
}

struct WeeklyVolume: Identifiable, Codable {
    let id: UUID
    var weekNumber: Int
    var totalVolume: Double
    var averageIntensity: Double
    var sessionCount: Int
}
```

### 3.4 Apple Intelligence Communication Models ( NEW)

**File:** `CoachingModels.swift`

All models in this section use Apple's `@Generable` macro for constrained decoding via Foundation Models. Each struct has a static template fallback for devices without Apple Intelligence support.

```swift
import FoundationModels

// MARK: - Coaching Explanation (Tier 1: High Value)
/// Generated when the AdjustmentArbiter produces a ProposedAdjustment.
/// Explains WHY the change is recommended using the user's recent data.
///
/// Context budget: ~800 tokens (instructions + proposal + tool output + generation)
@Generable
struct CoachingExplanation {
    @Guide(description: "Why this adjustment is being recommended, referencing the user's recent performance data. 2-3 sentences, conversational tone appropriate to training level.")
    var reasoning: String

    @Guide(description: "What will change in the training plan if accepted. 1-2 sentences.")
    var whatChanges: String

    @Guide(description: "What happens if the user declines. 1 sentence.")
    var ifDeclined: String
}

// MARK: - Post-Workout Summary (Tier 1: High Value)
/// Generated after SessionExecutionService.completeSession computes all adjustments.
/// Provides a narrative connecting today's session to the broader progression.
///
/// Context budget: ~600 tokens
@Generable
struct PostWorkoutSummary {
    @Guide(description: "2-3 sentence summary of how the session went, referencing specific exercises and performance")
    var sessionSummary: String

    @Guide(description: "One specific positive highlight from the workout")
    var highlight: String

    @Guide(description: "One thing to watch or improve next session, if any")
    var lookAhead: String?
}

// MARK: - Natural Language Plan Creation Input (Tier 1: High Value)
/// Guided generation maps free-text user descriptions to structured plan input.
/// This feeds directly into ProgramDesignService.generatePlan — the LLM
/// parses intent only; it does NOT design the program.
///
/// Context budget: ~500 tokens
@Generable
struct PlanCreationInput {
    @Guide(description: "Primary training goal",
           .options(.strength, .hypertrophy, .endurance, .generalFitness))
    var goal: TrainingGoal

    @Guide(description: "Number of training days per week", .range(1...6))
    var frequency: Int

    @Guide(description: "Exercises the user wants to focus on")
    var focusExercises: [String]

    @Guide(description: "How long the user has been consistently training",
           .options(.lessThan3Months, .threeToTwelveMonths, .oneToTwoYears, .moreThanTwoYears))
    var trainingExperience: ExperienceLevel

    @Guide(description: "Any equipment limitations mentioned")
    var equipmentNotes: String?

    /// : Maps the @Generable ExperienceLevel to our domain TrainingStatus
    enum ExperienceLevel: String, Codable {
        case lessThan3Months
        case threeToTwelveMonths
        case oneToTwoYears
        case moreThanTwoYears

        var toTrainingStatus: TrainingStatus {
            switch self {
            case .lessThan3Months: return .beginner
            case .threeToTwelveMonths: return .intermediate
            case .oneToTwoYears: return .intermediate
            case .moreThanTwoYears: return .advanced
            }
        }
    }
}

// MARK: - Workout Note Signal Extraction (Tier 2: Medium Value)
/// Uses the Content Tagging Adapter to extract actionable signals from
/// free-text workout notes. Feeds into InsightReport as subjective inputs.
///
/// Context budget: ~400 tokens
@Generable
struct WorkoutNoteSignals {
    @Guide(description: "Detected pain or discomfort mentions", .maximumCount(3))
    var painSignals: [PainSignal]

    @Guide(description: "Detected fatigue or recovery mentions")
    var fatigueLevel: FatigueLevel?

    @Guide(description: "Detected motivation or mood")
    var mood: MoodSignal?

    @Guide(description: "Any exercise-specific concerns mentioned")
    var exerciseConcerns: [String]
}

@Generable
struct PainSignal {
    var bodyPart: String

    @Guide(description: "Severity of the reported pain", .options(.mild, .moderate, .severe))
    var severity: PainSeverity

    enum PainSeverity: String, Codable {
        case mild       // Mentioned but not impeding training
        case moderate   // Affecting performance or exercise selection
        case severe     // Stopping or significantly limiting training
    }
}

@Generable
enum FatigueLevel: String, Codable {
    case low            // Good energy, recovered
    case normal         // Standard training day
    case elevated       // Tired, poor sleep, life stress mentioned
    case high           // Multiple fatigue indicators
}

@Generable
enum MoodSignal: String, Codable {
    case positive       // Enthusiastic, motivated
    case neutral        // Standard
    case mixed          // Some positive, some negative
    case negative       // Frustrated, unmotivated
}

// MARK: - Plan Narrative (Tier 2: Streaming UI Reveal)
/// Streamed alongside plan generation to create a "coach designing your program" feel.
/// The actual plan computation is already done — this adds contextual descriptions.
///
/// Context budget: ~700 tokens
@Generable
struct PlanNarrative {
    @Guide(description: "A brief description of the training philosophy chosen")
    var philosophy: String

    @Guide(description: "Description of each training block's purpose")
    var blockDescriptions: [BlockNarrative]

    @Guide(description: "A motivational note about what to expect from this program")
    var expectation: String
}

@Generable
struct BlockNarrative {
    var blockName: String

    @Guide(description: "1-2 sentences explaining what this block focuses on and why")
    var description: String
}
```

---

## 4. Services Layer

All services in `StrengthTracker/Shared/Services/Progression/`.

### 4.1 TrainingStatusDetector

**File:** `TrainingStatusDetector.swift`

```swift
/// Determines user's training status from workout history
final class TrainingStatusDetector {
    private let workoutRepository: WorkoutRepository

    init(workoutRepository: WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    func detect async throws -> TrainingStatus {
        let allWorkouts = try await workoutRepository.fetchAll
        let completed = allWorkouts.filter { $0.completedAt != nil }

        guard !completed.isEmpty else { return .beginner }

        let count = completed.count
        let sortedByDate = completed.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let firstDate = sortedByDate.first?.completedAt ?? Date
        let monthsTraining = Calendar.current.dateComponents([.month], from: firstDate, to: Date).month ?? 0

        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date) ?? Date
        let recentWorkouts = completed.filter { ($0.completedAt ?? .distantPast) >= threeMonthsAgo }
        let recentWeeks = max(1, Calendar.current.dateComponents([.weekOfYear], from: threeMonthsAgo, to: Date).weekOfYear ?? 1)
        let weeklyFrequency = Double(recentWorkouts.count) / Double(recentWeeks)

        if monthsTraining > 18 && count > 200 && weeklyFrequency >= 3.0 {
            return .advanced
        }

        if (monthsTraining >= 3 || count >= 50) && weeklyFrequency >= 2.0 {
            return .intermediate
        }

        return .beginner
    }

    struct OneRMEstimate {
        let value: Double
        let source: OneRMWindow
        let isStale: Bool

        enum OneRMWindow: String {
            case recent     // Last 6 months
            case extended   // 6–12 months (10% detraining penalty)
            case none       // No usable data
        }
    }

    func estimateOneRM(exerciseId: UUID) async throws -> OneRMEstimate? {
        let allWorkouts = try await workoutRepository.fetchAll
        let completed = allWorkouts.filter { $0.completedAt != nil }

        let now = Date
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: now)!
        let twelveMonthsAgo = Calendar.current.date(byAdding: .month, value: -12, to: now)!

        let recentEstimate = bestEstimateFromWorkouts(
            completed.filter { ($0.completedAt ?? .distantPast) >= sixMonthsAgo },
            exerciseId: exerciseId
        )

        if let recent = recentEstimate, recent > 0 {
            return OneRMEstimate(value: recent.rounded(toNearest: 2.5), source: .recent, isStale: false)
        }

        let extendedEstimate = bestEstimateFromWorkouts(
            completed.filter {
                let date = $0.completedAt ?? .distantPast
                return date >= twelveMonthsAgo && date < sixMonthsAgo
            },
            exerciseId: exerciseId
        )

        if let extended = extendedEstimate, extended > 0 {
            let penalized = extended* 0.90
            return OneRMEstimate(value: penalized.rounded(toNearest: 2.5), source: .extended, isStale: true)
        }

        return nil
    }

    private func bestEstimateFromWorkouts(_ workouts: [Workout], exerciseId: UUID) -> Double? {
        var bestEstimate: Double = 0

        for workout in workouts {
            for workoutExercise in workout.exercises where workoutExercise.exercise.id == exerciseId {
                for set in workoutExercise.sets where set.isCompleted {
                    guard let weight = set.weight, let reps = set.reps, reps > 0, weight > 0 else { continue }
                    guard reps <= 15 else { continue }

                    let estimate: Double
                    if reps == 1 {
                        estimate = weight
                    } else if reps <= 5 {
                        estimate = weight* (1.0 + Double(reps) / 30.0)
                    } else {
                        estimate = weight* (36.0 / (37.0 - Double(reps)))
                    }

                    bestEstimate = max(bestEstimate, estimate)
                }
            }
        }

        return bestEstimate > 0 ? bestEstimate : nil
    }
}
```

### 4.2 ProgramDesignService

**File:** `ProgramDesignService.swift`

*(Identical to v2 — no changes needed. The deterministic engine is unchanged.)*

```swift
/// Generates periodized training blocks from a ProgressionPlan
final class ProgramDesignService {

    func generateProgram(for plan: ProgressionPlan) -> [TrainingBlock] {
        switch plan.programType {
        case .linear:
            return generateLinearProgram(plan)
        case .dailyUndulating:
            return generateDUPProgram(plan)
        case .weeklyUndulating:
            return generateWUPProgram(plan)
        case .block:
            return generateBlockProgram(plan)
        }
    }

    // ... (all four periodization generators identical to v2)
    // See v2 spec sections 4.2 for full implementation of:
    // - generateLinearProgram (with Review Fix #6 intensity clamp)
    // - generateDUPProgram (with Review Fix #5 %-based overload)
    // - generateWUPProgram (with Review Fix #5 %-based overload)
    // - generateBlockProgram (with Review Fix #7 fixed-template intra-phase)
    // - spreadDaysInWeek (with Review Fix #4 fixed templates)
    // All code preserved exactly as v2.
}
```

### 4.3 SessionExecutionService

**File:** `SessionExecutionService.swift`

*(Core logic identical to v2.  addition: captures workout notes for AI signal extraction.)*

```swift
/// Bridges planned sessions with actual workout execution.
/// : Now also captures workout notes and triggers coaching summary generation.
final class SessionExecutionService {
    private let workoutRepository: WorkoutRepository
    private let templateRepository: TemplateRepository
    private let personalRecordRepository: PersonalRecordRepository

    init(
        workoutRepository: WorkoutRepository,
        templateRepository: TemplateRepository,
        personalRecordRepository: PersonalRecordRepository
    ) {
        self.workoutRepository = workoutRepository
        self.templateRepository = templateRepository
        self.personalRecordRepository = personalRecordRepository
    }

    func prepareSession(_ session: PlannedSession) -> WorkoutTemplate {
        session.toWorkoutTemplate
    }

    /// After workout completion, link it back and compute adjustments.
    /// : Also captures userWorkoutNotes for downstream AI signal extraction.
    func completeSession(
        _ session: PlannedSession,
        workout: Workout,
        planExercises: [PlanExercise]
    ) -> (updatedSession: PlannedSession, adjustments: [PlanAdjustment], updatedExercises: [PlanExercise]) {
        var updated = session
        updated.completedWorkoutId = workout.id
        updated.completedAt = workout.completedAt
        updated.userWorkoutNotes = workout.notes  // : Capture for signal extraction

        var adjustments: [PlanAdjustment] = []
        var updatedPlanExercises = planExercises

        // ... (1RM update logic with EWMA + outlier rejection identical to v2)
        // See v2 spec section 4.3 for full implementation

        return (updated, adjustments, updatedPlanExercises)
    }

    func apreAdjust(
        planned: PlannedExerciseSet,
        completedReps: Int,
        completedWeight: Double,
        isCompound: Bool,
        isLowerBody: Bool
    ) -> Double {
        return planned.apreAdjustedWeight(
            actualReps: completedReps,
            workingWeight: completedWeight,
            isCompound: isCompound,
            isLowerBody: isLowerBody
        )
    }

    func estimateCurrent1RM(from sets: [ExerciseSet]) -> Double? {
        // ... (identical to v2)
        let completedSets = sets.filter { $0.isCompleted }
        guard !completedSets.isEmpty else { return nil }

        var bestEstimate: Double = 0

        for set in completedSets {
            guard let weight = set.weight, let reps = set.reps, reps > 0, weight > 0 else { continue }
            guard reps <= 15 else { continue }

            let estimate: Double
            if reps == 1 {
                estimate = weight
            } else if reps <= 5 {
                estimate = weight* (1.0 + Double(reps) / 30.0)
            } else {
                estimate = weight* (36.0 / (37.0 - Double(reps)))
            }

            bestEstimate = max(bestEstimate, estimate)
        }

        return bestEstimate > 0 ? bestEstimate.rounded(toNearest: 2.5) : nil
    }
}
```

### 4.4 PlanAnalyticsService

*(Identical to v2 — see v2 spec section 4.4 for full implementation.)*

### 4.5 AdaptiveAdjustmentService

**File:** `AdaptiveAdjustmentService.swift`

*(Core InsightReport and AdjustmentArbiter logic identical to v2.  extension: InsightReport gains subjective signal fields from workout note analysis.)*

```swift
///  Extension to InsightReport — subjective signals from workout notes
extension AdaptiveAdjustmentService.InsightReport {
    /// : Extracted from workout notes via Apple Intelligence Content Tagging Adapter
    struct SubjectiveSignals {
        var painSignals: [WorkoutNoteSignals.PainSignal]
        var fatigueLevel: FatigueLevel?
        var mood: MoodSignal?
        var exerciseConcerns: [String]

        var isEmpty: Bool {
            painSignals.isEmpty && fatigueLevel == nil && mood == nil && exerciseConcerns.isEmpty
        }
    }
}
```

The `collectInsights` method is extended (not replaced) to incorporate subjective signals:

```swift
/// : Extended signal collection with subjective inputs from workout notes
func collectInsights(
    plan: ProgressionPlan,
    recentWorkouts: [Workout],
    availableExercises: [Exercise],
    subjectiveSignals: InsightReport.SubjectiveSignals? = nil  // : Optional AI-extracted signals
) async throws -> InsightReport {
    // ... (all existing signal collection from v2 unchanged)

    // : Integrate subjective signals into deload detection
    if let signals = subjectiveSignals, !signals.isEmpty {
        // Recurring pain on a specific exercise strengthens exercise swap signal
        for pain in signals.painSignals where pain.severity == .moderate || pain.severity == .severe {
            if let matchingExercise = plan.exercises.first(where: {
                $0.exerciseName.localizedCaseInsensitiveContains(pain.bodyPart) ||
                signals.exerciseConcerns.contains($0.exerciseName)
            }) {
                // Boost priority of existing plateau signal, or create new swap signal
                if !report.plateauSignals.contains(where: { $0.exerciseId == matchingExercise.exerciseId }) {
                    report.plateauSignals.append(InsightReport.PlateauSignal(
                        exerciseId: matchingExercise.exerciseId,
                        exerciseName: matchingExercise.exerciseName,
                        weeksStalled: 0,  // Not stalled, but pain-driven
                        suggestedSwapId: matchingExercise.alternatives.first?.uuidString,
                        suggestedSwapName: nil  // Resolved at presentation time
                    ))
                }
            }
        }

        // Elevated fatigue from notes adds a deload signal
        if signals.fatigueLevel == .high {
            report.deloadSignals.append(InsightReport.DeloadSignal(
                source: .subjectiveFatigue,
                severity: 0.5
            ))
        }
    }

    return report
}
```

**DeloadSource extension for :**

```swift
extension InsightReport.DeloadSignal.DeloadSource {
    // : Add subjective fatigue source
    static let subjectiveFatigue = DeloadSource(rawValue: "subjectiveFatigue")!
}
```

The AdjustmentArbiter is unchanged — it already handles any number of deload signals via the `urgentDeloadSignals.count >= 2` threshold. Adding a subjective fatigue signal simply contributes to the multi-signal detection that was already designed for extensibility (Review Fix #12).

*(Full v2 AdaptiveAdjustmentService code — InsightReport, AdjustmentArbiter, applyDeload, ProposedAdjustment — preserved exactly as v2. See v2 spec section 4.5.)*

### 4.6 AppleIntelligenceAvailabilityService ( NEW)

**File:** `AppleIntelligenceAvailabilityService.swift`

```swift
import FoundationModels

/// Wraps SystemLanguageModel.availability with graceful degradation.
/// All Apple Intelligence features check this service before attempting generation.
///
///  #4: Centralizes availability logic so fallback behavior is consistent.
final class AppleIntelligenceAvailabilityService {

    enum AIAvailability {
        case available                   // Full Apple Intelligence support
        case unavailable(reason: String) // Device doesn't support, or user disabled
    }

    var currentAvailability: AIAvailability {
        guard #available(iOS 26,*) else {
            return .unavailable(reason: "Requires iOS 26 or later")
        }

        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable:
            return .unavailable(reason: "Apple Intelligence not available on this device")
        @unknown default:
            return .unavailable(reason: "Unknown availability status")
        }
    }

    var isAvailable: Bool {
        if case .available = currentAvailability { return true }
        return false
    }

    ///  #11: Swedish language check
    /// Apple's on-device model supports EN, FR, DE, IT, PT-BR, ES, JA, KO, ZH-CN.
    /// Swedish is NOT supported. Swedish-language users get static fallbacks.
    var supportsCurrentLocale: Bool {
        let supported = ["en", "fr", "de", "it", "pt", "es", "ja", "ko", "zh"]
        let current = Locale.current.language.languageCode?.identifier ?? "en"
        return supported.contains(current)
    }
}
```

### 4.7 CoachingCommunicationService ( NEW)

**File:** `CoachingCommunicationService.swift`

```swift
import FoundationModels

/// The COMMUNICATE layer (Layer 6). Generates personalized coaching text
/// from structured engine output. Protocol-based with automatic fallback.
///
///  #3: This service NEVER generates or modifies training parameters.
/// @Generable structs intentionally have no fields for weights, reps, or sets.
///
/// Architecture:
///   FoundationModelCoachingProvider (Apple Intelligence, on-device)
///     ↓ fallback if unavailable
///   StaticCoachingProvider (template strings, works everywhere)
///
/// Context budgets per integration point:
///   Coaching explanation: ~800 tokens
///   Post-workout summary: ~600 tokens
///   Plan creation parsing: ~500 tokens
///   Note signal extraction: ~400 tokens
///   Plan narrative: ~700 tokens
///   All well within the 4,096 token context window.

// MARK: - Provider Protocol

protocol CoachingExplanationProvider {
    func explainAdjustment(
        _ adjustment: ProposedAdjustment,
        context: CoachingContext
    ) async -> CoachingExplanation

    func generatePostWorkoutSummary(
        session: PlannedSession,
        workout: Workout,
        apreDeltas: [String: Double],
        oneRMChanges: [String: (old: Double, new: Double)]
    ) async -> PostWorkoutSummary

    func parseNaturalLanguagePlanInput(
        _ userText: String
    ) async -> PlanCreationInput?

    func extractWorkoutNoteSignals(
        _ noteText: String
    ) async -> WorkoutNoteSignals?

    func generatePlanNarrative(
        plan: ProgressionPlan
    ) async -> PlanNarrative?
}

/// Context provided to coaching generation for personalization
struct CoachingContext {
    let trainingStatus: TrainingStatus
    let exerciseName: String?
    let recentSessions: [SessionSummary]    // Last 3 sessions, lightweight
    let currentBlock: String?
    let weekNumber: Int?

    struct SessionSummary {
        let weekNumber: Int
        let completedSets: Int
        let plannedSets: Int
        let qualityScore: Int
    }
}

// MARK: - Apple Intelligence Implementation

final class FoundationModelCoachingProvider: CoachingExplanationProvider {
    private let availabilityService: AppleIntelligenceAvailabilityService
    private let fallback: StaticCoachingProvider

    init(availabilityService: AppleIntelligenceAvailabilityService) {
        self.availabilityService = availabilityService
        self.fallback = StaticCoachingProvider
    }

    func explainAdjustment(
        _ adjustment: ProposedAdjustment,
        context: CoachingContext
    ) async -> CoachingExplanation {
        guard availabilityService.isAvailable && availabilityService.supportsCurrentLocale else {
            return await fallback.explainAdjustment(adjustment, context: context)
        }

        do {
            let session = LanguageModelSession

            // Tool: let the model pull specific data it needs
            let recentPerformanceTool = RecentPerformanceTool(context: context)

            let instructions = """
            You are explaining a training adjustment decision made by a progression engine.
            The user's training level: \(context.trainingStatus.coachingTone)
            Never suggest the user deviate from the plan's recommendations.
            Reference the specific numbers provided. Do not invent statistics or cite research.
            """

            let prompt = """
            Explain this adjustment: \(adjustment.adjustment.description)
            Type: \(adjustment.adjustment.adjustmentType.rawValue)
            Priority: \(adjustment.priority)
            """

            let response = try await session.respond(
                to: prompt,
                generating: CoachingExplanation.self,
                instructions: instructions,
                tools: [recentPerformanceTool]
            )

            return response
        } catch {
            return await fallback.explainAdjustment(adjustment, context: context)
        }
    }

    func generatePostWorkoutSummary(
        session: PlannedSession,
        workout: Workout,
        apreDeltas: [String: Double],
        oneRMChanges: [String: (old: Double, new: Double)]
    ) async -> PostWorkoutSummary {
        guard availabilityService.isAvailable && availabilityService.supportsCurrentLocale else {
            return await fallback.generatePostWorkoutSummary(
                session: session, workout: workout,
                apreDeltas: apreDeltas, oneRMChanges: oneRMChanges
            )
        }

        do {
            let session = LanguageModelSession

            let exerciseSummaries = workout.exercises.map { ex in
                let sets = ex.sets.filter(\.isCompleted)
                let totalReps = sets.compactMap(\.reps).reduce(0, +)
                let avgWeight = sets.compactMap(\.weight).average ?? 0
                return "\(ex.exercise.name): \(sets.count) sets, \(totalReps) total reps, avg \(avgWeight.formatted) kg"
            }.joined(separator: ". ")

            let deltaDescriptions = oneRMChanges.map { name, change in
                "\(name): e1RM \(change.old.formatted) → \(change.new.formatted) kg"
            }.joined(separator: ". ")

            let prompt = """
            Summarize this workout session:
            Exercises: \(exerciseSummaries)
            1RM changes: \(deltaDescriptions.isEmpty ? "None" : deltaDescriptions)
            APRE adjustments: \(apreDeltas.isEmpty ? "None" : apreDeltas.description)
            """

            return try await session.respond(
                to: prompt,
                generating: PostWorkoutSummary.self,
                instructions: "Generate a coaching summary of this workout. Be specific about exercises and numbers. Keep it encouraging but honest."
            )
        } catch {
            return await fallback.generatePostWorkoutSummary(
                session: session, workout: workout,
                apreDeltas: apreDeltas, oneRMChanges: oneRMChanges
            )
        }
    }

    func parseNaturalLanguagePlanInput(_ userText: String) async -> PlanCreationInput? {
        guard availabilityService.isAvailable && availabilityService.supportsCurrentLocale else {
            return nil  // NL creation not available — user uses structured flow
        }

        do {
            let session = LanguageModelSession
            return try await session.respond(
                to: userText,
                generating: PlanCreationInput.self,
                instructions: "Parse the user's training description into structured plan parameters. If information is missing, use reasonable defaults for a general fitness plan."
            )
        } catch {
            return nil
        }
    }

    func extractWorkoutNoteSignals(_ noteText: String) async -> WorkoutNoteSignals? {
        guard availabilityService.isAvailable, !noteText.isEmpty else { return nil }

        do {
            let session = LanguageModelSession
            return try await session.respond(
                to: noteText,
                generating: WorkoutNoteSignals.self,
                instructions: "Extract health and training signals from this workout note. Only extract signals that are clearly mentioned — do not infer or assume. If nothing relevant is mentioned, return empty arrays."
            )
        } catch {
            return nil
        }
    }

    func generatePlanNarrative(plan: ProgressionPlan) async -> PlanNarrative? {
        guard availabilityService.isAvailable && availabilityService.supportsCurrentLocale else {
            return nil  // Narrative is a progressive enhancement
        }

        do {
            let session = LanguageModelSession
            let blockSummary = plan.blocks.map { "\($0.name): \($0.durationWeeks) weeks, \($0.intensityFloor* 100)–\($0.intensityCeiling* 100)% 1RM" }.joined(separator: ". ")

            return try await session.respond(
                to: "Describe this training program: \(plan.programType.displayName) for \(plan.primaryGoal.rawValue). Blocks: \(blockSummary)",
                generating: PlanNarrative.self,
                instructions: "Generate a brief, motivating description of this periodized training program. Reference the specific blocks and their purposes."
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Tool Calling (Model pulls data it needs)

struct RecentPerformanceTool: Tool {
    let name = "getRecentPerformance"
    let description = "Get the user's recent workout performance for a specific exercise"

    let context: CoachingContext

    @Generable struct Arguments {
        @Guide(description: "Exercise name to look up")
        var exerciseName: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let summaries = context.recentSessions.map {
            "Week \($0.weekNumber): \($0.completedSets)/\($0.plannedSets) sets, quality \($0.qualityScore)"
        }
        return ToolOutput(summaries.joined(separator: ". "))
    }
}

// MARK: - Static Fallback (Works on all devices)

final class StaticCoachingProvider: CoachingExplanationProvider {

    func explainAdjustment(
        _ adjustment: ProposedAdjustment,
        context: CoachingContext
    ) async -> CoachingExplanation {
        let type = adjustment.adjustment.adjustmentType

        let reasoning: String
        switch type {
        case .deload:
            reasoning = "Your recent sessions show signs of accumulated fatigue. A deload week reduces volume while maintaining intensity, allowing recovery without losing strength."
        case .loadDecrease:
            reasoning = "Performance has declined over recent sessions. Reducing the training load helps you rebuild momentum."
        case .loadIncrease:
            reasoning = "Your estimated 1RM has improved based on recent performance. Weights are being adjusted upward."
        case .exerciseSwap:
            reasoning = "Progress has stalled on this exercise. Swapping to a variation can break through the plateau."
        default:
            reasoning = adjustment.adjustment.description
        }

        return CoachingExplanation(
            reasoning: reasoning,
            whatChanges: "The plan will be updated to reflect this adjustment.",
            ifDeclined: "The current plan continues unchanged."
        )
    }

    func generatePostWorkoutSummary(
        session: PlannedSession,
        workout: Workout,
        apreDeltas: [String: Double],
        oneRMChanges: [String: (old: Double, new: Double)]
    ) async -> PostWorkoutSummary {
        let completedCount = workout.exercises.flatMap(\.sets).filter(\.isCompleted).count
        let totalPlanned = session.plannedExercises.reduce(0) { $0 + $1.sets }

        let highlight: String
        if let prExercise = oneRMChanges.first(where: { $0.value.new > $0.value.old }) {
            highlight = "New estimated 1RM on \(prExercise.key): \(prExercise.value.new.formatted) kg"
        } else {
            highlight = "Completed \(completedCount) sets across \(workout.exercises.count) exercises"
        }

        return PostWorkoutSummary(
            sessionSummary: "Session complete: \(completedCount)/\(totalPlanned) planned sets finished.",
            highlight: highlight,
            lookAhead: apreDeltas.isEmpty ? nil : "APRE adjustments applied for next session."
        )
    }

    func parseNaturalLanguagePlanInput(_ userText: String) async -> PlanCreationInput? {
        return nil  // Not available without Apple Intelligence
    }

    func extractWorkoutNoteSignals(_ noteText: String) async -> WorkoutNoteSignals? {
        return nil  // Not available without Apple Intelligence
    }

    func generatePlanNarrative(plan: ProgressionPlan) async -> PlanNarrative? {
        return nil  // Not available without Apple Intelligence
    }
}
```

---

## 5. Repository Layer

### 5.1 Protocol

**File:** `ProgressionPlanRepository.swift`

```swift
protocol ProgressionPlanRepository {
    func fetchAll async throws -> [ProgressionPlan]
    func fetchActive async throws -> ProgressionPlan?
    func fetch(id: UUID) async throws -> ProgressionPlan?
    func save(_ plan: ProgressionPlan) async throws
    func delete(_ plan: ProgressionPlan) async throws
    func updateStatus(_ planId: UUID, status: PlanStatus) async throws
    func addAdjustment(_ adjustment: PlanAdjustment, toPlan planId: UUID) async throws
    func updateExercise(_ exercise: PlanExercise, inPlan planId: UUID) async throws
    func updateBlock(_ block: TrainingBlock, inPlan planId: UUID) async throws
    func markSessionCompleted(_ sessionId: UUID, workoutId: UUID, inPlan planId: UUID) async throws
}
```

---

## 6. SwiftData Persistence

*(Identical to v2 — Entity, Mapper, Design Decisions all preserved. The new  fields on domain models (coachingExplanation on PlanAdjustment, userWorkoutNotes on PlannedSession, creationSource on ProgressionPlan) are all Optional with nil defaults, so no schema migration is needed for the v2→ transition. Tolerant decoding handles them automatically per Review Fix #13.)*

See v2 spec section 6 for full implementation of:

- 6.1 ProgressionPlanEntity (with schemaVersion)
- 6.2 ProgressionPlanMapper (with tolerant decoding, optimistic concurrency)
- 6.3 Design Decisions (JSON serialization, deferred writes, schema versioning, concurrency)

---

## 7. ViewModel Layer

### 7.1 PlanCreationViewModel

*(Extended for  with natural language plan creation as an alternative entry point.)*

```swift
@MainActor
final class PlanCreationViewModel: ObservableObject {
    // MARK: - Published State (v2 preserved)

    @Published var step: CreationStep = .selectExercises
    @Published var selectedExercises: [Exercise] = []
    @Published var exerciseOneRMs: [UUID: Double] = [:]
    @Published var staleEstimates: Set<UUID> = []
    @Published var missingEstimates: Set<UUID> = []
    @Published var primaryGoal: TrainingGoal = .strength
    @Published var secondaryGoal: TrainingGoal?
    @Published var weeklyFrequency: Int = 3
    @Published var programType: ProgramType?
    @Published var targetWeeks: Int = 12
    @Published var planName: String = ""
    @Published var detectedTrainingStatus: TrainingStatus = .beginner
    @Published var isLoading = false
    @Published var error: String?

    // : Natural language plan creation
    @Published var naturalLanguageInput: String = ""
    @Published var isNLAvailable: Bool = false
    @Published var parsedNLInput: PlanCreationInput?
    @Published var planNarrative: PlanNarrative?

    enum CreationStep: Int, CaseIterable {
        case selectExercises = 0
        case inputOneRMs = 1
        case setGoals = 2
        case reviewPlan = 3
    }

    // MARK: - Dependencies

    private let statusDetector: TrainingStatusDetector
    private let programDesigner: ProgramDesignService
    private let planRepository: ProgressionPlanRepository
    private let exerciseRepository: ExerciseRepository
    private let coachingProvider: CoachingExplanationProvider  // 
    private let aiAvailability: AppleIntelligenceAvailabilityService  // 

    init(
        statusDetector: TrainingStatusDetector,
        programDesigner: ProgramDesignService,
        planRepository: ProgressionPlanRepository,
        exerciseRepository: ExerciseRepository,
        coachingProvider: CoachingExplanationProvider,
        aiAvailability: AppleIntelligenceAvailabilityService
    ) {
        self.statusDetector = statusDetector
        self.programDesigner = programDesigner
        self.planRepository = planRepository
        self.exerciseRepository = exerciseRepository
        self.coachingProvider = coachingProvider
        self.aiAvailability = aiAvailability
        self.isNLAvailable = aiAvailability.isAvailable && aiAvailability.supportsCurrentLocale
    }

    // MARK: - : Natural Language Plan Creation

    /// Alternative entry point: user describes goals in plain text.
    /// Guided Generation maps to PlanCreationInput, which feeds into
    /// the same deterministic ProgramDesignService.
    func parseNaturalLanguageInput async {
        guard !naturalLanguageInput.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        if let parsed = await coachingProvider.parseNaturalLanguagePlanInput(naturalLanguageInput) {
            parsedNLInput = parsed

            // Map parsed input to VM state (same fields as structured flow)
            primaryGoal = parsed.goal
            weeklyFrequency = parsed.frequency
            detectedTrainingStatus = parsed.trainingExperience.toTrainingStatus

            // Resolve focus exercises to Exercise objects
            let allExercises = (try? await exerciseRepository.fetchAll) ?? []
            selectedExercises = parsed.focusExercises.compactMap { name in
                allExercises.first { $0.name.localizedCaseInsensitiveContains(name) }
            }

            // Auto-estimate 1RMs for matched exercises
            for exercise in selectedExercises {
                if let estimate = try? await statusDetector.estimateOneRM(exerciseId: exercise.id) {
                    exerciseOneRMs[exercise.id] = estimate.value
                }
            }

            // Skip to review step
            step = .reviewPlan
        } else {
            error = "Could not parse your description. Try the step-by-step flow instead."
        }
    }

    // ... (all v2 methods preserved: onAppear, addExercise, removeExercise, etc.)

    func generatePreview -> ProgressionPlan {
        // ... (identical to v2, plus creationSource tracking)
        var plan = ProgressionPlan(
            // ... (all v2 fields)
            creationSource: parsedNLInput != nil ? .naturalLanguage : .structuredFlow
        )
        plan.blocks = programDesigner.generateProgram(for: plan)
        return plan
    }

    /// : Generate streaming narrative for plan reveal
    func generateNarrative(for plan: ProgressionPlan) async {
        planNarrative = await coachingProvider.generatePlanNarrative(plan: plan)
    }

    func createPlan async throws {
        var plan = generatePreview
        plan.status = .active
        try await planRepository.save(plan)
    }
}
```

### 7.2 ActivePlanViewModel

*(Extended for  with coaching explanation generation and workout note processing.)*

```swift
@MainActor
final class ActivePlanViewModel: ObservableObject {
    @Published var plan: ProgressionPlan?
    @Published var progress: PlanProgress?
    @Published var proposedAdjustments: [ProposedAdjustment] = []
    @Published var isLoading = false
    @Published var todaySession: PlannedSession?
    @Published var coachingExplanations: [UUID: CoachingExplanation] = [:]  // : adjustment ID → explanation
    @Published var latestPostWorkoutSummary: PostWorkoutSummary?           // 

    private let planRepository: ProgressionPlanRepository
    private let planAnalytics: PlanAnalyticsService
    private let adjustmentService: AdaptiveAdjustmentService
    private let sessionService: SessionExecutionService
    private let workoutRepository: WorkoutRepository
    private let exerciseRepository: ExerciseRepository
    private let coachingProvider: CoachingExplanationProvider  // 

    // ... (init with coachingProvider added)

    func loadActivePlan async {
        isLoading = true
        defer { isLoading = false }

        do {
            plan = try await planRepository.fetchActive

            if let plan = plan {
                progress = try await planAnalytics.generateProgress(for: plan)
                todaySession = findTodaySession(in: plan)

                let recentWorkouts = try await workoutRepository.fetchByDateRange(
                    start: Calendar.current.date(byAdding: .weekOfYear, value: -2, to: Date)!,
                    end: Date
                )
                let exercises = try await exerciseRepository.fetchAll

                // : Extract signals from recent workout notes before analysis
                var subjectiveSignals: AdaptiveAdjustmentService.InsightReport.SubjectiveSignals?
                if let lastNote = recentWorkouts.last?.notes, !lastNote.isEmpty {
                    if let extracted = await coachingProvider.extractWorkoutNoteSignals(lastNote) {
                        subjectiveSignals = .init(
                            painSignals: extracted.painSignals,
                            fatigueLevel: extracted.fatigueLevel,
                            mood: extracted.mood,
                            exerciseConcerns: extracted.exerciseConcerns
                        )
                    }
                }

                proposedAdjustments = try await adjustmentService.analyzeAndPropose(
                    plan: plan,
                    recentWorkouts: recentWorkouts,
                    availableExercises: exercises,
                    subjectiveSignals: subjectiveSignals  // 
                )

                // : Generate coaching explanations for each proposal
                for proposal in proposedAdjustments {
                    let context = CoachingContext(
                        trainingStatus: plan.trainingStatus,
                        exerciseName: plan.exercises.first(where: {
                            proposal.adjustment.affectedExerciseIds.contains($0.id)
                        })?.exerciseName,
                        recentSessions: [],  // Populated from analytics
                        currentBlock: plan.currentBlock?.name,
                        weekNumber: plan.currentWeek?.absoluteWeekNumber
                    )
                    coachingExplanations[proposal.adjustment.id] =
                        await coachingProvider.explainAdjustment(proposal, context: context)
                }
            }
        } catch {
            // Handle silently
        }
    }

    /// : Called after workout completion to generate coaching summary
    func onWorkoutCompleted(session: PlannedSession, workout: Workout, adjustments: [PlanAdjustment]) async {
        let apreDeltas = adjustments
            .filter { $0.trigger == .apre }
            .reduce(into: [String: Double]) { dict, adj in
                if let name = plan?.exercises.first(where: { adj.affectedExerciseIds.contains($0.id) })?.exerciseName {
                    dict[name] = Double(adj.newValues["1RM"] ?? "0") ?? 0
                }
            }

        let oneRMChanges = adjustments
            .filter { $0.trigger == .oneRMUpdate }
            .reduce(into: [String: (old: Double, new: Double)]) { dict, adj in
                if let name = plan?.exercises.first(where: { adj.affectedExerciseIds.contains($0.id) })?.exerciseName,
                   let oldStr = adj.previousValues["1RM"], let old = Double(oldStr),
                   let newStr = adj.newValues["1RM"], let new = Double(newStr) {
                    dict[name] = (old, new)
                }
            }

        latestPostWorkoutSummary = await coachingProvider.generatePostWorkoutSummary(
            session: session,
            workout: workout,
            apreDeltas: apreDeltas,
            oneRMChanges: oneRMChanges
        )
    }

    // ... (acceptAdjustment, declineAdjustment, findTodaySession identical to v2)
}
```

---

## 8. UX Flow & Views

### 8.1 Dashboard Integration

*(Identical to v2, plus  post-workout summary display.)*

### 8.2 View Hierarchy ( Updated)

```
iOS/Features/Progression/
├── Views/
│   ├── PlanCreationFlow/
│   │   ├── PlanCreationView.swift          // Tab/step container
│   │   ├── NaturalLanguagePlanView.swift   // : NL text input alternative
│   │   ├── ExerciseSelectionStep.swift     // Step 1: pick exercises
│   │   ├── OneRMInputStep.swift            // Step 2: enter/confirm 1RM values
│   │   ├── GoalSettingStep.swift           // Step 3: goal + frequency + duration
│   │   └── PlanPreviewStep.swift           // Step 4: review +  streaming narrative
│   ├── ActivePlan/
│   │   ├── ActivePlanCardView.swift        // Dashboard card widget
│   │   ├── PlanDetailView.swift            // Full plan overview with blocks
│   │   ├── BlockDetailView.swift           // Week-by-week view of a block
│   │   ├── SessionDetailView.swift         // Planned session detail
│   │   ├── AdjustmentBannerView.swift      // : Now with coaching explanations
│   │   └── PostWorkoutSummaryView.swift    //  NEW: Coaching summary after workout
│   └── Progress/
│       ├── PlanProgressView.swift          // Charts: 1RM trends, adherence, volume
│       └── ExerciseProgressDetailView.swift
├── ViewModels/
│   ├── PlanCreationViewModel.swift         // : + NL parsing
│   ├── ActivePlanViewModel.swift           // : + coaching generation
│   └── PlanProgressViewModel.swift
└── Intents/                                 //  NEW
    └── TodaysWorkoutIntent.swift           // Siri integration
```

### 8.3 Creation Flow UX (: Dual Entry Points)

**Entry Point A: Natural Language (, Apple Intelligence required)**

When Apple Intelligence is available, the creation flow shows a text field above the structured steps:

```
┌───────────────────────────────────────────────┐
│  Describe your training goals...              │
│  ┌─────────────────────────────────────────┐  │
│  │ "I've been lifting for about 8 months,  │  │
│  │  going 3 times a week. I want to get    │  │
│  │  my bench and squat numbers up."        │  │
│  └─────────────────────────────────────────┘  │
│                                               │
│  [Create from description]                    │
│                                               │
│  ── or set up step by step ──                │
│                                               │
│  [Select Exercises →]                         │
└───────────────────────────────────────────────┘
```

On "Create from description": Guided Generation parses to `PlanCreationInput`, resolves exercises, auto-estimates 1RMs, and jumps to Step 4 (Review). The user can still edit any parameter before confirming.

Fallback: On devices without Apple Intelligence, the NL text field is hidden. Users see only the structured 4-step flow.

**Entry Point B: Structured 4-Step Flow (v2, works everywhere)**

Identical to v2:

- Step 1: Select Exercises
- Step 2: Input 1RM Values
- Step 3: Set Goals & Configuration
- Step 4: Review & Create (: with streaming PlanNarrative if available)

### 8.4 Siri Integration via App Intents ( NEW)

**File:** `TodaysWorkoutIntent.swift`

```swift
import AppIntents

struct TodaysWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Workout"
    static var description = IntentDescription("Shows today's planned training session")

    @Dependency
    private var planRepository: ProgressionPlanRepository

    func perform async throws -> some IntentResult & ProvidesDialog {
        guard let plan = try await planRepository.fetchActive,
              let session = findTodaySession(in: plan) else {
            return .result(dialog: "No session planned for today.")
        }

        let exercises = session.plannedExercises.prefix(5).map {
            "\($0.exercise.name): \($0.sets)×\($0.targetReps) @ \($0.targetWeight.formatted) kg"
        }

        return .result(dialog: "Today is \(session.sessionLabel). \(exercises.joined(separator: ". "))")
    }

    private func findTodaySession(in plan: ProgressionPlan) -> PlannedSession? {
        let todayWeekday = Calendar.current.component(.weekday, from: Date)
        return plan.currentWeek?.sessions.first { session in
            !session.isCompleted && session.dayOfWeek == todayWeekday
        } ?? plan.currentWeek?.sessions.first { !$0.isCompleted }
    }
}
```

---

## 9. Algorithms & Formulas

*(Identical to v2 — all algorithms are deterministic and unchanged.)*

### 9.1 1RM Estimation

Epley for ≤5 reps: `weight × (1 + reps/30)`. Brzycki for 6–10: `weight × 36/(37 - reps)`. Beyond 15 reps: unreliable, returns nil.

### 9.2 APRE Load Adjustment Tables (Percentage-Based)

See section 3.2 PlannedExerciseSet for full tables (3RM, 6RM, 10RM protocols).

### 9.3 Reactive Deload Protocol

40–60% volume reduction, intensity maintained. Research: Jovanovic & Flanagan (±18% daily 1RM variance supports reactive over calendar-based).

### 9.4 Training Status Classification

Beginner (<3 months OR <50 workouts), Intermediate (3–18 months OR 50–200), Advanced (>18 months AND >200 AND ≥3x/week).

### 9.5 Periodization Templates

Linear, DUP, WUP, Block — see ProgramDesignService (section 4.2).

### 9.6 Detraining Rules (Review Fix #9)

10–21 days: 5% reduction. 21–42: 10%. 42+: 15% + repeat week.

### 9.7 Beginner Regression Protocol (Review Fix #10)

2 consecutive misses: 5% training max reduction. 3+: 10% + repeat week.

### 9.8 1RM Smoothing Protocol (Review Fix #8)

EWMA α=0.3. Outlier rejection at ±15%. Regression guard: only apply downward if >5% below current.

---

## 10. Integration with Existing Systems

### 10.1 AppContainer Registration ( Updated)

```swift
// In AppContainer.swift — add alongside existing registrations

// Existing v2 registrations
container.register(TrainingStatusDetector.self) { resolver in
    TrainingStatusDetector(workoutRepository: resolver.resolve(WorkoutRepository.self)!)
}

container.register(ProgramDesignService.self) { _ in
    ProgramDesignService
}

container.register(SessionExecutionService.self) { resolver in
    SessionExecutionService(
        workoutRepository: resolver.resolve(WorkoutRepository.self)!,
        templateRepository: resolver.resolve(TemplateRepository.self)!,
        personalRecordRepository: resolver.resolve(PersonalRecordRepository.self)!
    )
}

container.register(PlanAnalyticsService.self) { resolver in
    PlanAnalyticsService(
        workoutRepository: resolver.resolve(WorkoutRepository.self)!,
        plateauService: resolver.resolve(PlateauDetectionService.self)!,
        muscleBalanceService: resolver.resolve(MuscleBalanceService.self)!,
        qualityScoreService: resolver.resolve(WorkoutQualityScoreService.self)!
    )
}

container.register(AdaptiveAdjustmentService.self) { resolver in
    AdaptiveAdjustmentService(
        planAnalytics: resolver.resolve(PlanAnalyticsService.self)!,
        plateauService: resolver.resolve(PlateauDetectionService.self)!,
        recommendationService: resolver.resolve(ExerciseRecommendationService.self)!,
        muscleBalanceService: resolver.resolve(MuscleBalanceService.self)!
    )
}

container.register(ProgressionPlanRepository.self) { resolver in
    SwiftDataProgressionPlanRepository(modelContext: resolver.resolve(ModelContext.self)!)
}

//  NEW registrations
container.register(AppleIntelligenceAvailabilityService.self) { _ in
    AppleIntelligenceAvailabilityService
}

container.register(CoachingExplanationProvider.self) { resolver in
    FoundationModelCoachingProvider(
        availabilityService: resolver.resolve(AppleIntelligenceAvailabilityService.self)!
    )
}
```

### 10.2 Data Flow with Existing Analytics

*(Identical to v2 — see v2 spec section 10.2.)*

### 10.3 AnalyticsFeatureGate Integration

*(Identical to v2 — see v2 spec section 10.3.)*

---

## 11. Apple Intelligence Communication Layer ( NEW)

This section consolidates the architectural decisions, constraints, and rationale for the COMMUNICATE layer. It draws from the detailed analysis in `apple-intelligence-analysis.md`.

### 11.1 The Central Insight

The progression module already solves the hard problems deterministically. APRE load adjustments, EWMA-smoothed 1RM estimation, multi-signal deload detection, the AdjustmentArbiter's priority ranking — these are peer-reviewed, safety-critical algorithms. What the module does poorly is communicate: a beginner sees "Reactive deload triggered: quality score decline" and has no idea what to do.

Apple Intelligence (Foundation Models, iOS 26+) solves exactly this gap. The ~3B parameter on-device model excels at taking structured data and generating contextual, varied, human-readable explanations. It runs on-device (privacy), works offline (gym basements), costs nothing (consumer app), and responds in under 50ms.

### 11.2 Integration Points by Priority

| Tier | Integration                                   | Value                           | Context Budget         | Sprint |
| ---- | --------------------------------------------- | ------------------------------- | ---------------------- | ------ |
| 1    | Coaching explanations for ProposedAdjustments | High — solves "why?" UX gap     | ~800 tokens            | 3–4    |
| 1    | Natural language plan creation                | High — lowers creation friction | ~500 tokens            | 5–6    |
| 1    | Post-workout coaching summaries               | High — proven by SmartGym       | ~600 tokens            | 3–4    |
| 2    | Workout note signal extraction                | Medium — subjective data loop   | ~400 tokens            | 5–6    |
| 2    | Siri via App Intents                          | Medium — quick access           | N/A (pure App Intents) | 5–6    |
| 2    | Streaming plan narrative                      | Medium — UX polish              | ~700 tokens            | 7–8    |
| 3    | Motivational greetings                        | Low — doesn't fit brand         | —                      | Defer  |
| 3    | Genmoji for milestones                        | Low — zero training value       | —                      | Skip   |
| 3    | AI exercise descriptions                      | Low — risk of inaccuracy        | —                      | Skip   |

### 11.3 Safety Boundary

**Hard rule: The model never generates or modifies weight, rep, or set prescriptions.**

All numerical training parameters flow exclusively through the deterministic engine. The model receives these numbers as read-only context for explanation generation. The `@Generable` structs intentionally have no field for `suggestedWeight`, `newReps`, or similar. Guided Generation's constrained decoding prevents structural deviation.

### 11.4 Device Availability and Fallback Strategy

Foundation Models requires iPhone 15 Pro or later with Apple Intelligence enabled. As of early 2026, this excludes a majority of active iPhones. Every integration point uses the `CoachingExplanationProvider` protocol:

-**Apple Intelligence available**: `FoundationModelCoachingProvider` generates contextual, personalized coaching text
-**Apple Intelligence unavailable**: `StaticCoachingProvider` returns template-based strings (same quality as v2 spec)

The static fallback IS the v2 behavior. Apple Intelligence is a progressive enhancement — nobody loses functionality.

### 11.5 Context Window Management

4,096 tokens total (input + output). A full ProgressionPlan serialized is ~200KB JSON — far beyond. The key insight: we never send the whole plan. Each integration uses a focused slice (see budget table in 11.2). The tool calling pattern helps — the model requests only the data it needs via function calls.

### 11.6 Hallucination Guardrails

1.**Constrain output to explanation, not advice.** `@Guide` descriptions say "explain the reasoning" not "recommend what to do."
2.**Provide all facts via tool outputs.** Instructions say: "Reference the specific numbers provided. Do not invent statistics or cite research."
3.**Instructions over prompts.** Apple's model prioritizes developer instructions. Our instruction set includes: "You are explaining decisions made by the training engine. Never suggest the user deviate from the plan's recommendations."
4.**Graceful errors.** If the model hits a guardrail, fall back to static templates. No error messages shown.

### 11.7 Localization Constraint

Apple's on-device model supports: English, French, German, Italian, Portuguese (BR), Spanish, Japanese, Korean, Simplified Chinese.**Swedish is NOT supported.**

For HellBentIron's Nordic user base:

- English users: full Apple Intelligence coaching
- Swedish users: static template fallbacks (properly localized to Swedish)
- The `AppleIntelligenceAvailabilityService.supportsCurrentLocale` check handles this automatically
- Monitor Apple's language expansion roadmap for Swedish addition

### 11.8 SmartGym Validation

SmartGym ships nearly identical patterns (text-to-workout, coaching explanations, performance summaries) and was featured in Apple's Foundation Models launch. Their CEO calls it the most-loved feature.

Our differentiation: SmartGym's LLM generates workout plans directly. Our deterministic engine generates plans; the LLM only explains. This is safer, more transparent, and more defensible.

| Dimension         | SmartGym                                | HellBentIron                                 |
| ----------------- | --------------------------------------- | -------------------------------------------- |
| Plan generation   | LLM generates exercises/sets/reps       | Deterministic engine; LLM parses intent only |
| Load prescription | LLM-influenced                          | APRE + EWMA (research-validated)             |
| Coaching          | LLM explains its own suggestions        | LLM explains engine's validated decisions    |
| Safety            | Model could hallucinate dangerous loads | Numbers never touch the model                |

---

## 12. Implementation Phases ( Updated)

### Phase 1: Foundation (Sprint 1–2)

**Goal:** Plan creation flow + basic program generation

- [ ] Domain models: all enums (including  DeloadTrigger.subjectiveSignal), ProgressionPlan (with creationSource), PlanExercise, TrainingBlock, TrainingWeek, PlannedSession (with userWorkoutNotes), PlannedExerciseSet
- [ ] PlannedSession.effectiveDate + scheduledDate precedence rules (Review Fix #2)
- [ ] SwiftData: ProgressionPlanEntity, Mapper, SwiftDataProgressionPlanRepository
- [ ] TrainingStatusDetector with time-windowed 1RM estimation
- [ ] ProgramDesignService: Linear periodization (with status-dependent intensityStep + escalation clamp)
- [ ] spreadDaysInWeek fixed templates (Review Fix #4)
- [ ] PlanCreationViewModel + 4-step creation flow views
- [ ] Dashboard integration: green button + ActivePlanCardView
- [ ] AppContainer registrations
- [ ]**: AppleIntelligenceAvailabilityService** — wraps SystemLanguageModel.availability
- [ ]**: Define `CoachingExplanationProvider` protocol** + StaticCoachingProvider fallback
- [ ]**: Define all `@Generable` structs** (CoachingExplanation, PostWorkoutSummary, PlanCreationInput, WorkoutNoteSignals, PlanNarrative)
- [ ]**: Create Foundation Models instruction templates** for each integration point

### Phase 2: Execution & Tracking (Sprint 3–4)

**Goal:** Session execution + APRE + basic analytics + coaching

- [ ] SessionExecutionService with APRE load adjustment (workingWeight-based, Review Fix #3)
- [ ] 1RM EWMA smoothing + outlier rejection (Review Fix #8)
- [ ] PlannedSession → WorkoutTemplate conversion
- [ ] Post-workout plan linkage (session completion, deferred write)
- [ ] Optimistic concurrency check before plan save (Review Fix #14)
- [ ] PlanAnalyticsService: session-linkage attribution (Review Fix #1), adherence tracking, exercise progress
- [ ] PlanProgressView with 1RM trend charts
- [ ] ActivePlanViewModel: today's session, quick-start
- [ ]**: Implement FoundationModelCoachingProvider.explainAdjustment** (Tier 1)
- [ ]**: Implement PostWorkoutSummary generation** (Tier 1)
- [ ]**: Define tool calling interfaces** (RecentPerformanceTool) for plan data access
- [ ]**: Add streaming snapshot support** to AdjustmentBannerView
- [ ]**: PostWorkoutSummaryView** — displayed after workout completion

### Phase 3: Adaptive Intelligence + NL Input (Sprint 5–6)

**Goal:** Full CORRECT layer + DUP/Block programs + natural language

- [ ] ProgramDesignService: DUP (%-based overload), WUP (%-based overload), Block periodization
- [ ] InsightReport signal collection (detraining, regression, multi-signal deload, plateau, adherence)
- [ ] AdjustmentArbiter: priority ranking, mutual exclusion, max 3 proposals (Review Fix #11)
- [ ] Detraining detection + intensity reduction proposals (Review Fix #9)
- [ ] Beginner regression protocol (Review Fix #10)
- [ ] Multi-signal deload triggers (Review Fix #12)
- [ ] AdjustmentBannerView with accept/decline UI +  coaching explanations
- [ ] PlanAdjustment history view
- [ ] Integration with existing PlateauDetectionService
- [ ] Integration with MuscleBalanceService
- [ ]**: Natural language plan creation** with PlanCreationInput guided generation (Tier 1)
- [ ]**: NaturalLanguagePlanView** — text input UI with fallback to structured flow
- [ ]**: Workout note signal extraction** via Content Tagging Adapter (Tier 2)
- [ ]**: Feed extracted signals into InsightReport** (SubjectiveSignals extension)
- [ ]**: App Intents for Siri** — TodaysWorkoutIntent (Tier 2)

### Phase 4: Polish & Advanced Features (Sprint 7–8)

- [ ] Plan duplication/templating
- [ ] Plan sharing (export as JSON)
- [ ] Historical plan comparison
- [ ] Predictive 1RM forecasting (linear regression on historical estimates)
- [ ] Watch app: today's session summary
- [ ] Notification: "Time for your strength session" with today's plan
- [ ] Schema migration testing: simulate v2→ upgrade path (Review Fix #13)
- [ ]**: A/B test coaching explanations vs. static templates** (engagement, adjustment acceptance rate)
- [ ]**: Tune instruction prompts** based on user feedback
- [ ]**: Streaming PlanNarrative** on plan creation review (Tier 2)
- [ ]**: Monitor Apple's language support** for Swedish addition

---

## 13. Testing Strategy ( Updated)

### Unit Tests

```
ProgressionTests/
├── Models/
│   ├── PlanExerciseTests.swift
│   ├── TrainingBlockTests.swift
│   ├── ProgressionPlanTests.swift
│   └── PlannedSessionTests.swift
├── Services/
│   ├── TrainingStatusDetectorTests.swift
│   ├── ProgramDesignServiceTests.swift
│   ├── SessionExecutionServiceTests.swift
│   ├── PlanAnalyticsServiceTests.swift
│   ├── AdaptiveAdjustmentServiceTests.swift
│   ├── AdjustmentArbiterTests.swift
│   ├── CoachingCommunicationServiceTests.swift       //  NEW
│   └── AppleIntelligenceAvailabilityServiceTests.swift //  NEW
├── Persistence/
│   ├── ProgressionPlanMapperTests.swift
│   ├── ConcurrencyTests.swift
│   └── SwiftDataProgressionPlanRepositoryTests.swift
└── AppleIntelligence/                                  //  NEW
    ├── StaticCoachingProviderTests.swift
    ├── CoachingExplanationTests.swift
    ├── PostWorkoutSummaryTests.swift
    ├── WorkoutNoteSignalExtractionTests.swift
    └── PlanCreationInputTests.swift
```

### Key Test Cases (v2 preserved +  additions)

*(All v2 test cases from Review Fixes #1–14 preserved exactly. See v2 spec section 12 for complete list.)*

**: Apple Intelligence Communication Tests:**

**Coaching Explanation Fallback:**

- Apple Intelligence unavailable → StaticCoachingProvider returns template explanation
- Apple Intelligence available → FoundationModelCoachingProvider generates contextual text
- Model error → graceful fallback to static template (no error shown to user)
- Swedish locale → falls back to static provider regardless of device capability

**Post-Workout Summary:**

- All sets completed, 1RM improved → highlight shows new 1RM
- Partial completion, APRE downward → summary acknowledges difficulty, lookAhead notes adjustment
- Empty workout (no completed sets) → minimal summary, no crash

**Natural Language Plan Creation:**

- "I want to get stronger, lifting 3 days a week" → goal: strength, frequency: 3
- "Been lifting 8 months, bench and squat focus" → experience: threeToTwelveMonths, focusExercises: ["bench press", "squat"]
- Gibberish input → returns nil, user sees "try step-by-step" message
- Missing exercise match → falls back to structured flow for exercise selection

**Workout Note Signal Extraction:**

- "Shoulder was bugging me on OHP" → painSignal(bodyPart: "shoulder", severity: .moderate), exerciseConcerns: ["overhead press"]
- "Felt great today" → mood: .positive, no pain signals
- "Didn't sleep well, tired" → fatigueLevel: .elevated
- Empty note → returns nil (no extraction attempted)
- Note without training signals ("nice gym playlist") → empty signals

**Subjective Signal Integration with Arbiter:**

- Recurring pain signal on exercise + existing plateau → exercise swap priority boosted
- High fatigue from notes → adds deload signal (counted toward 2-signal threshold)
- Subjective signals alone (no other triggers) → no action (signals are contributory, not standalone)

**Safety Boundary Tests:**

- @Generable structs have no weight/rep/set fields → verify at compile time
- Coaching explanation referencing "try 5 more kg" → verify instructions prevent this
- Tool calling: model requests data → data provided read-only, no mutation path

**Context Budget Tests:**

- Coaching explanation input: verify < 1000 tokens total
- Post-workout summary: verify < 800 tokens
- Plan creation parsing: verify < 600 tokens

---

## 14. Appendix: Research Foundation

### Periodization Model Selection

| Finding                                                                 | Source                                       | Implication                               |
| ----------------------------------------------------------------------- | -------------------------------------------- | ----------------------------------------- |
| DUP produces 25–41% greater strength gains vs LP in trained individuals | Miranda et al. (2011), Zourdos et al. (2016) | Default to DUP for intermediates          |
| UP more favorable for strength gains (meta-analysis, b=0.51, p=0.001)   | Williams et al. (2017)                       | Undulating > Linear for experienced       |
| Beginners progress similarly with any periodization model               | Brookbush Institute (2024)                   | Linear simplicity preferred for beginners |
| Block periodization excels for peaking performance                      | Issurin (2010)                               | Reserve for advanced/competition prep     |
| Novelty/variety important for continued strength development            | Harries et al. meta-analysis                 | Supports DUP variation principle          |

### Auto-Regulation Rankings

| Method         | SUCRA Squat | SUCRA Bench | Source                       |
| -------------- | ----------- | ----------- | ---------------------------- |
| APRE           | 93.0%       | 97.1%       | Network meta-analysis (2024) |
| RPE            | 66.8%       | 29.9%       | Network meta-analysis (2024) |
| VBT            | 27.0%       | 57.1%       | Network meta-analysis (2024) |
| PBRT (fixed %) | 13.2%       | 15.9%       | Network meta-analysis (2024) |

**Key insight:** APRE is the clear winner for auto-regulation, ranking #1 for both squat and bench press 1RM improvement.

### 1RM Estimation Formulas

Both Epley and Brzycki are widely validated. The hybrid approach maximizes accuracy across the full rep spectrum. Estimates beyond 10 reps become unreliable; beyond 15 should not be used.

### Deload Research

Reactive deloads are superior to proactive scheduled deloads for experienced lifters. Optimal protocol: reduce volume 40–60%, maintain intensity.

### Apple Intelligence Technical Specifications ( NEW)

| Specification       | Value                                                                        | Source                                     |
| ------------------- | ---------------------------------------------------------------------------- | ------------------------------------------ |
| Model size          | ~3B parameters, 2-bit quantized                                              | WWDC25 Foundation Models session           |
| RAM usage           | ~1.2GB when loaded                                                           | Apple developer documentation              |
| Context window      | 4,096 tokens (input + output)                                                | Apple ML research papers                   |
| Latency             | <50ms short requests, 1–2s longer generations                                | WWDC25 benchmarks                          |
| Cost                | Zero (on-device, no API)                                                     | N/A                                        |
| Device requirements | iPhone 15 Pro+, M1+ iPad/Mac                                                 | Apple Intelligence system requirements     |
| Supported languages | EN, FR, DE, IT, PT-BR, ES, JA, KO, ZH-CN                                     | Apple documentation (Swedish NOT included) |
| Key capability      | Summarization, entity extraction, text understanding, constrained generation | Apple ML research                          |
| Not designed for    | General world knowledge, mathematical computation, multi-step reasoning      | Apple documentation                        |

### SmartGym Validation ( NEW)

SmartGym ships Foundation Models integration for fitness with Apple featuring them in the launch announcement. Patterns validated: text-to-workout, coaching explanations, performance summaries, personalized coaching messages. Their CEO: "The Foundation Models framework enables us to deliver on-device features that were once impossible."

---

## File Reference

### New Files to Create

```
Shared/Models/Domain/Progression/
├── ProgressionEnums.swift
├── ProgressionPlan.swift
├── PlanExercise.swift
├── TrainingBlock.swift
├── TrainingWeek.swift
├── PlannedSession.swift
├── PlannedExerciseSet.swift
├── PlanAdjustment.swift
├── PlanProgress.swift
└── CoachingModels.swift                              //  NEW: @Generable structs

Shared/Services/Progression/
├── TrainingStatusDetector.swift
├── ProgramDesignService.swift
├── SessionExecutionService.swift
├── PlanAnalyticsService.swift
├── AdaptiveAdjustmentService.swift
├── AppleIntelligenceAvailabilityService.swift        //  NEW
└── CoachingCommunicationService.swift                //  NEW: Provider protocol + implementations

Shared/Repositories/Protocols/
└── ProgressionPlanRepository.swift

Shared/Persistence/SwiftData/
├── Entities/ProgressionPlanEntity.swift
├── Mappers/ProgressionPlanMapper.swift
└── Repositories/SwiftDataProgressionPlanRepository.swift

iOS/Features/Progression/
├── ViewModels/
│   ├── PlanCreationViewModel.swift                   // : + NL parsing
│   ├── ActivePlanViewModel.swift                     // : + coaching generation
│   └── PlanProgressViewModel.swift
├── Views/
│   ├── PlanCreationFlow/
│   │   ├── PlanCreationView.swift
│   │   ├── NaturalLanguagePlanView.swift             //  NEW
│   │   ├── ExerciseSelectionStep.swift
│   │   ├── OneRMInputStep.swift
│   │   ├── GoalSettingStep.swift
│   │   └── PlanPreviewStep.swift
│   ├── ActivePlan/
│   │   ├── ActivePlanCardView.swift
│   │   ├── PlanDetailView.swift
│   │   ├── BlockDetailView.swift
│   │   ├── SessionDetailView.swift
│   │   ├── AdjustmentBannerView.swift                // : + coaching explanations
│   │   └── PostWorkoutSummaryView.swift              //  NEW
│   └── Progress/
│       ├── PlanProgressView.swift
│       └── ExerciseProgressDetailView.swift
└── Intents/                                           //  NEW
    └── TodaysWorkoutIntent.swift
```

### Modified Files

```
iOS/Features/Dashboard/DashboardView.swift    — Add green button + active plan card
Shared/DI/AppContainer.swift                  — Register new services + ViewModels +  coaching services
Shared/Persistence/SwiftData/Schema.swift     — Add ProgressionPlanEntity to schema
```

---

*End of Specification*
