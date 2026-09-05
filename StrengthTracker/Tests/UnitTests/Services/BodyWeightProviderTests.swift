import Testing
import Foundation
@testable import StrengthTrackerShared

/// HealthKit stub that returns a scripted body weight.
final class StubBodyWeightHealthKit: HealthKitServiceProtocol, @unchecked Sendable {
    var bodyWeightKg: Double?
    var authorizationRequests = 0
    init(bodyWeightKg: Double? = nil) { self.bodyWeightKg = bodyWeightKg }
    func requestAuthorization() async throws { authorizationRequests += 1 }
    func saveWorkout(_ workout: Workout, calories: Double, bodyWeightKg: Double) async throws {}
    func fetchBodyWeightKg() async -> Double? { bodyWeightKg }
    func startWorkoutSession() async throws {}
    func endWorkoutSession(_ workout: Workout) async throws {}
}

@Suite("BodyWeightProvider", .serialized)
@MainActor
struct BodyWeightProviderTests {

    private static let touchedKeys = ["bodyWeightKg", "hasRequestedHealthKitAuth"]

    private func withPrefs(bodyWeightKg: Double?, _ body: (UserPreferencesService) async throws -> Void) async rethrows {
        let defaults = UserDefaults.standard
        let snapshot = Self.touchedKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in snapshot {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let prefs = UserPreferencesService()
        prefs.bodyWeightKg = bodyWeightKg
        try await body(prefs)
    }

    @Test("Initial value is synchronous: prefs when set, default otherwise")
    func initialValue() async {
        await withPrefs(bodyWeightKg: 82) { prefs in
            let provider = BodyWeightProvider(healthKitService: StubBodyWeightHealthKit(), userPreferencesService: prefs)
            #expect(provider.current == 82)
            #expect(provider.source == .preferences)
        }
        await withPrefs(bodyWeightKg: nil) { prefs in
            let provider = BodyWeightProvider(healthKitService: StubBodyWeightHealthKit(), userPreferencesService: prefs)
            #expect(provider.current == UserPreferencesService.defaultBodyWeightKg)
            #expect(provider.source == .defaultValue)
        }
    }

    @Test("HealthKit wins over prefs after refresh, and falls back when it disappears")
    func healthKitPrecedence() async {
        await withPrefs(bodyWeightKg: 82) { prefs in
            let healthKit = StubBodyWeightHealthKit(bodyWeightKg: 90)
            let provider = BodyWeightProvider(healthKitService: healthKit, userPreferencesService: prefs, debounce: .milliseconds(10))
            await provider.refresh()
            #expect(provider.current == 90)
            #expect(provider.source == .healthKit)
            #expect(provider.lastRefreshedAt != nil)

            healthKit.bodyWeightKg = nil
            await provider.refresh()
            #expect(provider.current == 82)
            #expect(provider.source == .preferences)
        }
    }

    @Test("A prefs edit re-resolves without a refresh")
    func prefsObservation() async {
        await withPrefs(bodyWeightKg: 80) { prefs in
            let provider = BodyWeightProvider(healthKitService: StubBodyWeightHealthKit(), userPreferencesService: prefs, debounce: .milliseconds(10))
            prefs.bodyWeightKg = 85
            for _ in 0..<50 where provider.current != 85 {
                try? await Task.sleep(for: .milliseconds(5))
            }
            #expect(provider.current == 85)
        }
    }

    @Test("Material change fires the rebuild hook once after the debounce; small changes do not")
    func materialChange() async {
        await withPrefs(bodyWeightKg: 80) { prefs in
            let healthKit = StubBodyWeightHealthKit()
            let provider = BodyWeightProvider(healthKitService: healthKit, userPreferencesService: prefs, debounce: .milliseconds(20))
            var calls: [(Double, Double)] = []
            provider.onMaterialChange = { old, new in calls.append((old, new)) }

            healthKit.bodyWeightKg = 80.5
            await provider.refresh()
            try? await Task.sleep(for: .milliseconds(60))
            #expect(calls.isEmpty, "0.5 kg is below the threshold")

            healthKit.bodyWeightKg = 83
            await provider.refresh()
            healthKit.bodyWeightKg = 84
            await provider.refresh()
            try? await Task.sleep(for: .milliseconds(80))
            #expect(calls.count == 1, "two rapid changes collapse into one rebuild")
            #expect(calls.first?.1 == 84)
        }
    }

    @Test("requestHealthKitAccess asks once, records it, and refreshes")
    func requestAccess() async throws {
        try await withPrefs(bodyWeightKg: nil) { prefs in
            let healthKit = StubBodyWeightHealthKit(bodyWeightKg: 77)
            let provider = BodyWeightProvider(healthKitService: healthKit, userPreferencesService: prefs, debounce: .milliseconds(10))
            try await provider.requestHealthKitAccess()
            #expect(healthKit.authorizationRequests == 1)
            #expect(prefs.hasRequestedHealthKitAuth)
            #expect(provider.current == 77)
        }
    }
}
