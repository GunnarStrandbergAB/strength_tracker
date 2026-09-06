import SwiftUI
import Charts
import StrengthTrackerShared

struct AnalyticsPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(STColors.textPrimary)
            content.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct AnalyticsDashboardView: View {
    let viewModel: WorkoutAnalyticsViewModel
    var initialTopic: String? = nil
    @State private var linkedTrend: OverloadTrend?
    @State private var didRouteTopic = false
    @Environment(DataRevision.self) private var revision: DataRevision?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let error = viewModel.errorMessage {
                        AnalyticsPanel(title: "Unable to update analytics") {
                            Text(error).font(.subheadline)
                            Button("Retry") { Task { await viewModel.loadDashboardInsights(force: true) } }
                        }
                    }
                    if viewModel.isInsightsLoading && viewModel.insights.workoutCount == 0 { ProgressView("Analyzing your history…") }
                    VStack(spacing: 2) {
                        Text("\(viewModel.insights.workoutCount)").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("workouts completed · all time").font(.subheadline).foregroundStyle(STColors.textSecondary)
                    }.frame(maxWidth: .infinity).padding(18).background(STColors.surface).clipShape(RoundedRectangle(cornerRadius: 20))

                    AnalyticsPanel(title: "Coach verdict") {
                        if let verdict = viewModel.insights.verdict {
                            Text(verdict.headline).font(.title3.bold()).foregroundStyle(AnalyticsColors.verdict(verdict))
                            Text(verdict.action).font(.subheadline)
                            DisclosureGroup("Why this verdict?") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(verdict.reasons, id: \.self) { Text($0) }
                                    Text("Updated \(verdict.computedAt.formatted(date: .abbreviated, time: .shortened))")
                                    Text("Possible verdicts: Clear to Progress, Hold Steady, Deload Recommended, Deload In Progress. These describe overall advice; individual exercise trends can differ.")
                                }.font(.caption).foregroundStyle(STColors.textSecondary).padding(.top, 8)
                            }
                        } else { Text("Building baseline. More recent training evidence is needed before giving a direction.").font(.subheadline) }
                    }.id("verdict")
                    AnalyticsLoadCard(viewModel: viewModel).id("load")
                    AnalyticsWatchlistCard(viewModel: viewModel).id("progress")
                    AnalyticsPanel(title: "Best training time") {
                        if let time = viewModel.insights.timeOfDayAnalysis {
                            Text(time.message).font(.subheadline)
                            Text("\(time.bestWindow): \(time.bestCount) sessions · \(time.worstWindow): \(time.worstCount) sessions").font(.caption)
                            Text(String(format: "%.0f vs %.0f points · prior 12 weeks", time.bestAvgQuality, time.worstAvgQuality)).font(.caption.monospacedDigit())
                            DisclosureGroup("How this is compared") { Text("Only comparable routines with at least three measured sessions in each time window are compared. This is an association, not proof that changing your workout time will improve performance.").font(.caption) }
                        } else { Text("No clear difference yet. We compare the same routines at different times, once enough scored sessions are available.").font(.subheadline) }
                    }.id("time")
                    AnalyticsQualityCard(viewModel: viewModel).id("quality")
                    AnalyticsCoverageCard(viewModel: viewModel).id("coverage")
                    AnalyticsRecoveryCard(viewModel: viewModel).id("recovery")
                    AdvancedInsightsCardView(viewModel: viewModel).id("patterns")
                    Text("Estimates from your logged history · updated \(viewModel.insights.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(STColors.textSecondary)
                }.padding(.horizontal, 18).padding(.vertical, 12)
            }
            .onChange(of: viewModel.isInsightsLoading) { _, loading in
                if !loading { routeTopic(using: proxy) }
            }
            .onAppear { routeTopic(using: proxy) }
            .onChange(of: initialTopic) { _, _ in didRouteTopic = false; routeTopic(using: proxy) }

        }
        .background(STColors.background).foregroundStyle(STColors.textPrimary)
        .safeAreaPadding(.bottom, 24)
        .navigationDestination(item: $linkedTrend) { AnalyticsExerciseTrendView(trend: $0, viewModel: viewModel) }
        .navigationTitle("Analytics").navigationBarTitleDisplayMode(.inline).stNavigationBarStyle()
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink("Patterns") { AdvancedInsightsView(viewModel: viewModel) } } }
        .task(id: revision?.value ?? 0) { await viewModel.loadDashboardInsights() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await viewModel.loadDashboardInsights()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await viewModel.loadDashboardInsights(force: true) } } }
        .refreshable { await viewModel.loadDashboardInsights(force: true) }
    }
    private func routeTopic(using proxy: ScrollViewProxy) {
        guard !didRouteTopic, let initialTopic else { return }
        if initialTopic.hasPrefix("progress-"), let id = UUID(uuidString: String(initialTopic.dropFirst(9))) {
            if let trend = viewModel.insights.overloadTrends.first(where: { $0.exerciseId == id }) {
                linkedTrend = trend
                didRouteTopic = true
            } else if viewModel.insights.workoutCount > 0 && !viewModel.isInsightsLoading {
                didRouteTopic = true
            }
            proxy.scrollTo("progress", anchor: .top)
        } else {
            proxy.scrollTo(initialTopic, anchor: .top)
            didRouteTopic = true
        }
    }
}

