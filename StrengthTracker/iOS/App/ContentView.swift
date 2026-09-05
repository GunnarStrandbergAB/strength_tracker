import SwiftUI
import StrengthTrackerShared

struct ContentView: View {
    @State private var selectedTab: Int

    let dashboardViewModel: DashboardViewModel
    let exerciseListViewModel: ExerciseListViewModel
    let progressViewModel: ProgressViewModel
    let workoutViewModel: WorkoutViewModel
    let workoutSessionCoordinator: WorkoutSessionCoordinator
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
    var aiCredentialsService: AICredentialsService? = nil
    var aiChatClient: (any AIChatClient)? = nil
    var aiChatViewModel: AIChatViewModel? = nil
    var aiMemoryService: AIMemoryService? = nil

    init(
        dashboardViewModel: DashboardViewModel,
        exerciseListViewModel: ExerciseListViewModel,
        progressViewModel: ProgressViewModel,
        workoutViewModel: WorkoutViewModel,
        workoutSessionCoordinator: WorkoutSessionCoordinator,
        historyViewModel: HistoryViewModel,
        templateViewModel: TemplateViewModel,
        analyticsViewModel: WorkoutAnalyticsViewModel,
        progressionPlanViewModel: ProgressionPlanViewModel,
        userPreferencesService: UserPreferencesService,
        connectivityManager: ConnectivityManager?,
        restTimerService: RestTimerService,
        personalRecordService: PersonalRecordService? = nil,
        proFeatureGate: ProFeatureGate? = nil,
        storeService: StoreService? = nil,
        aiCredentialsService: AICredentialsService? = nil,
        aiChatClient: (any AIChatClient)? = nil,
        aiChatViewModel: AIChatViewModel? = nil,
        aiMemoryService: AIMemoryService? = nil
    ) {
        self.dashboardViewModel = dashboardViewModel
        self.exerciseListViewModel = exerciseListViewModel
        self.progressViewModel = progressViewModel
        self.workoutViewModel = workoutViewModel
        self.workoutSessionCoordinator = workoutSessionCoordinator
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
        self.aiCredentialsService = aiCredentialsService
        self.aiChatClient = aiChatClient
        self.aiChatViewModel = aiChatViewModel
        self.aiMemoryService = aiMemoryService
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
                aiCredentialsService: aiCredentialsService,
                aiChatClient: aiChatClient,
                aiChatViewModel: aiChatViewModel,
                aiMemoryService: aiMemoryService,
                onStartWorkout: {
                    selectedTab = 1
                    Task {
                        await startSession(.init(name: "Quick Workout"))
                    }
                },
                onStartSession: { template, sessionId, planId, isDeload in
                    await startSession(.init(
                        name: template.name,
                        template: template,
                        isDeload: isDeload,
                        plannedSessionId: sessionId,
                        plannedPlanId: planId
                    ))
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
                coordinator: workoutSessionCoordinator,
                exerciseListViewModel: exerciseListViewModel,
                restTimerService: restTimerService,
                analyticsViewModel: analyticsViewModel,
                aiChat: aiChatEntry
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

            WorkoutHistoryView(viewModel: historyViewModel, analyticsViewModel: analyticsViewModel, exerciseListViewModel: exerciseListViewModel)
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
                PostWorkoutSummaryView(
                    debrief: debrief,
                    weightUnit: workoutViewModel.userPreferencesService?.weightUnit ?? .kg
                ) {
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

    private var aiChatEntry: AIChatEntry? {
        guard let aiChatViewModel, let aiCredentialsService else { return nil }
        return AIChatEntry(
            viewModel: aiChatViewModel,
            userPreferencesService: userPreferencesService,
            credentials: aiCredentialsService
        )
    }

    /// The Dashboard's start buttons only appear when no workout is active, so the
    /// coordinator's "already active" guard is a no-op here; a Watch-side workout
    /// is the one case it can refuse.
    private func startSession(_ request: WorkoutSessionCoordinator.StartRequest) async {
        do {
            try await workoutSessionCoordinator.start(request)
        } catch {
            workoutViewModel.errorMessage = error.localizedDescription
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
