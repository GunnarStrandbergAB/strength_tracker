#if canImport(SwiftUI)
import SwiftUI
import Charts
import StrengthTrackerShared

/// Both the exercise library and analytics use ExerciseHistoryDetailView below.
struct ExerciseProgressView: View {
    @Environment(DataRevision.self) private var dataRevision: DataRevision?
    @State private var viewModel: ProgressViewModel
    init(viewModel: ProgressViewModel, exercise: Exercise? = nil) {
        self._viewModel = State(initialValue: viewModel)
        if let exercise { viewModel.selectedExercise = exercise }
    }
    var body: some View {
        Group {
            if let exercise = viewModel.selectedExercise {
                ExerciseHistoryDetailView(exercise: exercise, workouts: viewModel.completedHistory,
                    bodyWeightKg: viewModel.resolvedBodyWeightKg, weightUnit: viewModel.weightUnit)
                    .id(exercise.id)
            } else {
                List(viewModel.exercises) { exercise in
                    Button(exercise.name) { viewModel.selectedExercise = exercise }
                }.scrollContentBackground(.hidden).background(STColors.background)
            }
        }
        .overlay { if viewModel.isLoading { ProgressView() } }
        .safeAreaInset(edge: .top) {
            if let error = viewModel.errorMessage { Text(error).font(.caption).padding().background(STColors.surface) }
        }
        .task(id: dataRevision?.value ?? 0) {
            await viewModel.loadExercises()
            if let exercise = viewModel.selectedExercise { await viewModel.loadProgression(for: exercise.id) }
        }
        .onChange(of: viewModel.selectedExercise?.id) { _, id in
            if let id { Task { await viewModel.loadProgression(for: id) } }
        }
    }
}

struct HistoryPeriodControl: View {
    @Binding var period: HistoryPeriod
    @Binding var start: Date
    @Binding var end: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("History period", selection: $period) {
                ForEach([HistoryPeriod.fourWeeks, .threeMonths, .sixMonths, .year, .all], id: \.self) { Text($0.rawValue).tag($0) }
                if period == .yearToDate || period == .custom { Text(period.rawValue).tag(period) }
            }.pickerStyle(.segmented)
            Menu {
                Button("Year to date") { period = .yearToDate }
                Button("Custom dates") { period = .custom }
            } label: { Label("More date ranges", systemImage: "calendar").font(.caption) }
            if period == .custom {
                DatePicker("From", selection: $start, in: ...Date(), displayedComponents: .date)
                DatePicker("Through", selection: $end, in: start...max(start, Date()), displayedComponents: .date)
            }
        }.onChange(of: start) { _, value in if end < value { end = value } }
    }
}

