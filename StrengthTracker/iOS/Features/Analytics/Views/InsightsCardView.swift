#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Compact analytics card for the Dashboard — shows top insights with navigation to full analytics.
struct InsightsCardView: View {
    let viewModel: WorkoutAnalyticsViewModel
    var storeService: StoreService? = nil
    @State private var showUpgradeSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INSIGHTS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(STColors.textSecondary)

                Spacer()

                if viewModel.hasProAccess {
                    NavigationLink {
                        AnalyticsDashboardView(viewModel: viewModel)
                    } label: {
                        Text("View All")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(STColors.primary)
                    }
                }
            }

            if !viewModel.hasProAccess {
                // No Pro — show locked card
                lockedAnalyticsView
            } else if viewModel.isInsightsLoading || viewModel.isMigrating {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(STColors.primary)
                    Text(viewModel.isMigrating ? "Analyzing workout history..." : "Loading insights...")
                        .font(.system(size: 13))
                        .foregroundStyle(STColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if !viewModel.isFeatureUnlocked(.qualityScore) {
                // Not enough data — show unlock progress
                unlockProgressView
            } else {
                insightsContent
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .sheet(isPresented: $showUpgradeSheet) {
            if let storeService {
                ProUpgradeView(storeService: storeService)
            }
        }
    }

    private var lockedAnalyticsView: some View {
        Button {
            showUpgradeSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Unlock Analytics")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(STColors.textPrimary)

                        Text("PRO")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(STColors.background)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(STColors.primary)
                            .clipShape(Capsule())
                    }
                    Text("Plateaus, muscle balance, quality scores & more")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textSecondary)
                }

                Spacer()

                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.primary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var insightsContent: some View {
        let insights = viewModel.insights

        // The one load/deload call, shared with every other screen
        if let verdict = insights.verdict {
            VerdictBanner(verdict: verdict, style: .inline)
        }

        // Plateau warnings (the Analytics screen lists them all)
        if !insights.plateaus.isEmpty {
            let top = insights.plateaus.prefix(1)
            ForEach(Array(top)) { plateau in
                insightRow(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: STColors.warning,
                    title: plateau.exerciseName ?? "Exercise",
                    detail: AnalyticsFormatting.weeksStalled(plateau.consecutiveWeeksStalled)
                )
            }
        }

        // Muscle imbalance warnings
        if let balance = insights.muscleBalance, !balance.imbalances.isEmpty {
            let top = balance.imbalances.filter { $0.severity != .mild }.prefix(1)
            ForEach(Array(top)) { imbalance in
                insightRow(
                    icon: "arrow.left.arrow.right",
                    iconColor: AnalyticsColors.severity(imbalance.severity),
                    title: "\(imbalance.primaryGroup) / \(imbalance.comparisonGroup)",
                    detail: "\(AnalyticsFormatting.ratio(imbalance.ratio)) ratio"
                )
            }
        }

        // Recommendations
        if !insights.recommendations.isEmpty && insights.plateaus.isEmpty {
            let rec = insights.recommendations[0]
            insightRow(
                icon: "lightbulb.fill",
                iconColor: STColors.primary,
                title: rec.exerciseName,
                detail: rec.reason.displayText(targetMuscleGroup: rec.targetMuscleGroup)
            )
        }

        // (The top highlight used to be repeated here; below 19 workouts it is built
        // from the same plateau/imbalance data as the rows above, so it duplicated them.)

        // Fallback: show workout count if nothing notable
        if insights.plateaus.isEmpty && (insights.muscleBalance?.imbalances.isEmpty ?? true) && insights.recommendations.isEmpty {
            insightRow(
                icon: "checkmark.circle.fill",
                iconColor: STColors.success,
                title: "On Track",
                detail: "\(insights.workoutCount) workouts analyzed"
            )
        }
    }

    private func insightRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(STColors.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(STColors.textSecondary)
            }

            Spacer()
        }
    }

    private var unlockProgressView: some View {
        VStack(spacing: 8) {
            if let unlock = viewModel.nextFeatureUnlock {
                let total = unlock.workoutsNeeded + viewModel.insights.workoutCount
                let current = viewModel.insights.workoutCount

                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textTertiary)

                    Text("Complete \(unlock.workoutsNeeded) more workout\(unlock.workoutsNeeded == 1 ? "" : "s") to unlock \(viewModel.featureDisplayName(unlock.feature))")
                        .font(.system(size: 12))
                        .foregroundStyle(STColors.textSecondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(STColors.background)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(STColors.primary)
                            .frame(width: geo.size.width * CGFloat(current) / CGFloat(max(total, 1)), height: 6)
                    }
                }
                .frame(height: 6)
            } else {
                Text("Complete workouts to unlock insights")
                    .font(.system(size: 12))
                    .foregroundStyle(STColors.textSecondary)
            }
        }
    }
}

// MARK: - RecommendationReason Display

extension RecommendationReason {
    var displayText: String {
        displayText(targetMuscleGroup: nil)
    }

    func displayText(targetMuscleGroup: String?) -> String {
        switch self {
        case .similarToFavorites: return "Similar to your favorites"
        case .fillsMuscleGap:
            if let muscle = targetMuscleGroup {
                return "Fills a gap in \(muscle.capitalized)"
            }
            return "Fills a muscle group gap"
        case .plateauBreaker: return "May help break plateau"
        case .recoveryAppropriate: return "Good for active recovery"
        }
    }
}

#endif
