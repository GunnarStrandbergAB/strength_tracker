#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    let onStartWorkout: () -> Void
    let onHistoryTapped: () -> Void

    init(
        viewModel: DashboardViewModel,
        onStartWorkout: @escaping () -> Void,
        onHistoryTapped: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onStartWorkout = onStartWorkout
        self.onHistoryTapped = onHistoryTapped
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Weekly Frequency Chart
                    WeeklyFrequencyChart(
                        weeklyWorkoutCounts: viewModel.weeklyWorkoutCounts,
                        totalWorkouts: viewModel.weeklyWorkoutTotal,
                        trend: viewModel.weeklyTrend,
                        trendIsPositive: viewModel.trendIsPositive(),
                        formattedTrend: viewModel.formattedTrend()
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Start Workout Button
                    Button(action: onStartWorkout) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))

                            Text("START EMPTY WORKOUT")
                                .font(.system(size: 15, weight: .bold))
                                .tracking(0.8)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(DashboardColors.primaryBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: DashboardColors.primaryBlue.opacity(0.25), radius: 12, y: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)

                    // Stats Carousel
                    StatsCarouselView(
                        formattedVolume: viewModel.formattedVolume(),
                        formattedDuration: viewModel.formattedDuration(),
                        prsCount: viewModel.prsThisWeek
                    )

                    // Recent Workouts
                    RecentWorkoutsWidget(
                        workouts: viewModel.recentWorkouts,
                        viewModel: viewModel,
                        onHistoryTapped: onHistoryTapped
                    )
                    .padding(.top, 4)

                    // Bottom spacer for tab bar
                    Spacer()
                        .frame(height: 20)
                }
            }
            .background(DashboardColors.background)
            .scrollIndicators(.hidden)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DashboardColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsPlaceholderView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundStyle(DashboardColors.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(DashboardColors.statCardBackground)
                            .clipShape(Circle())
                    }
                }
            }
            .task {
                await viewModel.loadDashboard()
            }
            .refreshable {
                await viewModel.loadDashboard()
            }
        }
    }
}

// MARK: - Settings placeholder for navigation from Dashboard gear icon

private struct SettingsPlaceholderView: View {
    var body: some View {
        Text("Settings")
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DashboardColors.background)
    }
}

// MARK: - Dashboard Color Palette

enum DashboardColors {
    static let background = Color(hex: "0B0F1A")
    static let card = Color(hex: "161E2E")
    static let statCardBackground = Color(hex: "1E293B").opacity(0.5)
    static let primaryBlue = Color(hex: "3B82F6")
    static let accentBlue = Color(hex: "2563EB")
    static let barBackground = Color(hex: "334155").opacity(0.5)
    static let textSecondary = Color(hex: "94A3B8")
    static let textTertiary = Color(hex: "64748B")
    static let trendPositive = Color(hex: "34D399")
    static let trendNegative = Color(hex: "EF4444")
}

#endif