struct AnalyticsLoadCard: View {
    let viewModel: WorkoutAnalyticsViewModel
    var body: some View {
        AnalyticsPanel(title: "Training load") {
            if let load = viewModel.insights.trainingLoad {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        loadRing(load.acwr)
                        Text(AnalyticsFormatting.loadZoneLabel(load.loadZone)).font(.headline).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        loadRing(load.acwr)
                        Text(AnalyticsFormatting.loadZoneLabel(load.loadZone)).font(.headline)
                    }
                }
                Text(String(format: "Recent load is %.0f%% %@ your smoothed baseline", abs(load.acwr - 1) * 100, load.acwr < 1 ? "below" : "above")).font(.subheadline)
                LabeledContent("Load indices", value: String(format: "%.1f / %.1f", load.acuteLoad, load.chronicLoad)).font(.caption.monospacedDigit())
                NavigationLink("Explore load history") { AnalyticsHistoryView(viewModel: viewModel, kind: .load) }
                DisclosureGroup("Load history · 8 weeks") {
                    Chart(load.history ?? []) { day in
                        LineMark(x: .value("Date", day.date), y: .value("Index", day.recent)).foregroundStyle(by: .value("Series", "Recent"))
                        LineMark(x: .value("Date", day.date), y: .value("Index", day.baseline)).foregroundStyle(by: .value("Series", "Baseline"))
                    }.chartForegroundStyleScale(["Recent": STColors.primary, "Baseline": STColors.textSecondary]).frame(height: 180)
                    Text("Retrospectively standardized using current exercise bests and resolved bodyweight.").font(.caption)
                }
                DisclosureGroup("How to read this") {
                    Text("Short and long smoothed daily load (7/28-day spans), including rest days. Today's load is partial. Each working set contributes reps × relative load; RPE is reported separately. This describes logged training, not readiness or a safety boundary. Bodyweight exercises use your currently resolved bodyweight retrospectively. Missing exercise baselines use an estimated 75% relative load.")
                        .font(.caption).foregroundStyle(STColors.textSecondary).padding(.top, 8)
                }
            } else { Text("Building baseline: eight sessions spanning at least two weeks are needed.").font(.subheadline) }
        }
    }
    private func loadRing(_ ratio: Double) -> some View {
        Text(AnalyticsFormatting.acwr(ratio))
            .font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
            .padding(22).background { Circle().stroke(STColors.primary.opacity(0.65), lineWidth: 4) }
            .accessibilityLabel("Load ratio \(AnalyticsFormatting.acwr(ratio))")
    }
}

