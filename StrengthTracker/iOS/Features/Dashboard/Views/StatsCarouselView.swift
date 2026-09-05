#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct StatsCarouselView: View {
    let formattedVolume: String
    var volumeUnit: String = "KG"
    let formattedAvgSessions: String
    let formattedDuration: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatCard(
                    icon: "scalemass",
                    label: "LIFETIME VOLUME",
                    value: formattedVolume,
                    unit: volumeUnit
                )

                StatCard(
                    icon: "calendar.badge.clock",
                    label: "AVG / WEEK",
                    value: formattedAvgSessions,
                    unit: nil
                )

                StatCard(
                    icon: "timer",
                    label: "TRAINING TIME",
                    value: formattedDuration,
                    unit: "HRS"
                )
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(STColors.primary)
                .padding(.bottom, 2)

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(STColors.textSecondary)
                .tracking(0.3)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(STColors.textTertiary)
                }
            }
            .padding(.top, 2)
        }
        .frame(minWidth: 130, alignment: .leading)
        .padding(16)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

#endif
