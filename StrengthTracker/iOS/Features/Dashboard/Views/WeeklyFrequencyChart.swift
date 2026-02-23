#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct WeeklyFrequencyChart: View {
    let weeklyQualityScores: [Double?]
    let totalWorkouts: Int
    let trend: Double
    let trendIsPositive: Bool
    let formattedTrend: String

    private let dayLabels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: title + trend badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEKLY QUALITY")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(STColors.textSecondary)
                        .tracking(0.8)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(totalWorkouts)")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)

                        Text("WORKOUTS")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(STColors.textTertiary)
                    }
                }

                Spacer()

                if trend != 0 {
                    TrendBadge(
                        value: formattedTrend,
                        isPositive: trendIsPositive
                    )
                }
            }
            .padding(.bottom, 20)

            // Bar chart
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 8) {
                        BarView(qualityScore: weeklyQualityScores[index])
                            .frame(height: 96)

                        Text(dayLabels[index])
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(STColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Bar View

private struct BarView: View {
    let qualityScore: Double?

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height

            ZStack(alignment: .bottom) {
                // Background bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(STColors.border.opacity(0.5))
                    .frame(height: totalHeight)

                // Filled portion based on quality score (0-100)
                if let score = qualityScore {
                    let fillFraction = CGFloat(min(max(score, 0), 100)) / 100.0
                    let minFillHeight: CGFloat = 8

                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(for: score))
                        .frame(height: max(totalHeight * fillFraction, minFillHeight))
                }
            }
        }
    }

    private func barColor(for score: Double) -> Color {
        switch score {
        case 80...:   return STColors.success   // green — excellent
        case 60..<80: return STColors.primary   // gold — good
        case 40..<60: return .orange            // needs work
        default:      return STColors.danger    // red — poor
        }
    }
}

// MARK: - Trend Badge

private struct TrendBadge: View {
    let value: String
    let isPositive: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 11, weight: .bold))

            Text(value)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(isPositive ? STColors.success : STColors.danger)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            (isPositive ? STColors.success : STColors.danger)
                .opacity(0.12)
        )
        .clipShape(Capsule())
    }
}

#endif