struct AnalyticsTrendRow: View {
    let trend: OverloadTrend
    let viewModel: WorkoutAnalyticsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trend.exerciseName).fixedSize(horizontal: false, vertical: true).font(.subheadline.weight(.semibold)).foregroundStyle(STColors.textPrimary)
            HStack {
                Text(trend.statusLabel).foregroundStyle(AnalyticsColors.trend(trend.trendStatus))
                Spacer()
                Text(String(format: "%+.2f%%/wk", trend.percentPerWeek)).monospacedDigit().foregroundStyle(STColors.textSecondary)
            }.font(.caption)
        }.padding(.vertical, 6)
    }
}
struct AnalyticsProgressList: View {
    let viewModel: WorkoutAnalyticsViewModel
    @State private var query = ""
    @AppStorage(ExerciseHistoryPreferences.pinsKey) private var pins = ""
    var body: some View {
        List {
            Section {
                ForEach(viewModel.loggedExercises.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { exercise in
                    HStack {
                        NavigationLink {
                            ExerciseHistoryDetailView(exercise: exercise, workouts: viewModel.completedHistory,
                                bodyWeightKg: viewModel.resolvedBodyWeightKg, weightUnit: viewModel.weightUnit,
                                suppliedTrend: viewModel.insights.overloadTrends.first { $0.exerciseId == exercise.id })
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(exercise.name).font(.headline).foregroundStyle(STColors.textPrimary)
                                Text(viewModel.insights.overloadTrends.first { $0.exerciseId == exercise.id }?.statusLabel ?? "Building evidence")
                                    .font(.caption).foregroundStyle(STColors.textSecondary)
                            }.padding(.vertical, 6)
                        }
                        let pinned = ExerciseHistoryPreferences.pins(from: pins).contains(exercise.id)
                        Button { pins = ExerciseHistoryPreferences.toggling(exercise.id, in: pins) } label: { Image(systemName: pinned ? "pin.fill" : "pin") }
                            .buttonStyle(.borderless).accessibilityLabel("\(pinned ? "Unpin" : "Pin") \(exercise.name)")
                            .disabled(!pinned && ExerciseHistoryPreferences.pins(from: pins).count >= 4)
                    }.listRowBackground(STColors.surface)
                }
            } header: { Text("Pin up to four exercises · verdicts use recent 12 weeks") }
        }.scrollContentBackground(.hidden).background(STColors.background.ignoresSafeArea())
            .preferredColorScheme(.dark).tint(STColors.primary).safeAreaPadding(.bottom, 24)
            .searchable(text: $query, prompt: "Find an exercise").navigationTitle("Exercise progress").stNavigationBarStyle()
    }
}
struct AnalyticsExerciseTrendView: View {
    let trend: OverloadTrend
    let viewModel: WorkoutAnalyticsViewModel
    var body: some View {
        if let exercise = viewModel.loggedExercises.first(where: { $0.id == trend.exerciseId }) {
            ExerciseHistoryDetailView(exercise: exercise, workouts: viewModel.completedHistory,
                bodyWeightKg: viewModel.resolvedBodyWeightKg, weightUnit: viewModel.weightUnit, suppliedTrend: trend)
        } else {
            ContentUnavailableView("History unavailable", systemImage: "chart.xyaxis.line", description: Text("Refresh analytics to load this exercise's sessions."))
                .background(STColors.background.ignoresSafeArea()).preferredColorScheme(.dark)
        }
    }
}

