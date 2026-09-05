import Foundation
import Observation

/// The single resolved body weight (kg) every volume, e1RM, PR, quality-score
/// and vector consumer reads. Resolution: newest HealthKit bodyMass sample →
/// Settings body weight → `UserPreferencesService.defaultBodyWeightKg`.
///
/// `current` is synchronous and valid from init (HealthKit is folded in after
/// `refresh()`), so sync consumers never fall back to a hard-coded value. When
/// the resolved value moves by `materialChangeThresholdKg` or more, derived data
/// (vectors, PRs, quality caches) is rebuilt once via `onMaterialChange`.
@MainActor
@Observable
public final class BodyWeightProvider {
    public enum Source: String, Sendable {
        case healthKit
        case preferences
        case defaultValue
    }

    public static let materialChangeThresholdKg: Double = 1.0

    public private(set) var current: Double
    public private(set) var source: Source
    public private(set) var lastRefreshedAt: Date?

    /// Wired by AppContainer to the derived-data rebuild. Debounced.
    public var onMaterialChange: (@MainActor (_ oldKg: Double, _ newKg: Double) async -> Void)?

    private let healthKitService: any HealthKitServiceProtocol
    private let userPreferencesService: UserPreferencesService
    private let debounce: Duration
    private var cachedHealthKitKg: Double?
    private var rebuildTask: Task<Void, Never>?

    public init(
        healthKitService: any HealthKitServiceProtocol,
        userPreferencesService: UserPreferencesService,
        debounce: Duration = .seconds(2)
    ) {
        self.healthKitService = healthKitService
        self.userPreferencesService = userPreferencesService
        self.debounce = debounce
        let resolved = Self.resolve(healthKit: nil, prefs: userPreferencesService.bodyWeightKg)
        self.current = resolved.0
        self.source = resolved.1
        observePreferences()
    }

    /// Requests HealthKit read/write access (iOS never asked before; only the
    /// Watch did), records that it was asked, then re-resolves.
    public func requestHealthKitAccess() async throws {
        try await healthKitService.requestAuthorization()
        userPreferencesService.hasRequestedHealthKitAuth = true
        await refresh()
    }

    /// Re-reads HealthKit and re-resolves. Call on foreground and after HealthKit authorization.
    public func refresh() async {
        cachedHealthKitKg = await healthKitService.fetchBodyWeightKg()
        lastRefreshedAt = Date()
        applyResolved()
    }

    // MARK: - Private

    private func observePreferences() {
        withObservationTracking {
            _ = userPreferencesService.bodyWeightKg
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyResolved()
                self.observePreferences()
            }
        }
    }

    private func applyResolved() {
        let old = current
        let resolved = Self.resolve(healthKit: cachedHealthKitKg, prefs: userPreferencesService.bodyWeightKg)
        current = resolved.0
        source = resolved.1
        guard abs(current - old) >= Self.materialChangeThresholdKg else { return }
        // Settings typing / repeated foregrounds collapse into one rebuild.
        rebuildTask?.cancel()
        let new = current
        let delay = debounce
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.onMaterialChange?(old, new)
        }
    }

    private static func resolve(healthKit: Double?, prefs: Double?) -> (Double, Source) {
        if let healthKit, healthKit > 0 { return (healthKit, .healthKit) }
        if let prefs, prefs > 0 { return (prefs, .preferences) }
        return (UserPreferencesService.defaultBodyWeightKg, .defaultValue)
    }
}
