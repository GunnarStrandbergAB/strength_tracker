import Foundation
import Observation

/// Holds the user's xAI API key, backed by the keychain. Loaded once at init;
/// writes go through on every change so SwiftUI can bind a SecureField directly.
@MainActor
@Observable
public final class AICredentialsService {

    private static let xaiKeyName = "xaiAPIKey"

    private let store: SecureStringStore

    /// The xAI API key. Empty string means no key; setting to empty deletes it from the store.
    public var xaiAPIKey: String {
        didSet {
            let trimmed = xaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try? store.removeValue(forKey: Self.xaiKeyName)
            } else {
                try? store.setString(trimmed, forKey: Self.xaiKeyName)
            }
        }
    }

    public var hasKey: Bool {
        !xaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(store: SecureStringStore = KeychainStore()) {
        self.store = store
        self.xaiAPIKey = (try? store.string(forKey: Self.xaiKeyName)) ?? ""
    }
}
