#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

#if canImport(Charts)
import Charts
#endif

struct ExerciseProgressChart: View {
    let data: [(date: Date, weight: Double, reps: Int)]

    var body: some View {
        if data.isEmpty {
            ContentUnavailableView(
                "No Data",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Complete some sets to see your progress.")
            )
        } else {
            chartContent
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        #if canImport(Charts)
        chartsView
        #else
        fallbackListView
        #endif
    }

    #if canImport(Charts)
    @ViewBuilder
    private var chartsView: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", entry.weight)
                )
                .foregroundStyle(Color.blue)

                PointMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", entry.weight)
                )
                .foregroundStyle(Color.blue)
            }
        }
        .chartYAxisLabel("Weight (kg)")
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                AxisGridLine()
            }
        }
        .frame(height: 220)
        .padding()
    }
    #endif

    private var fallbackListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weight Progression")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(Array(data.enumerated()), id: \.offset) { _, entry in
                HStack {
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f kg", entry.weight))
                        .monospacedDigit()
                    Text("\u{00D7} \(entry.reps)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

#endif
