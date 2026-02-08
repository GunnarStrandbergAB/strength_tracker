#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
import StrengthTrackerShared

struct WeeklyProgressEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct WeeklyProgressProvider: TimelineProvider {
    private let service = WidgetDataService()

    func placeholder(in context: Context) -> WeeklyProgressEntry {
        WeeklyProgressEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyProgressEntry) -> Void) {
        let data = service.readWidgetData()
        completion(WeeklyProgressEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyProgressEntry>) -> Void) {
        let data = service.readWidgetData()
        let entry = WeeklyProgressEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct WeeklyProgressWidget: Widget {
    let kind = "WeeklyProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyProgressProvider()) { entry in
            WeeklyProgressWidgetView(entry: entry)
                .containerBackground(Color(red: 0.071, green: 0.071, blue: 0.071), for: .widget)
        }
        .configurationDisplayName("Weekly Progress")
        .description("Track your weekly workout goal")
        .supportedFamilies([.systemMedium])
    }
}

struct WeeklyProgressWidgetView: View {
    let entry: WeeklyProgressEntry

    private var progress: Double {
        guard entry.data.weeklyGoal > 0 else { return 0 }
        return min(Double(entry.data.weeklyWorkoutCount) / Double(entry.data.weeklyGoal), 1.0)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color(red: 0.949, green: 0.800, blue: 0.051),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(entry.data.weeklyWorkoutCount)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("/\(entry.data.weeklyGoal)")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: 80, height: 80)

            // Stats
            VStack(alignment: .leading, spacing: 8) {
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))

                statRow(icon: "flame.fill", label: "Streak", value: "\(entry.data.currentStreak) days", color: .orange)
                statRow(icon: "trophy.fill", label: "Total", value: "\(entry.data.totalWorkoutsAllTime)", color: .yellow)

                if let last = entry.data.lastWorkoutDate {
                    statRow(icon: "clock", label: "Last", value: last.formatted(.relative(presentation: .named)), color: .gray)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "strengthtracker://dashboard"))
    }

    private func statRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
#endif
