import Foundation
import Observation

@MainActor
@Observable
public final class UserPreferencesService {

    /// Default body weight fallback when neither HealthKit nor user setting is available
    public static let defaultBodyWeightKg: Double = 70.0

    /// Default rest timer duration in seconds
    public static let defaultRestSecondsValue: Int = 90

    /// Default reps when adding an exercise to a template
    public static let defaultRepsValue: Int = 10

    /// The user's preferred weight unit (kg or lbs)
    public var weightUnit: WeightUnit {
        didSet { UserDefaults.standard.set(weightUnit.rawValue, forKey: "weightUnit") }
    }

    /// Default rest timer duration in seconds
    public var defaultRestSeconds: Int {
        didSet { UserDefaults.standard.set(defaultRestSeconds, forKey: "defaultRestSeconds") }
    }

    /// Default reps when adding an exercise to a template
    public var defaultReps: Int {
        didSet { UserDefaults.standard.set(defaultReps, forKey: "defaultReps") }
    }

    /// Whether the user has completed the onboarding flow
    public var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    /// Whether the default exercises have been seeded into the database
    public var hasSeededExercises: Bool {
        didSet { UserDefaults.standard.set(hasSeededExercises, forKey: "hasSeededExercises") }
    }

    /// The user's preferred distance unit (km or miles)
    public var distanceUnit: DistanceUnit {
        didSet { UserDefaults.standard.set(distanceUnit.rawValue, forKey: "distanceUnit") }
    }

    /// Whether to automatically start rest timer after completing a set
    public var autoStartRestTimer: Bool {
        didSet {
            UserDefaults.standard.set(true, forKey: "hasSetAutoStartRestTimer")
            UserDefaults.standard.set(autoStartRestTimer, forKey: "autoStartRestTimer")
        }
    }

    /// Whether the user has been prompted for HealthKit authorization
    public var hasRequestedHealthKitAuth: Bool {
        didSet { UserDefaults.standard.set(hasRequestedHealthKitAuth, forKey: "hasRequestedHealthKitAuth") }
    }

    /// Webhook URL for posting completed workouts to an external endpoint
    public var webhookURL: String {
        didSet { UserDefaults.standard.set(webhookURL, forKey: "webhookURL") }
    }

    /// Bearer token for webhook authentication (optional)
    public var webhookBearerToken: String {
        didSet { UserDefaults.standard.set(webhookBearerToken, forKey: "webhookBearerToken") }
    }

    /// Whether the AI assistant (Grok chat) is enabled
    public var aiChatEnabled: Bool {
        didSet { UserDefaults.standard.set(aiChatEnabled, forKey: "aiChatEnabled") }
    }

    /// Vector schema version — bump when normalization constants change to trigger recomputation
    public var vectorVersion: Int {
        didSet { UserDefaults.standard.set(vectorVersion, forKey: "vectorVersion") }
    }

    /// Tracks the one-time effective-load migration (factor backfill + PR recalc)
    public var effectiveLoadModelVersion: Int {
        didSet { UserDefaults.standard.set(effectiveLoadModelVersion, forKey: "effectiveLoadModelVersion") }
    }

    /// Whether to always show the intensity (RPE/RIR) column in workout exercises.
    /// Kept under the historical name/key so existing users' setting survives.
    public var alwaysShowRPE: Bool {
        didSet { UserDefaults.standard.set(alwaysShowRPE, forKey: "alwaysShowRPE") }
    }

    /// The user's preferred intensity metric for set logging (RPE or RIR)
    public var intensityMetric: IntensityMetric {
        didSet { UserDefaults.standard.set(intensityMetric.rawValue, forKey: "intensityMetric") }
    }

    /// Deload weight as a percentage of normal weight (e.g. 50 = use 50% of normal)
    public var deloadWeightPercentage: Int {
        didSet { UserDefaults.standard.set(deloadWeightPercentage, forKey: "deloadWeightPercentage") }
    }

    /// Deload rest timer as a percentage of normal rest (e.g. 75 = use 75% of normal)
    public var deloadRestPercentage: Int {
        didSet { UserDefaults.standard.set(deloadRestPercentage, forKey: "deloadRestPercentage") }
    }

    /// User's body weight in kg (last-resort fallback for calorie estimation)
    public var bodyWeightKg: Double? {
        didSet {
            if let bodyWeightKg {
                UserDefaults.standard.set(bodyWeightKg, forKey: "bodyWeightKg")
            } else {
                UserDefaults.standard.removeObject(forKey: "bodyWeightKg")
            }
        }
    }

    public init() {
        let defaults = UserDefaults.standard

        let weightRaw = defaults.string(forKey: "weightUnit") ?? "kg"
        self.weightUnit = WeightUnit(rawValue: weightRaw) ?? .kg

        let restSeconds = defaults.integer(forKey: "defaultRestSeconds")
        self.defaultRestSeconds = restSeconds != 0 ? restSeconds : Self.defaultRestSecondsValue

        let reps = defaults.integer(forKey: "defaultReps")
        self.defaultReps = reps != 0 ? reps : Self.defaultRepsValue

        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.hasSeededExercises = defaults.bool(forKey: "hasSeededExercises")

        let distanceRaw = defaults.string(forKey: "distanceUnit") ?? "km"
        self.distanceUnit = DistanceUnit(rawValue: distanceRaw) ?? .km

        if defaults.bool(forKey: "hasSetAutoStartRestTimer") {
            self.autoStartRestTimer = defaults.bool(forKey: "autoStartRestTimer")
        } else {
            self.autoStartRestTimer = true
        }

        self.hasRequestedHealthKitAuth = defaults.bool(forKey: "hasRequestedHealthKitAuth")

        self.alwaysShowRPE = defaults.bool(forKey: "alwaysShowRPE")

        let metricRaw = defaults.string(forKey: "intensityMetric") ?? IntensityMetric.rpe.rawValue
        self.intensityMetric = IntensityMetric(rawValue: metricRaw) ?? .rpe

        self.webhookURL = defaults.string(forKey: "webhookURL") ?? ""
        self.webhookBearerToken = defaults.string(forKey: "webhookBearerToken") ?? ""

        let deloadWeight = defaults.integer(forKey: "deloadWeightPercentage")
        self.deloadWeightPercentage = deloadWeight != 0 ? deloadWeight : 50

        let deloadRest = defaults.integer(forKey: "deloadRestPercentage")
        self.deloadRestPercentage = deloadRest != 0 ? deloadRest : 75

        let weight = defaults.double(forKey: "bodyWeightKg")
        self.bodyWeightKg = weight > 0 ? weight : nil

        self.vectorVersion = defaults.integer(forKey: "vectorVersion")
        self.effectiveLoadModelVersion = defaults.integer(forKey: "effectiveLoadModelVersion")

        self.aiChatEnabled = defaults.bool(forKey: "aiChatEnabled")
    }

    /// Reset all preferences to defaults
    public func resetToDefaults() {
        weightUnit = .kg
        distanceUnit = .km
        defaultRestSeconds = Self.defaultRestSecondsValue
        defaultReps = Self.defaultRepsValue
        autoStartRestTimer = true
        alwaysShowRPE = false
        intensityMetric = .rpe
        deloadWeightPercentage = 50
        deloadRestPercentage = 75
        // Note: Don't reset onboarding, seeding, or HealthKit auth flags
    }
}
