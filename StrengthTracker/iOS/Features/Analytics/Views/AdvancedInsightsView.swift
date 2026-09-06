import SwiftUI
import Charts
import StrengthTrackerShared

struct AdvancedInsightsView: View {
    let viewModel: WorkoutAnalyticsViewModel
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                AnalyticsPanel(title: "Training state") {
                    if let state = viewModel.trainingState {
                        Text(state.kind.rawValue).font(.title2.bold())
                        Text(state.kind.explanation).font(.subheadline).foregroundStyle(STColors.textSecondary)
                        Text("Completed four-week periods · inferred pattern, separate from your planned phase").font(.caption)
                        Chart(state.weeks) { week in
                            BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Working sets", week.sets))
                                .foregroundStyle(week.kind == .light ? STColors.textSecondary : STColors.primary)
                        }.chartYAxisLabel("Working sets").frame(height: 180)
                        DisclosureGroup("Week-by-week details") {
                            ForEach(state.weeks) { week in
                                LabeledContent(week.start.formatted(date: .abbreviated, time: .omitted), value: week.sessions == 0 ? "No logged sessions" : "\(week.sets) sets · \(week.sessions) sessions")
                            }
                        }.font(.caption)
                        DisclosureGroup("What do the states mean?") {
                            ForEach(TrainingStateKind.allCases, id: \.rawValue) { kind in
                                VStack(alignment: .leading, spacing: 4) { Text(kind.rawValue).bold(); Text(kind.explanation) }.font(.caption).padding(.vertical, 5)
                            }
                        }
                    } else { Text("Log more sessions to establish your baseline.") }
                }
                AnalyticsPanel(title: "Workout types") {
                    Text("Frequency over the same trailing 12-week window · session counts are all time").font(.caption).foregroundStyle(STColors.textSecondary)
                    ForEach(viewModel.insights.archetypes) { type in
                        NavigationLink {
                            List(viewModel.completedHistory.filter { type.memberWorkoutIds.contains($0.id) }.sorted { $0.trainingDate > $1.trainingDate }) { workout in
                                NavigationLink { WorkoutDetailView(workout: workout, analyticsViewModel: viewModel) } label: {
                                    VStack(alignment: .leading) { Text(workout.name); Text(workout.trainingDate.formatted(date: .abbreviated, time: .omitted)).font(.caption) }
                                }
                            }.navigationTitle(type.label).stNavigationBarStyle()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(type.label).fixedSize(horizontal: false, vertical: true).font(.subheadline.weight(.semibold)).foregroundStyle(STColors.textPrimary)
                                Text(type.dominantFeatures.prefix(2).joined(separator: " + ")).font(.caption).foregroundStyle(STColors.textSecondary)
                                Text(String(format: "%d sessions · %.1f/week", type.memberWorkoutIds.count, type.frequency)).font(.caption).foregroundStyle(STColors.textSecondary)
                                if let last = type.lastPerformed { Text("Last: \(last.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(STColors.textSecondary) }
                            }.padding(.vertical, 6)
                        }
                    }
                }
                AnalyticsPanel(title: "What changed") {
                    if let state = viewModel.trainingState {
                        Text("\(state.previous.start.formatted(date: .abbreviated, time: .omitted)) – \(state.previous.end.formatted(date: .abbreviated, time: .omitted)) versus \(state.current.start.formatted(date: .abbreviated, time: .omitted)) – \(state.current.end.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                        LabeledContent("Working sets/week", value: String(format: "%.1f → %.1f", state.previous.weeklySets, state.current.weeklySets))
                        LabeledContent("Sessions", value: "\(state.previous.sessions) → \(state.current.sessions)")
                        LabeledContent("Median reps", value: String(format: "%.0f → %.0f", state.previous.medianReps, state.current.medianReps))
                        if let previous = state.previous.meanRPE, let current = state.current.meanRPE {
                            LabeledContent("Logged mean RPE", value: String(format: "%.1f → %.1f", previous, current))
                        }
                    }
                    DisclosureGroup("Notable sessions") {
                        let recent = TrainingStateService.notableSessions(workouts: viewModel.completedHistory)
                        if recent.isEmpty { Text("No clear differences in comparable recent sessions.").font(.caption) }
                        ForEach(recent.prefix(5)) { notable in
                            let workout = notable.workout
                            NavigationLink { WorkoutDetailView(workout: workout, analyticsViewModel: viewModel) } label: {
                                VStack(alignment: .leading) {
                                    Text(workout.name).font(.subheadline)
                                    Text(workout.trainingDate.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                                    Text(notable.detail).font(.caption)
                                }.padding(.vertical, 5)
                            }
                        }
                        Text("Open a session to inspect its actual sets. A shorter or lighter session is not automatically a problem.").font(.caption)
                    }
                }
            }.padding(18)
        }.background(STColors.background).foregroundStyle(STColors.textPrimary)
        .safeAreaPadding(.bottom, 24).navigationTitle("Training patterns").navigationBarTitleDisplayMode(.inline).stNavigationBarStyle()
        .task { await viewModel.loadDashboardInsights() }
        .refreshable { await viewModel.loadDashboardInsights(force: true) }
    }
}
