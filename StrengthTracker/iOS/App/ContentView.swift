import SwiftUI
import StrengthTrackerShared

struct ContentView: View {
    @State private var selectedTab = 0

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
    var personalRecordService: PersonalRecordService? = nil
    var proFeatureGate: ProFeatureGate? = nil
    var storeService: StoreService? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                viewModel: dashboardViewModel,
                analyticsViewModel: analyticsViewModel,
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
                onStartSession: { template, sessionId, planId in
                    workoutViewModel.plannedSessionId = sessionId
                    workoutViewModel.plannedPlanId = planId
                    await workoutViewModel.startWorkout(name: template.name, from: template)
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
                exerciseListViewModel: exerciseListViewModel
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
        .onChange(of: workoutViewModel.isActive) { oldValue, isActive in
            if isActive {
                selectedTab = 1
            } else if oldValue {
                if let sessionId = workoutViewModel.plannedSessionId,
                   let planId = workoutViewModel.plannedPlanId,
                   let workoutId = workoutViewModel.currentWorkout?.id {
                    Task {
                        await progressionPlanViewModel.handleSessionCompleted(
                            sessionId: sessionId, planId: planId, workoutId: workoutId
                        )
                    }
                }
                workoutViewModel.plannedSessionId = nil
                workoutViewModel.plannedPlanId = nil
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
