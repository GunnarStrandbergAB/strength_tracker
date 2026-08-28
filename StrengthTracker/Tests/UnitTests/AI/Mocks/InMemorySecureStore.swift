import Foundation
@testable import StrengthTrackerShared

/// In-memory SecureStringStore for tests — avoids touching the real keychain.
final class InMemorySecureStore: SecureStringStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func string(forKey key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func setString(_ value: String, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    func removeValue(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}
