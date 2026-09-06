#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
import StrengthTrackerShared

// MARK: - Timeline Entry

struct TrainingHubEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    let highlightIndex: Int
    var measuredQuality: Double? { data.measuredQuality(at: date) }
    var visibleHighlights: [WidgetHighlight] { data.visibleHighlights(at: date) }
}

// MARK: - Timeline Provider

struct TrainingHubProvider: TimelineProvider {
    private let service = WidgetDataService()

    func placeholder(in context: Context) -> TrainingHubEntry {
        TrainingHubEntry(date: Date(), data: .empty, highlightIndex: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainingHubEntry) -> Void) {
        let data = service.readWidgetData()
        completion(TrainingHubEntry(date: Date(), data: data, highlightIndex: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingHubEntry>) -> Void) {
        let data = service.readWidgetData()

        if data.activeWorkout != nil {
            // During workout: single entry, refresh quickly
            let entry = TrainingHubEntry(date: Date(), data: data, highlightIndex: 0)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        } else {
            // Analytics mode: rotate highlights every 30 min
            var entries: [TrainingHubEntry] = []
            let highlightCount = max(data.highlights.count, 1)
            let now = Date()

            for i in 0..<max(highlightCount, 1) {
                let entryDate = Calendar.current.date(byAdding: .minute, value: 30 * i, to: now) ?? now
                entries.append(TrainingHubEntry(
                    date: entryDate,
                    data: data,
                    highlightIndex: i % highlightCount
                ))
            }

            let nextUpdate = Calendar.current.date(
                byAdding: .minute, value: 30 * max(highlightCount, 1), to: now
            ) ?? now
            // An explicit expiry entry removes advice even if the system delays the next reload.
            let expiries = data.highlights.compactMap(\.validUntil) + [data.analyticsGeneratedAt?.addingTimeInterval(6 * 3600)].compactMap { $0 }
            for expiry in Set(expiries) where expiry > now {
                entries.append(TrainingHubEntry(date: expiry, data: data, highlightIndex: 0))
            }
            entries.sort { $0.date < $1.date }
            let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}

// MARK: - Widget Definition

struct TrainingHubWidget: Widget {
    let kind = "TrainingHubWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingHubProvider()) { entry in
            TrainingHubWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("Training Hub")
        .description("Adaptive dashboard: analytics at rest, workout controls during sessions")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root View

struct TrainingHubWidgetView: View {
    let entry: TrainingHubEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.data.activeWorkout != nil {
            activeWorkoutView
        } else {
            analyticsView
        }
    }

    @ViewBuilder
    private var analyticsView: some View {
        switch family {
        case .systemSmall:
            AnalyticsSmallView(entry: entry)
        case .systemMedium:
            AnalyticsMediumView(entry: entry)
        case .systemLarge:
            AnalyticsLargeView(entry: entry)
        default:
            AnalyticsSmallView(entry: entry)
        }
    }

    @ViewBuilder
    private var activeWorkoutView: some View {
        switch family {
        case .systemSmall:
            ActiveWorkoutSmallView(entry: entry)
        case .systemMedium:
            ActiveWorkoutMediumView(entry: entry)
        case .systemLarge:
            ActiveWorkoutLargeView(entry: entry)
        default:
            ActiveWorkoutSmallView(entry: entry)
        }
    }
}
#endif