struct AnalyticsQualityCard: View {
    let viewModel: WorkoutAnalyticsViewModel
    var body: some View {
        AnalyticsPanel(title: "Training quality") {
            if let score = viewModel.aggregateQuality, score.workoutsIncluded > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.0f", score.ewmaOverall)).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(AnalyticsColors.score(score.ewmaOverall))
                    Text("/ 100").font(.subheadline)
                    Spacer()
                    if !score.provisional { Text(String(format: "%+.0f pts", score.trendVsPrior)).font(.caption.monospacedDigit()) }
                }
                qualityRow("Volume", score.ewmaVolume)
                qualityRow("Intensity", score.ewmaIntensity)
                qualityRow("Rest Rhythm", score.ewmaConsistency)
                qualityRow("Program balance", score.ewmaBalance)
                Text(score.provisional ? "Provisional · building a measured baseline" : "\(score.workoutsIncluded) measured sessions. Recent sessions carry more weight.").font(.caption).foregroundStyle(STColors.textSecondary)
                NavigationLink("Explore quality history") { AnalyticsHistoryView(viewModel: viewModel, kind: .quality) }
                DisclosureGroup("How this is scored") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Four equal components. Volume meets its benchmark at 80% of comparable historical muscle volume; intensity compares set e1RM with prior exercise bests. Rest Rhythm measures regularity within an exercise, not whether a rest was long enough. Program balance describes the prior 12 weeks including that session.")
                        Text("The aggregate gives each new session 30% weight and the previous aggregate 70%. Provisional sessions are excluded when measured sessions exist. Changes are score points versus four weeks ago. Version \(WorkoutQualityScore.modelVersion); historical scores use information available at the session date.")
                        if let latest = viewModel.qualityScore {
                            Text("Latest session: \(Int(latest.overallScore))/100\(latest.isProvisional ? " · provisional" : "")")
                            ForEach(latest.provisionalReasons ?? [], id: \.self) { Text($0) }
                        }
                    }.font(.caption).foregroundStyle(STColors.textSecondary).padding(.top, 8)
                }
            } else { Text("Complete more sessions to establish your quality baseline.").font(.subheadline) }
        }
    }
    private func qualityRow(_ label: String, _ score: Double) -> some View {
        VStack(spacing: 4) {
            LabeledContent(label, value: String(format: "%.0f", score)).font(.subheadline.monospacedDigit())
            ProgressView(value: min(100, max(0, score)), total: 100).tint(AnalyticsColors.score(score))
        }
    }
}

struct AnalyticsCoverageCard: View {
    let viewModel: WorkoutAnalyticsViewModel
    var body: some View {
        AnalyticsPanel(title: "Muscle coverage") {
            Text("Weekly average · last 4 weeks").font(.caption).foregroundStyle(STColors.textSecondary)
            if let balance = viewModel.insights.muscleBalance {
                let groups = balance.muscleGroupVolumes
                let largest = groups.map { ($0.directWeeklySets ?? 0) + ($0.indirectWeeklySets ?? 0) }.max() ?? 1
                ForEach(groups.prefix(5)) { group in coverageRow(group, largest: largest) }
                NavigationLink("Explore muscle history") { AnalyticsHistoryView(viewModel: viewModel, kind: .coverage) }
                DisclosureGroup("All muscles and attribution") {
                    ForEach(groups.dropFirst(5)) { group in coverageRow(group, largest: largest) }
                    Text("Solid = direct working sets. Muted = estimated indirect credits (0.5 divided among secondary muscles per set). These are exposure estimates, not equal muscle stimulus. Compare with your own program; no universal balance ratio is prescribed.").font(.caption).foregroundStyle(STColors.textSecondary)
                }
            } else { Text("No working-set coverage yet.").font(.subheadline) }
        }
    }
    private func coverageRow(_ group: MuscleGroupVolume, largest: Double) -> some View {
        let direct = group.directWeeklySets ?? 0, indirect = group.indirectWeeklySets ?? 0
        return VStack(alignment: .leading, spacing: 5) {
            LabeledContent(group.muscleGroup.capitalized, value: String(format: "%.1f + %.1f sets", direct, indirect)).font(.caption.monospacedDigit())
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(STColors.primary).frame(width: geo.size.width * direct / max(1, largest))
                    Rectangle().fill(STColors.textSecondary.opacity(0.45)).frame(width: geo.size.width * indirect / max(1, largest))
                }.clipShape(Capsule())
            }.frame(height: 8).accessibilityHidden(true)
        }.padding(.vertical, 4)
    }
}

