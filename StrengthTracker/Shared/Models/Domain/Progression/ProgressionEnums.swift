import Foundation

// MARK: - Training Status
/// Derived from workout history count + time span
public enum TrainingStatus: String, Codable, CaseIterable, Sendable {
    case beginner       // < 3 months consistent training OR < 50 workouts
    case intermediate   // 3–18 months OR 50–200 workouts
    case advanced       // > 18 months AND > 200 workouts

    public var recommendedProgramType: ProgramType {
        switch self {
        case .beginner: return .linear
        case .intermediate: return .dailyUndulating
        case .advanced: return .block
        }
    }

    public var weeklyFrequencyRange: ClosedRange<Int> {
        switch self {
        case .beginner: return 3...4
        case .intermediate: return 4...5
        case .advanced: return 4...6
        }
    }

    public var progressionRate: String {
        switch self {
        case .beginner: return "Session-to-session (2.5–5 kg/week)"
        case .intermediate: return "Weekly (1–2.5 kg/week)"
        case .advanced: return "Monthly (0.5–1 kg/month)"
        }
    }
}

// MARK: - Program Type
/// Periodization model
public enum ProgramType: String, Codable, CaseIterable, Sendable {
    case linear                 // Classic LP: volume ↓, intensity ↑ across mesocycle
    case dailyUndulating        // DUP: hypertrophy/strength/power rotate within week
    case weeklyUndulating       // WUP: weekly rep-scheme rotation
    case block                  // 3–4 week focused blocks (accumulation → transmutation → realization)

    public var displayName: String {
        switch self {
        case .linear: return "Linear Periodization"
        case .dailyUndulating: return "Daily Undulating (DUP)"
        case .weeklyUndulating: return "Weekly Undulating (WUP)"
        case .block: return "Block Periodization"
        }
    }

    public var shortDescription: String {
        switch self {
        case .linear: return "Steady weekly increases. Best for building a strength base."
        case .dailyUndulating: return "Vary intensity each session. Best for breaking plateaus."
        case .weeklyUndulating: return "Vary rep schemes weekly. Balanced progression."
        case .block: return "Focused 3–4 week phases. Best for peaking performance."
        }
    }

    public var suitableFor: [TrainingStatus] {
        switch self {
        case .linear: return [.beginner, .intermediate]
        case .dailyUndulating: return [.intermediate, .advanced]
        case .weeklyUndulating: return [.intermediate, .advanced]
        case .block: return [.advanced]
        }
    }
}

// MARK: - Training Goal
public enum TrainingGoal: String, Codable, CaseIterable, Sendable {
    case strength               // 1–5 reps, 85–100% 1RM
    case hypertrophy            // 6–12 reps, 65–85% 1RM
    case muscularEndurance      // 12–20+ reps, 50–65% 1RM
    case powerlifting           // Competition peaking
    case generalFitness         // Mixed approach

    public var repRange: ClosedRange<Int> {
        switch self {
        case .strength: return 1...5
        case .hypertrophy: return 6...12
        case .muscularEndurance: return 12...20
        case .powerlifting: return 1...5
        case .generalFitness: return 6...15
        }
    }

    public var intensityRange: ClosedRange<Double> {
        switch self {
        case .strength: return 0.85...1.0
        case .hypertrophy: return 0.65...0.85
        case .muscularEndurance: return 0.50...0.65
        case .powerlifting: return 0.85...1.0
        case .generalFitness: return 0.60...0.80
        }
    }

    public var restSeconds: ClosedRange<Int> {
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
public enum BlockPhase: String, Codable, CaseIterable, Sendable {
    case accumulation       // High volume, moderate intensity (65–75% 1RM, 3–4×8–12)
    case transmutation      // Moderate volume, high intensity (78–88% 1RM, 4–5×4–6)
    case realization        // Low volume, peak intensity (88–100% 1RM, 3–5×1–3)
    case deload             // Recovery (40–60% normal volume, maintain intensity)

    public var weekDuration: Int {
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
public enum DUPSessionType: String, Codable, CaseIterable, Sendable {
    case hypertrophy    // 3×8–12 @ 65–75% 1RM
    case strength       // 4–5×3–5 @ 80–88% 1RM
    case power          // 5×1–3 @ 88–95% 1RM

    public var sets: Int {
        switch self {
        case .hypertrophy: return 3
        case .strength: return 4
        case .power: return 5
        }
    }

    public var repRange: ClosedRange<Int> {
        switch self {
        case .hypertrophy: return 8...12
        case .strength: return 3...5
        case .power: return 1...3
        }
    }

    public var intensityRange: ClosedRange<Double> {
        switch self {
        case .hypertrophy: return 0.65...0.75
        case .strength: return 0.80...0.88
        case .power: return 0.88...0.95
        }
    }
}

// MARK: - Plan Status
public enum PlanStatus: String, Codable, Sendable {
    case draft          // User still configuring
    case active         // Currently executing
    case paused         // Temporarily halted
    case completed      // All blocks finished
    case abandoned      // User quit early
}

// MARK: - Adjustment Type
public enum AdjustmentType: String, Codable, Sendable {
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
public enum DeloadTrigger: String, Codable, Sendable {
    case scheduledProgrammatic  // Every 4th week (beginner/intermediate)
    case reactivePerformance    // 2+ sessions below target RPE/reps
    case reactiveRecovery       // Recovery pattern indicates fatigue
    case reactivePlateau        // Plateau detected by existing service
    case userRequested          // Manual trigger
    case subjectiveSignal       // From workout note analysis (pain, fatigue)
}

// MARK: - Adjustment Trigger
public enum AdjustmentTrigger: String, Codable, Sendable {
    case apre
    case plateauDetected
    case performanceDecline
    case recoverySignal
    case userManual
    case scheduledDeload
    case oneRMUpdate
    case subjectiveSignal       // From workout note NLP analysis
}
