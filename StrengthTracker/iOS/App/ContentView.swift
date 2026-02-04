import SwiftUI
import StrengthTrackerShared

struct ContentView: View {
    @State private var selectedTab = 0

    let exerciseListViewModel: ExerciseListViewModel
    let workoutViewModel: WorkoutViewModel
    let historyViewModel: HistoryViewModel
    let templateViewModel: TemplateViewModel

    var body: some View {
        TabView(selection: $selectedTab) {
            ActiveWorkoutView(
                viewModel: workoutViewModel,
                exerciseListViewModel: exerciseListViewModel
            )
            .tabItem {
                Label("Workout", systemImage: "figure.strengthtraining.traditional")
            }
            .tag(0)

            TemplateListView(viewModel: templateViewModel)
                .tabItem {
                    Label("Templates", systemImage: "list.clipboard")
                }
                .tag(1)

            ExerciseListView(viewModel: exerciseListViewModel)
                .tabItem {
                    Label("Exercises", systemImage: "dumbbell")
                }
                .tag(2)

            WorkoutHistoryView(viewModel: historyViewModel)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(4)
        }
    }
}