struct ExerciseHistoryDetailView: View {
    let exercise: Exercise
    let workouts: [Workout]
    let bodyWeightKg: Double
    let weightUnit: WeightUnit
    var suppliedTrend: OverloadTrend? = nil
    @State private var period = HistoryPeriod.threeMonths
    @State private var start = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
    @State private var end = Date()
    @State private var smooth = false
    @State private var selectedDate: Date?
    @State private var historyLimit = 12
    @AppStorage private var targetReps: Int
    @AppStorage private var targetWeight: Double
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage private var storedMetric: String
    @AppStorage(ExerciseHistoryPreferences.pinsKey) private var pins = ""
    init(exercise: Exercise, workouts: [Workout], bodyWeightKg: Double, weightUnit: WeightUnit, suppliedTrend: OverloadTrend? = nil) {
        self.exercise = exercise; self.workouts = workouts; self.bodyWeightKg = bodyWeightKg; self.weightUnit = weightUnit; self.suppliedTrend = suppliedTrend
        _targetReps = AppStorage(wrappedValue: 5, "analytics.history.reps.\(exercise.id.uuidString)")
        _targetWeight = AppStorage(wrappedValue: -1, "analytics.history.load.\(exercise.id.uuidString)")
        _storedMetric = AppStorage(wrappedValue: ExerciseHistoryMetric.available(for: exercise.exerciseType)[0].rawValue, ExerciseHistoryPreferences.metricKey(exercise.id))
    }
    private var metric: ExerciseHistoryMetric {
        let available = ExerciseHistoryMetric.available(for: exercise.exerciseType)
        return available.first { $0.rawValue == storedMetric } ?? available[0]
    }
    private var sessions: [ExerciseHistorySession] { ExerciseHistoryCalculator.sessions(exerciseId: exercise.id, workouts: workouts, bodyWeightKg: bodyWeightKg) }
    private var interval: DateInterval { period.interval(now: Date(), firstDate: sessions.first?.date, customStart: start, customEnd: end) }
    private var allPoints: [HistoryPoint] { ExerciseHistoryCalculator.points(sessions: sessions, metric: metric, targetReps: targetReps, targetWeightKg: targetWeight) }
    private var points: [HistoryPoint] { allPoints.filter { $0.date >= interval.start && $0.date <= interval.end } }
    private var visibleSessions: [ExerciseHistorySession] { sessions.filter { $0.date >= interval.start && $0.date <= interval.end } }
    private var trend: OverloadTrend? { suppliedTrend ?? OverloadTrackingService.computeOverloadTrends(workouts: workouts, bodyWeightKg: bodyWeightKg).first { $0.exerciseId == exercise.id } }
    private var units: String {
        switch metric {
        case .volume: return "\(weightUnit.symbol) × reps"
        case .strength, .weightAtReps: return weightUnit.symbol
        case .repsAtWeight: return "reps"
        case .sets: return "sets"
        case .duration: return "min"
        case .distance: return "m"
        }
    }
    private func display(_ value: Double) -> Double { metric.usesWeight ? weightUnit.fromKg(value) : metric == .duration ? value / 60 : value }
    private func formatted(_ value: Double) -> String { String(format: "%.1f %@", display(value), units) }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                AnalyticsPanel(title: exercise.name) {
                    HistoryPeriodControl(period: $period, start: $start, end: $end)
                    Picker("Metric", selection: $storedMetric) {
                        ForEach(ExerciseHistoryMetric.available(for: exercise.exerciseType), id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                    }.tint(STColors.primary)
                    if metric == .weightAtReps { Stepper("Exactly \(targetReps) reps", value: $targetReps, in: 1...50) }
                    if metric == .repsAtWeight {
                        Picker("Effective load", selection: $targetWeight) {
                            ForEach(Array(Set(sessions.flatMap(\.loadParts).map(\.load))).sorted(), id: \.self) { value in Text(weightUnit.format(value, decimals: 1)).tag(value) }
                        }
                    }
                    historyChart
                }
                if metric.isPerformance {
                    AnalyticsPanel(title: "Recent training direction") {
                        if let trend {
                            Text(trend.statusLabel).font(.title3.bold()).foregroundStyle(AnalyticsColors.trend(trend.trendStatus))
                            Text(String(format: "%+.2f%%/week · %d observed weeks", trend.percentPerWeek, trend.observationCount ?? 0))
                        } else { Text("Building evidence") }
                        Text("The existing recent 12-week estimated-strength classification. Changing this chart's metric or dates does not change that verdict.").font(.caption).foregroundStyle(STColors.textSecondary)
                    }
                }
                AnalyticsPanel(title: "Session history") {
                    Text("\(visibleSessions.count) sessions in selected dates · tap to inspect logged sets").font(.caption).foregroundStyle(STColors.textSecondary)
                    ForEach(Array(visibleSessions.reversed().prefix(historyLimit))) { session in
                        NavigationLink {
                            HistoryWorkoutEvidenceView(workout: session.workout, weightUnit: weightUnit, bodyWeightKg: bodyWeightKg)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                    Spacer()
                                    if let value = session.value(for: metric, targetReps: targetReps, targetWeightKg: targetWeight) { Text(formatted(value)).monospacedDigit() }
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                                Text("\(session.workout.name) · \(session.sets.count) working sets\(session.workout.isDeload ? " · Deload" : "")").font(.caption).foregroundStyle(STColors.textSecondary)
                            }.padding(.vertical, 6)
                        }.foregroundStyle(STColors.textPrimary)
                    }
                }
                if visibleSessions.count > historyLimit { Button("Show more sessions (\(visibleSessions.count - historyLimit) remaining)") { historyLimit += 20 }.font(.subheadline) }
                if metric.usesWeight || metric == .repsAtWeight { averages }
                AnalyticsPanel(title: "How to read this") {
                    Text("One observation per session. Warm-ups and incomplete sets are excluded; drop segments count once. Estimated strength uses the existing e1RM formula (reps capped at 15); it is a limited proxy for high-rep, technique-sensitive and explosive movements.")
                    Text("Weight at reps uses the heaviest recorded segment at exactly the selected reps. Reps at weight uses the most reps at exactly the selected effective load. Duration and distance are recorded activity totals, not performance scores.")
                    Text("Grey points mark deloads. They remain in activity totals but are excluded from performance comparisons and median smoothing. Missing observations are not zero. Lines and medians restart after a gap over 21 days.")
                    if exercise.exerciseType == .bodyweightReps {
                        Text("Effective load = current resolved bodyweight × exercise factor + added weight (negative added weight is assistance). Historical values use today's \(weightUnit.format(bodyWeightKg, decimals: 1)) bodyweight retrospectively; they are not historical weigh-ins.")
                    }
                }.font(.caption).foregroundStyle(STColors.textSecondary)
            }.padding(18)
        }
        .background(STColors.background.ignoresSafeArea()).foregroundStyle(STColors.textPrimary)
        .preferredColorScheme(.dark).tint(STColors.primary).safeAreaPadding(.bottom, 24)
        .navigationTitle("Exercise history").navigationBarTitleDisplayMode(.inline).stNavigationBarStyle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let pinned = ExerciseHistoryPreferences.pins(from: pins).contains(exercise.id)
                Button { pins = ExerciseHistoryPreferences.toggling(exercise.id, in: pins) } label: { Image(systemName: pinned ? "pin.fill" : "pin") }
                    .accessibilityLabel(pinned ? "Unpin exercise" : "Pin exercise")
                    .disabled(!pinned && ExerciseHistoryPreferences.pins(from: pins).count >= 4)
            }
        }
        .onAppear { initializeTargetWeight() }
        .onChange(of: workouts) { _, _ in initializeTargetWeight() }
        .onChange(of: storedMetric) { _, _ in selectedDate = nil }
        .onChange(of: period) { _, _ in selectedDate = nil }
    }
    private func initializeTargetWeight() {
        let values = Set(sessions.flatMap(\.loadParts).map(\.load))
        if !values.contains(targetWeight), let load = sessions.last?.loadParts.first?.load { targetWeight = load }
    }
    @ViewBuilder private var historyChart: some View {
        let eligible = points.filter { !metric.isPerformance || !$0.isDeload }
        if let last = eligible.last {
            Text(formatted(last.value)).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Latest observed · \(last.date.formatted(date: .abbreviated, time: .omitted))").font(.caption)
            if metric.isPerformance {
                if let change = ExerciseHistoryCalculator.performanceChange(points: points, interval: interval) {
                    Text(String(format: "%+.1f%% · first vs last three-session medians", change)).font(.subheadline)
                } else { Text("Period change needs three observations near each end of the range (six total).").font(.caption) }
            } else {
                Text("Period total: \(formatted(points.reduce(0) { $0 + $1.value }))").font(.subheadline)
                if period != .all, let change = ExerciseHistoryCalculator.activityChange(points: allPoints, interval: interval, firstLoggedDate: workouts.map(\.trainingDate).min()) {
                    Text(String(format: "%+.1f%% vs preceding equal elapsed period", change)).font(.caption)
                } else { Text("No complete preceding-period comparison available.").font(.caption) }
            }
        }
        Text("\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(interval.end.formatted(date: .abbreviated, time: .omitted)) · \(points.count) observations\(period == .custom && interval.end < Calendar.current.startOfDay(for: Date()) ? "" : " · today partial")")
            .font(.caption).foregroundStyle(STColors.textSecondary)
        if points.isEmpty { ContentUnavailableView("No matching observations", systemImage: "chart.xyaxis.line", description: Text("Try another metric, load, rep count or date range.")) }
        else {
            Chart {
                ForEach(points) { point in
                    PointMark(x: .value("Date", point.date), y: .value(units, display(point.value)))
                        .foregroundStyle(point.isDeload ? STColors.textSecondary : STColors.primary)
                        .accessibilityLabel("\(point.date.formatted(date: .abbreviated, time: .omitted)), \(formatted(point.value))\(point.isDeload ? ", deload" : "")")
                    if smooth, let median = point.median {
                        LineMark(x: .value("Date", point.date), y: .value(units, display(median)), series: .value("Segment", point.segment))
                            .foregroundStyle(STColors.primary.opacity(0.65))
                    }
                }
                if let selectedDate { RuleMark(x: .value("Selected", selectedDate)).foregroundStyle(STColors.textSecondary.opacity(0.4)) }
            }.chartXScale(domain: interval.start...max(interval.end, interval.start.addingTimeInterval(1)))
                .chartYScale(domain: .automatic(includesZero: !metric.isPerformance))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 2 : 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxisLabel(units).chartXSelection(value: $selectedDate).frame(height: 230)
            if metric.isPerformance { Text("Vertical axis fits the observations; it may start above zero.").font(.caption).foregroundStyle(STColors.textSecondary) }
            Toggle("Three-session median", isOn: $smooth).font(.caption)
            Text("Touch the chart to inspect an observation. Raw points stay visible.").font(.caption).foregroundStyle(STColors.textSecondary)
            if let selectedDate, let point = points.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }),
               let session = sessions.first(where: { $0.id == point.id }) {
                NavigationLink { HistoryWorkoutEvidenceView(workout: session.workout, weightUnit: weightUnit, bodyWeightKg: bodyWeightKg) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(session.date.formatted(date: .abbreviated, time: .omitted)) · \(formatted(point.value))", systemImage: "arrow.up.right.square")
                        Text("\(session.sets.count) working sets · open workout for recorded load, reps and RPE").font(.caption)
                    }
                }
            }
            if let best = eligible.map(\.value).max() { LabeledContent(metric.isPerformance ? "Period best" : "Largest session", value: formatted(best)).font(.caption) }
            if metric.isPerformance, let best = allPoints.filter({ !$0.isDeload }).map(\.value).max() { LabeledContent("All-time best", value: formatted(best)).font(.caption) }
        }
    }
    private var averages: some View {
        let parts = visibleSessions.flatMap(\.loadParts)
        let reps = parts.reduce(0) { $0 + $1.reps }
        let volume = parts.reduce(0.0) { $0 + $1.load * Double($1.reps) }
        let completeSets = visibleSessions.reduce(0) { $0 + $1.completeLoadSets.count }
        let completeReps = visibleSessions.reduce(0) { $0 + $1.completeLoadSets.reduce(0) { $0 + $1.totalReps } }
        let completeVolume = visibleSessions.reduce(0.0) { result, session in result + session.completeLoadSets.reduce(0) { $0 + $1.setVolume(baseLoadPerRep: session.baseLoad) } }
        return AnalyticsPanel(title: "Supporting averages · this exercise") {
            if reps > 0 { LabeledContent("Average load per rep", value: weightUnit.format(volume / Double(reps), decimals: 1)) }
            if completeSets > 0 {
                LabeledContent("Volume per complete set", value: "\(weightUnit.format(completeVolume / Double(completeSets), decimals: 1)) × reps")
                LabeledContent("Reps per complete set", value: String(format: "%.1f", Double(completeReps) / Double(completeSets)))
            }
            Text("\(reps) reps with load evidence · \(completeSets) fully recorded working sets. Load per rep = summed load × reps ÷ reps. Set averages use only complete sets, including their drop segments. Deload activity is included. These describe your exercise mix within the movement; they are not strength scores.").font(.caption).foregroundStyle(STColors.textSecondary)
        }.font(.subheadline)
    }
}

