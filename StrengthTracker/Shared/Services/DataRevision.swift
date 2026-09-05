import Foundation
import Observation

/// The single cross-ViewModel refresh signal. A monotonically increasing counter
/// bumped by `WorkoutFinalizer` exactly once per completed mutation pipeline
/// (finish, edit, delete, rebuild) — after derived data (vectors, PRs, caches)
/// is consistent and before widgets are republished.
///
/// Views re-run their loads with `.task(id: revision.value)`; ViewModels keep a
/// `lastLoadedRevision` so duplicate triggers are no-ops; the analytics service
/// keys its insights cache on it.
@MainActor
@Observable
public final class DataRevision {
    public private(set) var value: Int = 0

    public init() {}

    public func bump() {
        value &+= 1
    }
}
