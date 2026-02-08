import Foundation
import Observation

@MainActor
@Observable
public final class UserPreferencesService {
    public init() {}

    /// The user's preferred weight unit (kg or lbs)
    public var weightUnit: WeightUnit {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "weightUnit") ?? "kg"
            return WeightUnit(rawValue: rawValue) ?? .kg
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "weightUnit")
        }
    }

    /// Default rest timer duration in seconds
    public var defaultRestSeconds: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "defaultRestSeconds")
            return value.nonZero ?? 90
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "defaultRestSeconds")
        }
    }

    /// Whether the user has completed the onboarding flow
    public var hasCompletedOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding")
        }
    }

    /// Whether the default exercises have been seeded into the database
    public var hasSeededExercises: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hasSeededExercises")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasSeededExercises")
        }
    }

    /// The user's preferred distance unit (km or miles)
    public var distanceUnit: DistanceUnit {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "distanceUnit") ?? "km"
            return DistanceUnit(rawValue: rawValue) ?? .km
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "distanceUnit")
        }
    }

    /// Whether to automatically start rest timer after completing a set
    public var autoStartRestTimer: Bool {
        get {
            // Default to true if not set
            if !UserDefaults.standard.bool(forKey: "hasSetAutoStartRestTimer") {
                return true
            }
            return UserDefaults.standard.bool(forKey: "autoStartRestTimer")
        }
        set {
            UserDefaults.standard.set(true, forKey: "hasSetAutoStartRestTimer")
            UserDefaults.standard.set(newValue, forKey: "autoStartRestTimer")
        }
    }

    /// Whether the user has been prompted for HealthKit authorization
    public var hasRequestedHealthKitAuth: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hasRequestedHealthKitAuth")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasRequestedHealthKitAuth")
        }
    }

    /// Preferred rest timer duration in seconds (for Watch and widgets)
    public var preferredRestTimerDuration: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "preferredRestTimerDuration")
            return value.nonZero ?? 90
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preferredRestTimerDuration")
        }
    }

    /// Reset all preferences to defaults
    public func resetToDefaults() {
        weightUnit = .kg
        distanceUnit = .km
        defaultRestSeconds = 90
        autoStartRestTimer = true
        preferredRestTimerDuration = 90
        // Note: Don't reset onboarding, seeding, or HealthKit auth flags
    }
}

private extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}
