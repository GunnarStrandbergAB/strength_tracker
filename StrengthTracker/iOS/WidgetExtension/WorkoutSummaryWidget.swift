#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
import StrengthTrackerShared

struct WorkoutSummaryEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct WorkoutSummaryProvider: TimelineProvider {
    private let service = WidgetDataService()

    func placeholder(in context: Context) -> WorkoutSummaryEntry {
        WorkoutSummaryEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutSummaryEntry) -> Void) {
        let data = service.readWidgetData()
        completion(WorkoutSummaryEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutSummaryEntry>) -> Void) {
        let data = service.readWidgetData()
        let entry = WorkoutSummaryEntry(date: Date(), data: data)
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct WorkoutSummaryWidget: Widget {
    let kind = "WorkoutSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutSummaryProvider()) { entry in
            WorkoutSummaryWidgetView(entry: entry)
                .containerBackground(Color(red: 0.071, green: 0.071, blue: 0.071), for: .widget)
        }
        .configurationDisplayName("Last Workout")
        .description("Shows your most recent workout")
        .supportedFamilies([.systemSmall])
    }
}

struct WorkoutSummaryWidgetView: View {
    let entry: WorkoutSummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
                Text("STRENGTH")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
            }

            Spacer()

            if let name = entry.data.lastWorkoutName {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let date = entry.data.lastWorkoutDate {
                    Text(date, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }

                Text("\(entry.data.lastWorkoutExerciseCount) exercises")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            } else {
                Text("No workouts yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.gray)

                Text("Start your first!")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.949, green: 0.800, blue: 0.051))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "strengthtracker://workout"))
    }
}
#endif
