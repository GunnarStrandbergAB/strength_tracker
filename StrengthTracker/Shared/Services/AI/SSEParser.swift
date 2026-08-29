import Foundation

/// One server-sent event: an optional event name and the data payload.
public struct SSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

/// Line-based SSE parser suited to `URLSession.AsyncBytes.lines` (which strips
/// newlines and skips blank lines). Each `data:` line is treated as a complete
/// event payload — true for the OpenAI/xAI streaming format where every data
/// line carries one full JSON object. Comment lines (`: keep-alive`) are ignored.
public struct SSEParser: Sendable {
    private var pendingEventName: String?

    public init() {}

    /// Feed one line; returns a complete event when the line carried data.
    public mutating func parse(line: String) -> SSEEvent? {
        if line.hasPrefix("data:") {
            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let event = SSEEvent(event: pendingEventName, data: data)
            pendingEventName = nil
            return event
        }
        if line.hasPrefix("event:") {
            pendingEventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        // Comments (":..."), ids, retry hints, and anything unknown are skipped.
        return nil
    }
}