/// Read-only workout destination with explicit user units and bodyweight context.
struct HistoryWorkoutEvidenceView: View {
    let workout: Workout
    let weightUnit: WeightUnit
    let bodyWeightKg: Double
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                AnalyticsPanel(title: workout.name) {
                    Text(workout.trainingDate.formatted(date: .complete, time: .shortened))
                    if workout.isDeload { Text("Deload session").foregroundStyle(STColors.textSecondary) }
                }
                ForEach(workout.exercises) { entry in
                    AnalyticsPanel(title: entry.exercise.name) {
                        ForEach(entry.sets.filter(\.isCompleted)) { set in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Set \(set.order) · \(set.setType.rawValue)").font(.caption).foregroundStyle(STColors.textSecondary)
                                ForEach(set.effectiveParts) { part in
                                    HStack {
                                        if let load = part.effectiveLoad(baseLoadPerRep: entry.exercise.baseLoadPerRep(bodyWeightKg: bodyWeightKg)) { Text(weightUnit.format(load, decimals: 1)) }
                                        if let reps = part.reps { Text("× \(reps) reps") }
                                        if let rpe = part.intensityValue(for: .rpe) { Text(String(format: "RPE %.1f", rpe)).foregroundStyle(STColors.textSecondary) }
                                    }.font(.subheadline.monospacedDigit())
                                    if entry.exercise.exerciseType == .bodyweightReps {
                                        Text("Added: \(weightUnit.format(part.weight ?? 0, decimals: 1)) · effective load includes current bodyweight").font(.caption).foregroundStyle(STColors.textSecondary)
                                    }
                                }
                                if let seconds = set.durationSeconds { Text("\(seconds) seconds").font(.subheadline) }
                                if let meters = set.distanceMeters { Text(String(format: "%.0f m", meters)).font(.subheadline) }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }.padding(18)
        }.background(STColors.background.ignoresSafeArea()).foregroundStyle(STColors.textPrimary)
            .preferredColorScheme(.dark).safeAreaPadding(.bottom, 24)
            .navigationTitle("Logged workout").navigationBarTitleDisplayMode(.inline).stNavigationBarStyle()
    }
}
#endif
