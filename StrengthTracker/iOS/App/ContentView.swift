import SwiftUI
import StrengthTrackerShared

struct ContentView: View {
    @State private var selectedTab: Int

    let dashboardViewModel: DashboardViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let progressViewModel: ProgressViewModel
    let workoutViewModel: WorkoutViewModel
    let historyViewModel: HistoryViewModel
    let templateViewModel: TemplateViewModel
    let analyticsViewModel: WorkoutAnalyticsViewModel
    let progressionPlanViewModel: ProgressionPlanViewModel
    let userPreferencesService: UserPreferencesService
    let connectivityManager: ConnectivityManager?
    let restTimerService: RestTimerService
    var personalRecordService: PersonalRecordService? = nil
    var proFeatureGate: ProFeatureGate? = nil
    var storeService: StoreService? = nil

    init(
        dashboardViewModel: DashboardViewModel,
        exerciseListViewModel: ExerciseListViewModel,
        progressViewModel: ProgressViewModel,
        workoutViewModel: WorkoutViewModel,
        historyViewModel: HistoryViewModel,
        templateViewModel: TemplateViewModel,
        analyticsViewModel: WorkoutAnalyticsViewModel,
        progressionPlanViewModel: ProgressionPlanViewModel,
        userPreferencesService: UserPreferencesService,
        connectivityManager: ConnectivityManager?,
        restTimerService: RestTimerService,
        personalRecordService: PersonalRecordService? = nil,
        proFeatureGate: ProFeatureGate? = nil,
        storeService: StoreService? = nil
    ) {
        self.dashboardViewModel = dashboardViewModel
        self.exerciseListViewModel = exerciseListViewModel
        self.progressViewModel = progressViewModel
        self.workoutViewModel = workoutViewModel
        self.historyViewModel = historyViewModel
        self.templateViewModel = templateViewModel
        self.analyticsViewModel = analyticsViewModel
        self.progressionPlanViewModel = progressionPlanViewModel
        self.userPreferencesService = userPreferencesService
        self.connectivityManager = connectivityManager
        self.restTimerService = restTimerService
        self.personalRecordService = personalRecordService
        self.proFeatureGate = proFeatureGate
        self.storeService = storeService
        _selectedTab = State(initialValue: workoutViewModel.isActive ? 1 : 0)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                viewModel: dashboardViewModel,
                analyticsViewModel: analyticsViewModel,
                historyViewModel: historyViewModel,
                progressionPlanViewModel: progressionPlanViewModel,
                exerciseListViewModel: exerciseListViewModel,
                templateViewModel: templateViewModel,
                userPreferencesService: userPreferencesService,
                connectivityManager: connectivityManager,
                proFeatureGate: proFeatureGate,
                storeService: storeService,
                onStartWorkout: {
                    selectedTab = 1
                    Task {
                        await workoutViewModel.startWorkout(name: "Quick Workout", from: nil)
                    }
                },
                onStartSession: { template, sessionId, planId, isDeload in
                    workoutViewModel.plannedSessionId = sessionId
                    workoutViewModel.plannedPlanId = planId
                    await workoutViewModel.startWorkout(name: template.name, from: template, isDeload: isDeload)
                },
                onHistoryTapped: {
                    selectedTab = 4
                }
            )
            .tint(STColors.textSecondary)
            .tabItem {
                Label("Dashboard", systemImage: "square.grid.2x2")
            }
            .tag(0)

            ActiveWorkoutView(
                viewModel: workoutViewModel,
                exerciseListViewModel: exerciseListViewModel,
                restTimerService: restTimerService,
                analyticsViewModel: analyticsViewModel
            )
            .tint(STColors.textSecondary)
            .tabItem {
                Label("Workout", systemImage: "figure.strengthtraining.traditional")
            }
            .tag(1)

            TemplateListView(viewModel: templateViewModel, exerciseListViewModel: exerciseListViewModel, workoutViewModel: workoutViewModel)
                .tint(STColors.textSecondary)
                .tabItem {
                    Label("Templates", systemImage: "list.clipboard")
                }
                .tag(2)

            ExerciseListView(viewModel: exerciseListViewModel, progressViewModel: progressViewModel, analyticsViewModel: analyticsViewModel, personalRecordService: personalRecordService)
                .tint(STColors.textSecondary)
                .tabItem {
                    Label("Exercises", systemImage: "dumbbell")
                }
                .tag(3)

            WorkoutHistoryView(viewModel: historyViewModel, analyticsViewModel: analyticsViewModel)
                .tint(STColors.textSecondary)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(4)
        }
        .toolbarBackground(STColors.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .tint(STColors.primary)
        .sheet(isPresented: .init(
            get: { workoutViewModel.showPostWorkoutSummary },
            set: { if !$0 { workoutViewModel.showPostWorkoutSummary = false; workoutViewModel.postWorkoutDebrief = nil } }
        )) {
            if let debrief = workoutViewModel.postWorkoutDebrief {
                PostWorkoutSummaryView(debrief: debrief) {
                    workoutViewModel.showPostWorkoutSummary = false
                    workoutViewModel.postWorkoutDebrief = nil
                }
                .interactiveDismissDisabled(false)
            }
        }
        .onChange(of: workoutViewModel.isActive) { oldValue, isActive in
            if isActive {
                selectedTab = 1
            } else if oldValue {
                selectedTab = 0
            }
        }
        .onChange(of: workoutViewModel.currentWorkout?.id) { _, newId in
            if newId != nil && workoutViewModel.isActive {
                selectedTab = 1
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "strengthtracker" else { return }
        switch url.host {
        case "workout":
            selectedTab = 1
        case "dashboard":
            selectedTab = 0
        case "history":
            selectedTab = 4
        case "exercises":
            selectedTab = 3
        default:
            break
        }
    }
}
