#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    let userPreferencesService: UserPreferencesService
    let onStartWorkout: () -> Void
    let onHistoryTapped: () -> Void

    init(
        viewModel: DashboardViewModel,
        userPreferencesService: UserPreferencesService,
        onStartWorkout: @escaping () -> Void,
        onHistoryTapped: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.userPreferencesService = userPreferencesService
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
                        .background(STColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: STColors.primary.opacity(0.25), radius: 12, y: 4)
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
            .background(STColors.background)
            .scrollIndicators(.hidden)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(STColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(preferencesService: userPreferencesService)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundStyle(STColors.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(STColors.surface)
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

#endif
