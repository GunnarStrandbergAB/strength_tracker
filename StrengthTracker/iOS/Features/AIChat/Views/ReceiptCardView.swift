#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Compact card listing what a direct-write AI tool changed. Purely
/// presentational: every string was formatted at write time.
struct ReceiptCardView: View {
    let receipt: AIReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: headerSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(STColors.primary)
                Text(receipt.headline)
                    .font(.stLabel)
                    .foregroundStyle(STColors.textSecondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Spacer()
            }

            ForEach(receipt.sections) { section in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: section.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(STColors.success)
                        .frame(width: 18)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.stBody)
                            .foregroundStyle(STColors.textPrimary)
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.stCaption)
                                .foregroundStyle(STColors.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.card)
                .strokeBorder(STColors.border, lineWidth: 1)
        )
    }

    private var headerSymbol: String {
        switch receipt.scope {
        case .activeWorkout: return "figure.strengthtraining.traditional"
        case .historyWorkout: return "clock.arrow.circlepath"
        case .session: return "play.circle"
        }
    }
}
#endif
