import Foundation
import Observation

@MainActor
@Observable
public final class ProFeatureGate {

    public let storeService: StoreService

    public init(storeService: StoreService) {
        self.storeService = storeService
    }

    /// Single source of truth: user has Pro access if they're a subscriber OR running in beta/debug.
    public var hasProAccess: Bool {
        Self.isBeta || storeService.isProUser
    }

    /// Beta bypass: DEBUG builds always unlock, release builds unlock for TestFlight (sandbox receipt).
    public static var isBeta: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
