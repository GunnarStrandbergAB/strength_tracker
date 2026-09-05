#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// The one visual for the shared coach verdict. Every screen that talks about
/// deloads or load direction shows this instead of its own phrasing.
struct VerdictBanner: View {
    enum Style {
        case card    // standalone card with surface background
        case inline  // row inside another card
    }

    let verdict: TrainingVerdict
    var style: Style = .card
    var showReasons: Bool = false
    /// Small uppercase label above the headline, e.g. "COACH VERDICT" or "NEXT SESSION".
    var kicker: String? = nil

    var body: some View {
        switch style {
        case .card:
            content
                .padding(STSpacing.cardPadding)
                .background(STColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: STRadius.card)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                )
        case .inline:
            content
                .padding(10)
                .background(tint.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: STRadius.input))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let kicker {
                Text(kicker.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(STColors.textSecondary)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: style == .card ? 18 : 14))
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verdict.headline)
                        .font(.system(size: style == .card ? 15 : 13, weight: .semibold))
                        .foregroundStyle(STColors.textPrimary)
                    Text(verdict.action)
                        .font(.system(size: style == .card ? 12 : 11))
                        .foregroundStyle(STColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if showReasons, !verdict.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(verdict.reasons.prefix(4).enumerated()), id: \.offset) { _, reason in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(tint)
                                .frame(width: 4, height: 4)
                                .padding(.top, 5)
                            Text(reason)
                                .font(.system(size: 11))
                                .foregroundStyle(STColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 34)
            }
        }
    }

    private var tint: Color { AnalyticsColors.verdict(verdict) }

    private var icon: String {
        if verdict.isActiveDeload { return "leaf.fill" }
        switch verdict.kind {
        case .deload: return "exclamationmark.shield.fill"
        case .hold: return "pause.circle.fill"
        case .progress: return "arrow.up.right.circle.fill"
        }
    }
}
#endif