struct AnalyticsRecoveryCard: View {
    let viewModel: WorkoutAnalyticsViewModel
    var body: some View {
        AnalyticsPanel(title: "Recovery estimate") {
            Text("Exposure-based estimate · optional check-ins personalize the prior").font(.caption).foregroundStyle(STColors.textSecondary)
            if viewModel.insights.recoveryPatterns.isEmpty { Text("No recent muscle exposure logged.").font(.subheadline) }
            ForEach(viewModel.insights.recoveryPatterns.prefix(3)) { pattern in recoveryRow(pattern) }
            DisclosureGroup("All muscles and check-ins") {
                ForEach(viewModel.insights.recoveryPatterns.dropFirst(3)) { pattern in recoveryRow(pattern) }
                Text("A readiness check-in adjusts a bounded prior gradually; it is not a measured recovery time. Earlier session exposure can overlap. Estimates use current workload relative to your usual session dose. No logged exposure does not prove readiness.").font(.caption).foregroundStyle(STColors.textSecondary)
            }
        }
    }
    private func recoveryRow(_ pattern: RecoveryPattern) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let last = pattern.lastTrainedDate { Text("Last trained \(last.formatted(date: .abbreviated, time: .shortened))") }
                let remaining = max(0, (pattern.readyToTrainDate ?? Date()).timeIntervalSinceNow / 3600)
                Text(String(format: "Estimated remaining: %.0f–%.0f hours · %d check-ins", remaining * 0.75, remaining * 1.25, pattern.feedbackCount ?? 0))
                HStack {
                    Button("Feels ready") { Task { await viewModel.recordRecovery(pattern, feelsReady: true) } }
                    Button("Still sore") { Task { await viewModel.recordRecovery(pattern, feelsReady: false) } }
                }.buttonStyle(.bordered)
            }.font(.caption).padding(.vertical, 8)
        } label: {
            LabeledContent(pattern.muscleGroup.capitalized, value: pattern.recoveryStatus == .ready ? "Likely ready" : pattern.isJustTrained ? "Recently trained" : "Recovering")
                .font(.subheadline).foregroundStyle(STColors.textPrimary)
        }
    }
}

struct AnalyticsWatchlistCard: View {
    let viewModel: WorkoutAnalyticsViewModel
    @AppStorage(ExerciseHistoryPreferences.pinsKey) private var pins = ""
    @State private var period = HistoryPeriod.threeMonths
    private var exercises: [Exercise] {
        let ids = ExerciseHistoryPreferences.pins(from: pins)
        let automatic = Array(viewModel.insights.overloadTrends.prefix(4).map(\.exerciseId))
        let selected = ids.isEmpty ? (automatic.isEmpty ? Array(viewModel.loggedExercises.prefix(4).map(\.id)) : automatic) : ids
        return selected.compactMap { id in viewModel.loggedExercises.first { $0.id == id } }
    }
    var body: some View {
        AnalyticsPanel(title: "Exercise progress") {
            Text(ExerciseHistoryPreferences.pins(from: pins).isEmpty ? "Automatic selection · pin exercises to make it yours" : "Your pinned exercises")
                .font(.caption).foregroundStyle(STColors.textSecondary)
            Picker("Watchlist period", selection: $period) {
                ForEach([HistoryPeriod.fourWeeks, .threeMonths, .sixMonths, .year, .all], id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            ForEach(exercises) { exercise in
                NavigationLink {
                    ExerciseHistoryDetailView(exercise: exercise, workouts: viewModel.completedHistory, bodyWeightKg: viewModel.resolvedBodyWeightKg,
                        weightUnit: viewModel.weightUnit, suppliedTrend: viewModel.insights.overloadTrends.first { $0.exerciseId == exercise.id })
                } label: { watchRow(exercise) }.foregroundStyle(STColors.textPrimary)
            }
            if exercises.isEmpty { Text("Complete an exercise to start its history.").font(.subheadline) }
            NavigationLink { AnalyticsProgressList(viewModel: viewModel) } label: { Label("All exercises & pins", systemImage: "arrow.right") }
        }
    }
    private func watchRow(_ exercise: Exercise) -> some View {
        let sessions = ExerciseHistoryCalculator.sessions(exerciseId: exercise.id, workouts: viewModel.completedHistory, bodyWeightKg: viewModel.resolvedBodyWeightKg)
        let metric = ExerciseHistoryMetric.available(for: exercise.exerciseType)[0]
        let interval = period.interval(now: Date(), firstDate: sessions.first?.date, customStart: Date(), customEnd: Date())
        let points = ExerciseHistoryCalculator.points(sessions: sessions, metric: metric).filter { $0.date >= interval.start && $0.date <= interval.end }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(exercise.name).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(STColors.textSecondary)
            }
            if !points.isEmpty {
                Chart(points.filter { !metric.isPerformance || !$0.isDeload }) { point in
                    LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value), series: .value("Segment", point.segment)).foregroundStyle(STColors.primary)
                    PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value)).foregroundStyle(STColors.primary)
                }.chartYScale(domain: .automatic(includesZero: !metric.isPerformance)).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 36).accessibilityHidden(true)
            }
            if metric.isPerformance, let change = ExerciseHistoryCalculator.performanceChange(points: points, interval: interval) {
                Text(String(format: "%+.1f%% estimated strength · selected period", change)).font(.caption.monospacedDigit())
            } else { Text(metric.isPerformance ? "Not enough observations near both ends for a period change" : "\(metric.rawValue) per session").font(.caption).foregroundStyle(STColors.textSecondary) }
            if let last = sessions.last { Text("Last session \(last.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(STColors.textSecondary) }
            if let trend = viewModel.insights.overloadTrends.first(where: { $0.exerciseId == exercise.id }) {
                Text("\(trend.statusLabel) · recent 12 weeks").font(.caption).foregroundStyle(AnalyticsColors.trend(trend.trendStatus))
            }
        }.padding(.vertical, 8)
    }
}

