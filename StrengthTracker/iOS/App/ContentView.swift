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
                onStartWorkout: {
                    selectedTab = 1
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
    }
}
