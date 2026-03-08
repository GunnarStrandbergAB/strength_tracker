import WidgetKit
import SwiftUI
import StrengthTrackerShared

// MARK: - Timeline Entry

struct WatchRestTimerEntry: TimelineEntry {
    let date: Date
    let state: WatchRestTimerState?
    let relevance: TimelineEntryRelevance?
}

// MARK: - Timeline Provider

struct WatchRestTimerProvider: TimelineProvider {
    private static let appGroupId = "group.se.gunnarstrandberg.hellbent.shared"

    func placeholder(in context: Context) -> WatchRestTimerEntry {
        WatchRestTimerEntry(
            date: .now,
            state: WatchRestTimerState(
                exerciseName: "Bench Press",
                setNumber: 3,
                startDate: .now,
                endDate: .now.addingTimeInterval(90),
                totalSeconds: 90
            ),
            relevance: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchRestTimerEntry) -> Void) {
        let entry = WatchRestTimerEntry(
            date: .now,
            state: WatchRestTimerState(
                exerciseName: "Bench Press",
                setNumber: 3,
                startDate: .now,
                endDate: .now.addingTimeInterval(90),
                totalSeconds: 90
            ),
            relevance: TimelineEntryRelevance(score: 100)
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchRestTimerEntry>) -> Void) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupId),
              let data = defaults.data(forKey: WatchRestTimerState.userDefaultsKey),
              let timerState = try? JSONDecoder().decode(WatchRestTimerState.self, from: data) else {
            // No active timer — low relevance idle entry, check again in 5 minutes
            let entry = WatchRestTimerEntry(date: .now, state: nil, relevance: TimelineEntryRelevance(score: 0))
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(300))))
            return
        }

        let now = Date()

        if timerState.endDate > now {
            // Timer is active — high relevance to surface in Smart Stack
            let activeEntry = WatchRestTimerEntry(
                date: now,
                state: timerState,
                relevance: TimelineEntryRelevance(score: 100)
            )

            // At expiry, show "done" state
            let doneEntry = WatchRestTimerEntry(
                date: timerState.endDate,
                state: timerState,
                relevance: TimelineEntryRelevance(score: 50)
            )

            // 3 seconds after expiry, clear
            let clearEntry = WatchRestTimerEntry(
                date: timerState.endDate.addingTimeInterval(3),
                state: nil,
                relevance: TimelineEntryRelevance(score: 0)
            )

            completion(Timeline(entries: [activeEntry, doneEntry, clearEntry], policy: .after(timerState.endDate.addingTimeInterval(5))))
        } else {
            // Timer already expired — clear
            let entry = WatchRestTimerEntry(date: now, state: nil, relevance: TimelineEntryRelevance(score: 0))
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(300))))
        }
    }
}

// MARK: - Widget View

struct WatchRestTimerWidgetView: View {
    let entry: WatchRestTimerEntry
    private static let accentColor = Color(red: 0.949, green: 0.800, blue: 0.051)

    var body: some View {
        if let state = entry.state {
            let isExpired = state.endDate <= entry.date
            HStack {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                            .frame(width: 24, height: 24)

                        if !isExpired {
                            ProgressView(
                                timerInterval: state.startDate...state.endDate,
                                countsDown: true
                            )
                            .progressViewStyle(.circular)
                            .tint(Self.accentColor)
                            .frame(width: 24, height: 24)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isExpired ? "DONE" : "RESTING")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text(state.exerciseName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isExpired {
                    Text("00:00")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Self.accentColor)
                } else {
                    Text(timerInterval: state.startDate...state.endDate, countsDown: true)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Self.accentColor)
                }
            }
            .padding(10)
            .widgetURL(URL(string: "strengthtracker://workout"))
        } else {
            // No active timer — empty placeholder
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("No rest timer")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }
}

// MARK: - Widget Configuration

struct WatchRestTimerWidget: Widget {
    let kind = "WatchRestTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchRestTimerProvider()) { entry in
            WatchRestTimerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .supportedFamilies([.accessoryRectangular])
        .configurationDisplayName("Rest Timer")
        .description("Shows rest timer countdown during workouts.")
    }
}
