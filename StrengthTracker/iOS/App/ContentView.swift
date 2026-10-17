import SwiftUI
import Observation
import StrengthTrackerShared

struct ContentView: View {
    @Bindable var navigation: AppNavigationState
    @State private var presentations = AppPresentationState()

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
        navigation: AppNavigationState,
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
        self.navigation = navigation
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
    }

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            DashboardView(
                navigation: navigation,
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
                onOpenAIChat: openAIChat,
                onStartWorkout: {
                    navigation.selectedTab = 1
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
                    navigation.selectedTab = 4
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
                aiChat: aiChatEntry,
                onOpenAIChat: openAIChat
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
        .modifier(AppPresentations(state: presentations))
        .onChange(of: workoutViewModel.showPostWorkoutSummary, initial: true) { _, show in
            guard show, let debrief = workoutViewModel.postWorkoutDebrief else { return }
            // Capture the payload before clearing the producer's event. Its sheet
            // then owns stable data, including throughout dismissal animations.
            presentations.enqueueSummary(debrief, weightUnit: userPreferencesService.weightUnit)
            workoutViewModel.showPostWorkoutSummary = false
            workoutViewModel.postWorkoutDebrief = nil
        }
        .onChange(of: WorkoutNavigationSnapshot(isActive: workoutViewModel.isActive, id: workoutViewModel.currentWorkout?.id)) { _, snapshot in
            navigation.workoutChanged(snapshot)
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

    private func openAIChat() {
        guard let entry = aiChatEntry else { return }
        Task { await presentations.openChat(entry) }
    }
}

enum DashboardDestination: Hashable {
    case analytics(topic: String?)
    case exerciseHistory(UUID)
}

struct WorkoutNavigationSnapshot: Equatable {
    var isActive: Bool
    var id: UUID?
}

enum AppLink: Equatable {
    case dashboard, workout, restTimer, history, exercises
    case analytics(topic: String?)
    case exerciseHistory(UUID)

    init?(_ url: URL) {
        guard url.scheme == "strengthtracker" else { return nil }
        switch url.host {
        case "dashboard": self = .dashboard
        case "workout": self = .workout
        case "rest-timer": self = .restTimer
        case "history": self = .history
        case "exercises": self = .exercises
        case "analytics":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            // Legacy widget backgrounds used the same URL as the first highlight.
            // Never infer an exercise or analytics intent from those cached URLs.
            guard items.first(where: { $0.name == "source" })?.value == WidgetNavigation.insightSource else {
                self = .dashboard
                return
            }
            let topic = items.first { $0.name == "topic" }?.value
            self = .analytics(topic: topic.flatMap { WidgetNavigation.analyticsTopics.contains($0) ? $0 : nil })
        case "exercise-history":
            guard let id = UUID(uuidString: String(url.path.dropFirst())) else {
                self = .dashboard
                return
            }
            self = .exerciseHistory(id)
        default: return nil
        }
    }
}

/// One scene-owned route, shared by manual navigation, restoration and widget
/// links. A URL received before restoration/activation is consumed exactly once.
@MainActor @Observable
final class AppNavigationState {
    var selectedTab = 0
    var dashboardPath = NavigationPath()
    private(set) var isRestored = false
    private(set) var hasInitialRoute = false
    private(set) var pendingLink: AppLink?
    private var phase: ScenePhase = .inactive
    private var needsHome = true
    private var hasActivated = false
    private var lastWorkout = WorkoutNavigationSnapshot(isActive: false, id: nil)

    func restorationFinished(hasActiveWorkout: Bool, workoutID: UUID? = nil, hasProAccess: Bool) {
        guard !isRestored else { return }
        lastWorkout = .init(isActive: hasActiveWorkout, id: workoutID)
        isRestored = true
        activateIfReady(hasActiveWorkout: hasActiveWorkout, hasProAccess: hasProAccess)
    }

    func scenePhaseChanged(_ phase: ScenePhase, hasActiveWorkout: Bool, hasProAccess: Bool) {
        let previousPhase = self.phase
        self.phase = phase
        if phase == .background, previousPhase != .background, hasActivated {
            needsHome = true
            pendingLink = nil
            // Clear the previous drill-down before the next foreground frame.
            // Activation checks again in case the active workout changed away.
            resetToHome(hasActiveWorkout: hasActiveWorkout)
        }
        if phase == .active { hasActivated = true }
        activateIfReady(hasActiveWorkout: hasActiveWorkout, hasProAccess: hasProAccess)
    }

    func receive(_ link: AppLink, hasProAccess: Bool) {
        pendingLink = link
        if isRestored, phase == .active { applyPendingLink(hasProAccess: hasProAccess) }
    }

    func openAnalytics(topic: String? = nil) {
        selectedTab = 0
        dashboardPath = NavigationPath([DashboardDestination.analytics(topic: topic)])
    }

    func workoutChanged(_ workout: WorkoutNavigationSnapshot) {
        // Restoration chooses its default only after any queued link is known.
        guard isRestored, workout != lastWorkout else { return }
        let wasActive = lastWorkout.isActive
        lastWorkout = workout
        if workout.isActive { selectedTab = 1 }
        else if wasActive { selectedTab = 0; dashboardPath = NavigationPath() }
    }

    private func activateIfReady(hasActiveWorkout: Bool, hasProAccess: Bool) {
        guard isRestored, phase == .active else { return }
        if pendingLink != nil {
            applyPendingLink(hasProAccess: hasProAccess)
        } else if needsHome {
            resetToHome(hasActiveWorkout: hasActiveWorkout)
        }
        needsHome = false
        hasInitialRoute = true
    }

    private func resetToHome(hasActiveWorkout: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dashboardPath = NavigationPath()
            selectedTab = hasActiveWorkout ? 1 : 0
        }
    }

    private func applyPendingLink(hasProAccess: Bool) {
        guard let link = pendingLink else { return }
        pendingLink = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            var destination: DashboardDestination?
            switch link {
            case .dashboard: selectedTab = 0
            case .analytics(let topic):
                selectedTab = 0
                if hasProAccess { destination = .analytics(topic: topic) }
            case .exerciseHistory(let id):
                selectedTab = 0
                if hasProAccess { destination = .exerciseHistory(id) }
            case .workout, .restTimer: selectedTab = 1
            case .history: selectedTab = 4
            case .exercises: selectedTab = 3
            }
            // Assign the final path once. Data loading never adds another route.
            dashboardPath = NavigationPath(destination.map { [$0] } ?? [])
        }
    }
}

/// Keep initial content out of the first frame until the scene has selected its
/// initial route. Remains mounted across later foreground/background transitions.
struct AppLaunchGate<Content: View>: View {
    let navigation: AppNavigationState
    var allowFallback = false
    @ViewBuilder let content: Content

    var body: some View {
        if navigation.hasInitialRoute || allowFallback { content }
        else { STColors.background.ignoresSafeArea() }
    }
}

/// Attached outside the tabs and navigation stacks, including the restore gate.
struct AppNavigationLifecycle: ViewModifier {
    let navigation: AppNavigationState
    let hasActiveWorkout: Bool
    let hasProAccess: Bool
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.onChange(of: phase, initial: true) { _, phase in
            navigation.scenePhaseChanged(phase, hasActiveWorkout: hasActiveWorkout, hasProAccess: hasProAccess)
        }
    }
}
