#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    let analyticsViewModel: WorkoutAnalyticsViewModel
    let historyViewModel: HistoryViewModel
    let progressionPlanViewModel: ProgressionPlanViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let templateViewModel: TemplateViewModel
    let userPreferencesService: UserPreferencesService
    let connectivityManager: ConnectivityManager?
    var proFeatureGate: ProFeatureGate? = nil
    var storeService: StoreService? = nil
    let onStartWorkout: () -> Void
    let onStartSession: (WorkoutTemplate, UUID, UUID, Bool) async -> Void
    let onHistoryTapped: () -> Void

    init(
        viewModel: DashboardViewModel,
        analyticsViewModel: WorkoutAnalyticsViewModel,
        historyViewModel: HistoryViewModel,
        progressionPlanViewModel: ProgressionPlanViewModel,
        exerciseListViewModel: ExerciseListViewModel,
        templateViewModel: TemplateViewModel,
        userPreferencesService: UserPreferencesService,
        connectivityManager: ConnectivityManager? = nil,
        proFeatureGate: ProFeatureGate? = nil,
        storeService: StoreService? = nil,
        onStartWorkout: @escaping () -> Void,
        onStartSession: @escaping (WorkoutTemplate, UUID, UUID, Bool) async -> Void,
        onHistoryTapped: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.analyticsViewModel = analyticsViewModel
        self.historyViewModel = historyViewModel
        self.progressionPlanViewModel = progressionPlanViewModel
        self.exerciseListViewModel = exerciseListViewModel
        self.templateViewModel = templateViewModel
        self.userPreferencesService = userPreferencesService
        self.connectivityManager = connectivityManager
        self.proFeatureGate = proFeatureGate
        self.storeService = storeService
        self.onStartWorkout = onStartWorkout
        self.onStartSession = onStartSession
        self.onHistoryTapped = onHistoryTapped
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Greeting
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(STColors.textPrimary)
                        Text(motivationalSubtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(STColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    // Weekly Frequency Chart
                    WeeklyFrequencyChart(
                        weeklyQualityScores: viewModel.weeklyQualityScores,
                        totalWorkouts: viewModel.weeklyWorkoutTotal,
                        trend: viewModel.weeklyTrend,
                        trendIsPositive: viewModel.trendIsPositive(),
                        formattedTrend: viewModel.formattedTrend()
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Progression Plan Card
                    ProgressionPlanCardView(
                        viewModel: progressionPlanViewModel,
                        exerciseListViewModel: exerciseListViewModel,
                        templateViewModel: templateViewModel,
                        proFeatureGate: proFeatureGate,
                        storeService: storeService,
                        onStartSession: onStartSession
                    )
                    .padding(.horizontal, 20)

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

                    // Weekly Digest (M5) — show Mon-Wed when prior week data is fresh
                    if let digest = analyticsViewModel.weeklyDigest {
                        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
                        let isMondayToWednesday = (2...4).contains(dayOfWeek)
                        if isMondayToWednesday {
                            WeeklyDigestCard(digest: digest)
                                .padding(.horizontal, 20)
                        }
                    }

                    // Stats Carousel
                    StatsCarouselView(
                        formattedVolume: viewModel.formattedVolume(),
                        volumeUnit: viewModel.weightUnit.symbol.uppercased(),
                        formattedAvgSessions: viewModel.formattedAvgSessions(),
                        formattedDuration: viewModel.formattedDuration()
                    )

                    // Analytics Insights Card (hidden until close to first unlock)
                    if analyticsViewModel.insights.workoutCount >= 3 || !analyticsViewModel.hasProAccess {
                        InsightsCardView(viewModel: analyticsViewModel, storeService: storeService)
                            .padding(.horizontal, 20)
                    }

                    // Recent Workouts
                    RecentWorkoutsWidget(
                        workouts: viewModel.recentWorkouts,
                        viewModel: viewModel,
                        historyViewModel: historyViewModel,
                        analyticsViewModel: analyticsViewModel,
                        recentWorkoutScores: viewModel.recentWorkoutScores,
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
            .stNavigationBarStyle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(preferencesService: userPreferencesService, connectivityManager: connectivityManager, proFeatureGate: proFeatureGate, storeService: storeService)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundStyle(STColors.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(STColors.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .task {
                async let d: () = viewModel.loadDashboard()
                async let a: () = analyticsViewModel.loadDashboardInsights()
                async let p: () = progressionPlanViewModel.loadActivePlan()
                _ = await (d, a, p)
            }
            .refreshable {
                async let d: () = viewModel.loadDashboard()
                async let a: () = analyticsViewModel.loadDashboardInsights(force: true)
                async let p: () = progressionPlanViewModel.loadActivePlan()
                _ = await (d, a, p)
            }
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(
                    workout: workout,
                    historyViewModel: historyViewModel,
                    analyticsViewModel: analyticsViewModel
                )
            }
        }
    }

    // MARK: - Greeting

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Late night grind"
        }
    }

    private var motivationalSubtitle: String {
        let phrases = [
            "Let's get after it.",
            "Time to build.",
            "Ready to lift?",
            "Consistency wins.",
            "One rep at a time.",
            "Earn it today."
        ]
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return phrases[dayOfYear % phrases.count]
    }
}

#endif
