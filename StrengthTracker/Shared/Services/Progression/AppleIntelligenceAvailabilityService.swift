import Foundation

/// C3: Runtime check for FoundationModels availability with graceful fallback.
/// Routes coaching communication to either Apple Intelligence or static providers.
public struct AppleIntelligenceAvailabilityService: Sendable {

    public init() {}

    /// Whether FoundationModels (on-device Apple Intelligence) is available at runtime.
    public var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return true
        }
        return false
        #else
        return false
        #endif
    }
}
