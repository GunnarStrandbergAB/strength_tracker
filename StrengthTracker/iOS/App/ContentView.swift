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
    let userPreferencesService: UserPreferencesService

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                viewModel: dashboardViewModel,
                userPreferencesService: userPreferencesService,
                onStartWorkout: {
                    selectedTab = 1
                    Task {
                        await workoutViewModel.startWorkout(name: "Quick Workout", from: nil)
                    }
                },
                onHistoryTapped: {
                    selectedTab = 4
                }
            )
            .tabItem {
                Label("Dashboard", systemImage: "square.grid.2x2")
            }
            .tag(0)

            ActiveWorkoutView(
                viewModel: workoutViewModel,
                exerciseListViewModel: exerciseListViewModel
            )
            .tabItem {
                Label("Workout", systemImage: "figure.strengthtraining.traditional")
            }
            .tag(1)

            TemplateListView(viewModel: templateViewModel, exerciseListViewModel: exerciseListViewModel, workoutViewModel: workoutViewModel)
                .tabItem {
                    Label("Templates", systemImage: "list.clipboard")
                }
                .tag(2)

            ExerciseListView(viewModel: exerciseListViewModel, progressViewModel: progressViewModel)
                .tabItem {
                    Label("Exercises", systemImage: "dumbbell")
                }
                .tag(3)

            WorkoutHistoryView(viewModel: historyViewModel)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(4)
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
