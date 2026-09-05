import Foundation

/// A record of what a direct-write AI tool changed, shown as a compact card in
/// the chat. Strings are pre-formatted in the user's display unit at write time
/// so the card is a frozen record and needs no unit logic.
public struct AIReceipt: Codable, Sendable, Equatable {
    public enum Scope: String, Codable, Sendable {
        case activeWorkout
        case historyWorkout
        case session
    }

    public struct Section: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        /// SF Symbol name, e.g. "checkmark.circle.fill".
        public var symbol: String
        /// e.g. "Bench Press · set 2"
        public var title: String
        /// e.g. ["85 kg × 8", "RPE 9 · to failure"]
        public var lines: [String]

        public init(id: UUID = UUID(), symbol: String, title: String, lines: [String]) {
            self.id = id
            self.symbol = symbol
            self.title = title
            self.lines = lines
        }
    }

    public var scope: Scope
    /// The workout the sections belong to; consecutive receipts for the same
    /// workout merge into one card. nil for session-level receipts.
    public var workoutID: UUID?
    /// e.g. "Active workout · Push Day" or "Push Day · Sep 3"
    public var headline: String
    public var sections: [Section]

    public init(scope: Scope, workoutID: UUID?, headline: String, sections: [Section]) {
        self.scope = scope
        self.workoutID = workoutID
        self.headline = headline
        self.sections = sections
    }

    /// Whether `other` should be folded into this card rather than start a new one.
    public func canMerge(_ other: AIReceipt) -> Bool {
        scope == other.scope && workoutID == other.workoutID
    }

    public mutating func merge(_ other: AIReceipt) {
        sections.append(contentsOf: other.sections)
        headline = other.headline
    }
}
