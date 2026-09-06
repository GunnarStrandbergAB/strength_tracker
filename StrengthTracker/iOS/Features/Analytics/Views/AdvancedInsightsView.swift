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
                    let types = WorkoutArchetypeService.summarizeWorkoutTypes(workouts: viewModel.completedHistory)
                    Text("Training focus · last 12 weeks").font(.caption).foregroundStyle(STColors.textSecondary)
                    if types.isEmpty { Text("No sessions logged in this period.").font(.subheadline) }
                    ForEach(types.prefix(4)) { type in workoutTypeRow(type) }
                    if types.count > 4 {
                        DisclosureGroup("More types (\(types.count - 4))") {
                            ForEach(types.dropFirst(4)) { type in workoutTypeRow(type) }
                        }
                    }
                    DisclosureGroup("How sessions are grouped") {
                        Text("Each session is counted once using completed working sets and each exercise's primary muscle. A focus needs 70% of sets; full body needs at least 25% upper and 25% lower. Other combinations are mixed. Routine names, template copies and exercise substitutions do not create extra types. Frequency is sessions divided by 12 weeks, including weeks without logs.").font(.caption).foregroundStyle(STColors.textSecondary)
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
        .preferredColorScheme(.dark)
        .safeAreaPadding(.bottom, 24).navigationTitle("Training patterns").navigationBarTitleDisplayMode(.inline).stNavigationBarStyle()
        .task { await viewModel.loadDashboardInsights() }
        .refreshable { await viewModel.loadDashboardInsights(force: true) }
    }
    private func workoutTypeRow(_ type: WorkoutArchetype) -> some View {
        NavigationLink {
            List(viewModel.completedHistory.filter { type.memberWorkoutIds.contains($0.id) }.sorted { $0.trainingDate > $1.trainingDate }) { workout in
                NavigationLink { WorkoutDetailView(workout: workout, analyticsViewModel: viewModel) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(workout.name).font(.headline).foregroundStyle(STColors.textPrimary)
                        Text(workout.trainingDate.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(STColors.textSecondary)
                    }.padding(.vertical, 6)
                }.listRowBackground(STColors.surface)
            }
            .scrollContentBackground(.hidden).background(STColors.background.ignoresSafeArea())
            .preferredColorScheme(.dark).tint(STColors.primary)
            .navigationTitle(type.label).stNavigationBarStyle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(type.label).font(.headline).foregroundStyle(STColors.textPrimary)
                    Text("\(type.memberWorkoutIds.count) \(type.memberWorkoutIds.count == 1 ? "session" : "sessions") · \(String(format: "%.1f", type.frequency))/week")
                        .font(.caption).foregroundStyle(STColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(STColors.textSecondary)
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

}
