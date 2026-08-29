import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("AICredentialsService")
@MainActor
struct AICredentialsServiceTests {

    @Test("Loads existing key from the store at init")
    func loadsExistingKey() throws {
        let store = InMemorySecureStore()
        try store.setString("xai-123", forKey: "xaiAPIKey")

        let service = AICredentialsService(store: store)
        #expect(service.xaiAPIKey == "xai-123")
        #expect(service.hasKey)
    }

    @Test("Starts empty when store has no key")
    func startsEmpty() {
        let service = AICredentialsService(store: InMemorySecureStore())
        #expect(service.xaiAPIKey.isEmpty)
        #expect(!service.hasKey)
    }

    @Test("Setting a key persists the trimmed value")
    func persistsTrimmedKey() throws {
        let store = InMemorySecureStore()
        let service = AICredentialsService(store: store)

        service.xaiAPIKey = "  xai-abc \n"
        #expect(try store.string(forKey: "xaiAPIKey") == "xai-abc")
        #expect(service.hasKey)
    }

    @Test("Clearing the key removes it from the store")
    func clearingRemoves() throws {
        let store = InMemorySecureStore()
        try store.setString("xai-123", forKey: "xaiAPIKey")
        let service = AICredentialsService(store: store)

        service.xaiAPIKey = ""
        #expect(try store.string(forKey: "xaiAPIKey") == nil)
        #expect(!service.hasKey)
    }

    @Test("Whitespace-only key counts as no key and removes stored value")
    func whitespaceOnlyKey() throws {
        let store = InMemorySecureStore()
        try store.setString("xai-123", forKey: "xaiAPIKey")
        let service = AICredentialsService(store: store)

        service.xaiAPIKey = "   "
        #expect(!service.hasKey)
        #expect(try store.string(forKey: "xaiAPIKey") == nil)
    }
}

// The real keychain rejects unsigned processes with errSecMissingEntitlement (-34018),
// and this hosted test target builds with CODE_SIGNING_ALLOWED=NO. The signed app has
// implicit access to its own keychain items, so KeychainStore works at runtime;
// AICredentialsService behavior is covered above via InMemorySecureStore.
@Suite("KeychainStore", .disabled("Keychain requires a signed host app; test runs are unsigned (-34018)"))
struct KeychainStoreTests {

    @Test("Round-trips, overwrites, and removes a value")
    func roundTrip() throws {
        let store = KeychainStore(service: "se.gunnarstrandberg.strengthtracker.tests")
        let key = "test-\(UUID().uuidString)"
        defer { try? store.removeValue(forKey: key) }

        #expect(try store.string(forKey: key) == nil)

        try store.setString("first", forKey: key)
        #expect(try store.string(forKey: key) == "first")

        try store.setString("second", forKey: key)
        #expect(try store.string(forKey: key) == "second")

        try store.removeValue(forKey: key)
        #expect(try store.string(forKey: key) == nil)
    }

    @Test("Removing a missing key does not throw")
    func removeMissing() throws {
        let store = KeychainStore(service: "se.gunnarstrandberg.strengthtracker.tests")
        try store.removeValue(forKey: "never-stored-\(UUID().uuidString)")
    }
}
