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
                    AnalyticsPanel(title: "Exercise progress") {
                        Text("Recent 12 weeks · estimated strength").font(.caption).foregroundStyle(STColors.textSecondary)
                        if viewModel.insights.overloadTrends.isEmpty { Text("At least four observed weeks per exercise are needed.").font(.subheadline) }
                        ForEach(viewModel.insights.overloadTrends.prefix(4)) { trend in
                            NavigationLink { AnalyticsExerciseTrendView(trend: trend, viewModel: viewModel) } label: { AnalyticsTrendRow(trend: trend, viewModel: viewModel) }
                        }
                        NavigationLink("View all exercises") { AnalyticsProgressList(viewModel: viewModel) }
                    }.id("progress")
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
    var body: some View {
        let trends = viewModel.insights.overloadTrends.filter { query.isEmpty || $0.exerciseName.localizedCaseInsensitiveContains(query) }
        List {
            Section {
                ForEach(trends) { trend in
                    NavigationLink { AnalyticsExerciseTrendView(trend: trend, viewModel: viewModel) } label: {
                        AnalyticsTrendRow(trend: trend, viewModel: viewModel).padding(.vertical, 4)
                    }
                    .listRowBackground(STColors.surface)
                    .listRowSeparatorTint(STColors.textSecondary.opacity(0.2))
                }
                if trends.isEmpty { Text("No matching exercises").foregroundStyle(STColors.textSecondary).listRowBackground(STColors.surface) }
            } header: { Text("Estimated strength · recent 12 weeks").foregroundStyle(STColors.textSecondary) }
        }
        .scrollContentBackground(.hidden).background(STColors.background.ignoresSafeArea())
        .preferredColorScheme(.dark).tint(STColors.primary)
        .safeAreaPadding(.bottom, 24)
        .searchable(text: $query, prompt: "Find an exercise").navigationTitle("Exercise progress").stNavigationBarStyle()
    }
}
struct AnalyticsExerciseTrendView: View {
    let trend: OverloadTrend
    let viewModel: WorkoutAnalyticsViewModel
    @State private var fullHistory = false
    var body: some View {
        ScrollView {
            AnalyticsPanel(title: trend.exerciseName) {
                Text(trend.statusLabel).foregroundStyle(AnalyticsColors.trend(trend.trendStatus)).font(.title3)
                Text("\(viewModel.formatSlope(trend.slopePerWeek)) · recent 12-week estimate").font(.subheadline)
                if let margin = trend.slopeMargin {
                    Text("Slope uncertainty: \(viewModel.formatSlope(trend.slopePerWeek - margin)) to \(viewModel.formatSlope(trend.slopePerWeek + margin)) · \(trend.observationCount ?? 0) recent observed weeks").font(.caption)
                }
                Toggle("Show full history", isOn: $fullHistory)
                Chart(fullHistory ? trend.weeklyE1RMs : trend.recentWeeklyE1RMs, id: \.weekStart) { point in
                    LineMark(x: .value("Week", point.weekStart), y: .value("Estimated 1RM", viewModel.weightUnit.fromKg(point.e1rm)))
                        .foregroundStyle(STColors.primary)
                    PointMark(x: .value("Week", point.weekStart), y: .value("Estimated 1RM", viewModel.weightUnit.fromKg(point.e1rm))).foregroundStyle(STColors.primary)
                }.chartYAxisLabel("Estimated 1RM (\(viewModel.weightUnit.symbol))").frame(height: 220)
                if let last = trend.weeklyE1RMs.last { Text("Last observed week: \(last.weekStart.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
                DisclosureGroup("Understanding this estimate") {
                    Text("Classification uses actual elapsed weeks, a relative meaningful-change floor and regression uncertainty. Maintaining is neutral; unclear means the data cannot establish a direction. Estimates above 15 reps and movements where technique, leverage or speed changes are limited proxies. An e1RM trend does not measure jump power.").font(.subheadline).foregroundStyle(STColors.textSecondary)
                }
            }.padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(STColors.background.ignoresSafeArea()).foregroundStyle(STColors.textPrimary)
        .preferredColorScheme(.dark).tint(STColors.primary)
        .safeAreaPadding(.bottom, 24)
        .navigationTitle("Progress detail").navigationBarTitleDisplayMode(.inline).stNavigationBarStyle()
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
