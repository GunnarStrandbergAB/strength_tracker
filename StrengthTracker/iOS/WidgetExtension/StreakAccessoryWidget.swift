#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
import StrengthTrackerShared

struct StreakEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct StreakProvider: TimelineProvider {
    private let service = WidgetDataService()

    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: Date(), data: service.readWidgetData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let data = service.readWidgetData()
        let entry = StreakEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

@available(iOS 16.1, *)
struct StreakAccessoryWidget: Widget {
    let kind = "StreakAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakAccessoryView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Weeks in a row with a workout")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@available(iOS 16.1, *)
struct StreakAccessoryView: View {
    let entry: StreakEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                Text("\(entry.data.currentStreak)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20))
            VStack(alignment: .leading) {
                Text("\(entry.data.currentStreak)-week streak")
                    .font(.headline)
                Text("\(entry.data.weeklyWorkoutCount)/\(entry.data.weeklyGoal) this week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