struct AnalyticsHistoryView: View {
    enum Kind: String { case quality = "Quality history", load = "Load history", coverage = "Muscle history" }
    let viewModel: WorkoutAnalyticsViewModel
    let kind: Kind
    @State private var period = HistoryPeriod.threeMonths
    @State private var start = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
    @State private var end = Date()
    @State private var historyLimit = 12
    @State private var component = 0
    @State private var muscle = MuscleGroup.chest
    @State private var quality: [QualityHistoryObservation] = []
    @State private var load: TrainingLoad?
    private let components = ["Overall", "Volume", "Intensity", "Rest Rhythm", "Program balance"]
    private var interval: DateInterval { period.interval(now: Date(), firstDate: viewModel.completedHistory.map(\.trainingDate).min(), customStart: start, customEnd: end) }
    private var observations: [QualityHistoryObservation] { quality.filter { $0.workout.trainingDate >= interval.start && $0.workout.trainingDate <= interval.end } }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                AnalyticsPanel(title: kind.rawValue) {
                    HistoryPeriodControl(period: $period, start: $start, end: $end)
                    Text("\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(interval.end.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(STColors.textSecondary)
                    switch kind {
                    case .quality: qualityChart
                    case .load: loadChart
                    case .coverage: coverageChart
                    }
                }
                if kind == .quality {
                    AnalyticsPanel(title: "Session scores") {
                        Text("\(observations.filter { !$0.score.isProvisional }.count) measured of \(observations.count) scored sessions in this range").font(.caption)
                        ForEach(Array(observations.reversed().prefix(historyLimit))) { observation in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    let score = observation.score
                                    Text(String(format: "Volume %.0f · Intensity %.0f · Rest %.0f · Balance %.0f", score.volumeScore, score.intensityScore, score.consistencyScore, score.balanceScore))
                                    ForEach(score.provisionalReasons ?? [], id: \.self) { Text($0) }
                                    NavigationLink("Open logged workout") { HistoryWorkoutEvidenceView(workout: observation.workout, weightUnit: viewModel.weightUnit, bodyWeightKg: viewModel.resolvedBodyWeightKg) }
                                }.font(.caption)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(observation.workout.trainingDate.formatted(date: .abbreviated, time: .omitted))
                                    Text("\(observation.workout.name) · \(Int(observation.score.overallScore))/100\(observation.score.isProvisional ? " · provisional" : "")").font(.caption).foregroundStyle(STColors.textSecondary)
                                }
                            }
                        }
                    }
                    if observations.count > historyLimit { Button("Show more session scores") { historyLimit += 20 } }
                }
            }.padding(18)
        }.background(STColors.background.ignoresSafeArea()).foregroundStyle(STColors.textPrimary)
            .preferredColorScheme(.dark).tint(STColors.primary).safeAreaPadding(.bottom, 24)
            .navigationTitle(kind.rawValue).navigationBarTitleDisplayMode(.inline).stNavigationBarStyle()
            .task {
                if kind == .quality { quality = viewModel.historicalQuality() }
                if kind == .load { load = viewModel.historicalLoad() }
            }
    }
    @ViewBuilder private var qualityChart: some View {
        Picker("Component", selection: $component) { ForEach(components.indices, id: \.self) { Text(components[$0]).tag($0) } }
        Chart {
            ForEach(observations) { observation in
                let score = observation.score
                let value = [score.overallScore, score.volumeScore, score.intensityScore, score.consistencyScore, score.balanceScore][component]
                PointMark(x: .value("Session", observation.workout.trainingDate), y: .value("Score", value))
                    .foregroundStyle(score.isProvisional ? STColors.textSecondary.opacity(0.5) : STColors.textSecondary)
                if let aggregate = observation.aggregate {
                    LineMark(x: .value("Session", observation.workout.trainingDate), y: .value("Score", aggregate[component])).foregroundStyle(STColors.primary)
                }
            }
        }.chartYScale(domain: 0...100).frame(height: 230)
        if let latest = observations.last(where: { $0.aggregate != nil }), let values = latest.aggregate {
            Text(String(format: "Last displayed smoothed score: %.1f / 100", values[component])).font(.subheadline)
        }
        if observations.isEmpty { Text("No scored sessions in this range.") }
        Text("Dots: session scores. Yellow: full-history smoothed score. Filtering dates does not restart the calculation. Four equal components; each new measured score carries 30% weight after the initial two-session average. Provisional sessions are omitted from the line when measured history exists.").font(.caption).foregroundStyle(STColors.textSecondary)
    }
    @ViewBuilder private var loadChart: some View {
        let days = (load?.history ?? []).filter { $0.date >= Calendar.current.startOfDay(for: interval.start) && $0.date <= interval.end }
        if days.isEmpty { Text("Building baseline: eight sessions spanning at least two weeks are needed.") }
        else {
            Chart(days) { day in
                LineMark(x: .value("Date", day.date), y: .value("Load index", day.recent)).foregroundStyle(by: .value("Series", "Recent"))
                LineMark(x: .value("Date", day.date), y: .value("Load index", day.baseline)).foregroundStyle(by: .value("Series", "Baseline"))
            }.chartForegroundStyleScale(["Recent": STColors.primary, "Baseline": STColors.textSecondary]).frame(height: 240)
            if let latest = days.last { Text(String(format: "Last displayed indices: %.1f recent / %.1f baseline", latest.recent, latest.baseline)).font(.subheadline) }
        }
        Text("Unchanged 7/28-day-span daily EWMAs, including rest days. Full history is calculated before filtering. Today's load is partial. Retrospectively standardized using current exercise bests and resolved bodyweight; these are training indices, not kg or recovery measurements.").font(.caption).foregroundStyle(STColors.textSecondary)
    }
    @ViewBuilder private var coverageChart: some View {
        Picker("Muscle", selection: $muscle) { ForEach(MuscleGroup.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
        let weeks = MuscleHistoryCalculator.weeks(workouts: viewModel.completedHistory, muscle: muscle, interval: interval)
        Chart(weeks) { week in
            BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Sets", week.direct)).foregroundStyle(by: .value("Attribution", "Direct"))
            BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Sets", week.indirect)).foregroundStyle(by: .value("Attribution", "Indirect"))
        }.chartForegroundStyleScale(["Direct": STColors.primary, "Indirect": STColors.textSecondary.opacity(0.5)]).environment(\.calendar, Calendar.mondayStart).frame(height: 240)
        Text(String(format: "%.0f direct sets + %.1f indirect credits in selected dates", weeks.reduce(0) { $0 + $1.direct }, weeks.reduce(0) { $0 + $1.indirect })).font(.subheadline)
        Text("Weekly totals, Monday start. Edge weeks include only the selected dates and may be partial. Empty weeks mean no logged sets. Direct = one per working set; secondary muscles share 0.5 indirect credit. These are exposure estimates, not equal muscle stimulus. Deload activity is included.").font(.caption).foregroundStyle(STColors.textSecondary)
        DisclosureGroup("Weekly values") {
            ForEach(weeks.reversed()) { week in
                LabeledContent(week.date.formatted(date: .abbreviated, time: .omitted), value: String(format: "%.0f + %.1f", week.direct, week.indirect)).font(.caption)
            }
        }
    }
}
