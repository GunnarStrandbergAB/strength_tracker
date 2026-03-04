#if canImport(SwiftUI)
import SwiftUI
import StoreKit
import StrengthTrackerShared

struct ProUpgradeView: View {
    let storeService: StoreService
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(STColors.primary)

                        Text("HellBentIron Pro")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(STColors.textPrimary)

                        Text("Unlock your full potential")
                            .font(.system(size: 15))
                            .foregroundStyle(STColors.textSecondary)
                    }
                    .padding(.top, 24)

                    // Features list
                    VStack(alignment: .leading, spacing: 14) {
                        featureRow(icon: "chart.line.uptrend.xyaxis", title: "Progression Planning", detail: "Periodized programming with auto-progression")
                        featureRow(icon: "waveform.path.ecg", title: "Training Load Tracking", detail: "ACWR, volume landmarks, and overload detection")
                        featureRow(icon: "brain.head.profile", title: "Advanced Insights", detail: "Drift analysis, phase detection, anomalies")
                        featureRow(icon: "chart.bar.fill", title: "Quality Scores", detail: "Rate every workout on volume, intensity, balance")
                        featureRow(icon: "arrow.triangle.branch", title: "Plateau Detection", detail: "Spot stalled exercises and get recommendations")
                        featureRow(icon: "figure.walk", title: "Recovery Timeline", detail: "Optimal rest days between sessions")
                    }
                    .padding(.horizontal, 20)

                    // Product options
                    if storeService.products.isEmpty {
                        ProgressView()
                            .tint(STColors.primary)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(storeService.products, id: \.id) { product in
                                productCard(product)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Error
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(STColors.danger)
                            .padding(.horizontal, 20)
                    }

                    // Restore
                    Button {
                        Task {
                            await storeService.restorePurchases()
                            if storeService.isProUser {
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Restore Purchases")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(STColors.textSecondary)
                    }

                    // Auto-renewal disclosure
                    Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple ID account. Manage subscriptions in Settings \u{203A} Apple ID \u{203A} Subscriptions.")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    // Legal links
                    HStack(spacing: 16) {
                        Link("Terms of Service", destination: URL(string: "https://hellbentiron.com/terms")!)
                        Link("Privacy Policy", destination: URL(string: "https://hellbentiron.com/privacy")!)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textTertiary)
                    .padding(.bottom, 24)
                }
            }
            .background(STColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .stNavigationBarStyle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(STColors.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(STColors.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(STColors.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textSecondary)
            }
        }
    }

    private func productCard(_ product: Product) -> some View {
        Button {
            guard !isPurchasing else { return }
            isPurchasing = true
            errorMessage = nil
            Task {
                do {
                    let purchased = try await storeService.purchase(product)
                    if purchased {
                        dismiss()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
                isPurchasing = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(STColors.textPrimary)

                    if let subscription = product.subscription {
                        Text(periodLabel(subscription.subscriptionPeriod))
                            .font(.system(size: 12))
                            .foregroundStyle(STColors.textSecondary)
                    }
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(STColors.primary)
            }
            .padding(16)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(isYearly(product) ? STColors.primary.opacity(0.5) : STColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
        .opacity(isPurchasing ? 0.6 : 1)
    }

    private func periodLabel(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .month: return period.value == 1 ? "Monthly" : "\(period.value) months"
        case .year: return period.value == 1 ? "Yearly" : "\(period.value) years"
        case .week: return period.value == 1 ? "Weekly" : "\(period.value) weeks"
        case .day: return period.value == 1 ? "Daily" : "\(period.value) days"
        @unknown default: return ""
        }
    }

    private func isYearly(_ product: Product) -> Bool {
        product.id.contains("yearly")
    }
}
#endif
