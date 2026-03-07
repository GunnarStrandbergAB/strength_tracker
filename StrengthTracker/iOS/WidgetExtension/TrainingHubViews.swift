#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
import StrengthTrackerShared

// MARK: - Color Constants

enum WidgetColors {
    static let background = Color(red: 0.071, green: 0.071, blue: 0.071)
    static let surface = Color(white: 0.14)
    static let accent = Color(red: 0.949, green: 0.800, blue: 0.051)
    static let textPrimary = Color.white
    static let textSecondary = Color.gray
    static let textTertiary = Color(white: 0.45)

    static func highlightColor(_ name: String) -> Color {
        switch name {
        case "yellow": return accent
        case "orange": return .orange
        case "green": return .green
        case "red": return .red
        case "blue": return .blue
        default: return accent
        }
    }
}

// MARK: - Analytics Small View (Insight Card)

struct AnalyticsSmallView: View {
    let entry: TrainingHubEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetColors.accent)
                Text("TRAINING HUB")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(WidgetColors.accent)
            }

            Spacer()

            if let highlight = currentHighlight {
                Image(systemName: highlight.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(WidgetColors.highlightColor(highlight.color))

                Text(highlight.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WidgetColors.textPrimary)
                    .lineLimit(2)

                Text(highlight.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetColors.textSecondary)
                    .lineLimit(1)
            } else {
                // Fallback: show streak or workout count
                Image(systemName: "flame.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)

                Text(entry.data.currentStreak > 0 ? "\(entry.data.currentStreak)-day streak" : "Start Training")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WidgetColors.textPrimary)

                Text("\(entry.data.totalWorkoutsAllTime) total workouts")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "strengthtracker://analytics"))
    }

    private var currentHighlight: WidgetHighlight? {
        guard !entry.data.highlights.isEmpty else { return nil }
        return entry.data.highlights[entry.highlightIndex % entry.data.highlights.count]
    }
}

// MARK: - Analytics Medium View (Training Dashboard)

struct AnalyticsMediumView: View {
    let entry: TrainingHubEntry

    var body: some View {
        HStack(spacing: 12) {
            // Left: Calendar strip
            VStack(alignment: .leading, spacing: 8) {
                Text("THIS WEEK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(WidgetColors.accent)

                calendarStrip

                // Progress text
                Text("\(entry.data.weeklyWorkoutCount)/\(entry.data.weeklyGoal) sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 4)

            // Right: Highlights
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entry.data.highlights.prefix(2))) { highlight in
                    highlightRow(highlight)
                }

                if entry.data.highlights.count < 2 {
                    // Fill with stats
                    if entry.data.currentStreak > 0 {
                        statRow(icon: "flame.fill", text: "\(entry.data.currentStreak)-day streak", color: .orange)
                    }
                    if let volume = entry.data.weeklyVolume {
                        let formatted = volume >= 1000 ? String(format: "%.1fT", volume / 1000) : String(format: "%.0f kg", volume)
                        statRow(icon: "scalemass.fill", text: formatted, color: WidgetColors.accent)
                    }
                }

                Spacer(minLength: 0)

                // Next planned session
                if let session = entry.data.nextPlannedSession {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                            .foregroundStyle(WidgetColors.accent)
                        Text("Next: \(session.sessionName)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WidgetColors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "strengthtracker://analytics"))
    }

    private var calendarStrip: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 3) {
                    Text(dayLabel(index))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(WidgetColors.textTertiary)

                    Circle()
                        .fill(entry.data.weekDaysTrained[index] ? WidgetColors.accent : Color.white.opacity(0.1))
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    private func dayLabel(_ index: Int) -> String {
        ["M", "T", "W", "T", "F", "S", "S"][index]
    }

    private func highlightRow(_ highlight: WidgetHighlight) -> some View {
        HStack(spacing: 6) {
            Image(systemName: highlight.icon)
                .font(.system(size: 10))
                .foregroundStyle(WidgetColors.highlightColor(highlight.color))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(highlight.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetColors.textPrimary)
                    .lineLimit(1)
                Text(highlight.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetColors.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func statRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetColors.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - Analytics Large View (Full Dashboard)

struct AnalyticsLargeView: View {
    let entry: TrainingHubEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top: Header + Calendar + Progress Ring
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetColors.accent)
                        Text("TRAINING HUB")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(WidgetColors.accent)
                    }

                    calendarStrip
                }

                Spacer()

                progressRing
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            // Middle: Highlights
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entry.data.highlights.prefix(3))) { highlight in
                    highlightRow(highlight)
                }
                if entry.data.highlights.isEmpty {
                    emptyHighlightsView
                }
            }

            Spacer(minLength: 0)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            // Bottom: Next planned workout
            if let session = entry.data.nextPlannedSession {
                nextWorkoutSection(session)
            } else {
                HStack {
                    Spacer()
                    Link(destination: URL(string: "strengthtracker://workout")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Start Workout")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(WidgetColors.background)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(WidgetColors.accent)
                        .clipShape(Capsule())
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var calendarStrip: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 3) {
                    Text(dayLabel(index))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetColors.textTertiary)
                    Circle()
                        .fill(entry.data.weekDaysTrained[index] ? WidgetColors.accent : Color.white.opacity(0.1))
                        .frame(width: 12, height: 12)
                }
            }
        }
    }

    private var progressRing: some View {
        let progress = entry.data.weeklyGoal > 0
            ? min(Double(entry.data.weeklyWorkoutCount) / Double(entry.data.weeklyGoal), 1.0)
            : 0.0

        return ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(WidgetColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(entry.data.weeklyWorkoutCount)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetColors.textPrimary)
                Text("/\(entry.data.weeklyGoal)")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetColors.textSecondary)
            }
        }
        .frame(width: 56, height: 56)
    }

    private func highlightRow(_ highlight: WidgetHighlight) -> some View {
        HStack(spacing: 8) {
            Image(systemName: highlight.icon)
                .font(.system(size: 12))
                .foregroundStyle(WidgetColors.highlightColor(highlight.color))
                .frame(width: 20, height: 20)
                .background(WidgetColors.highlightColor(highlight.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(highlight.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetColors.textPrimary)
                    .lineLimit(1)
                Text(highlight.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var emptyHighlightsView: some View {
        VStack(spacing: 4) {
            if entry.data.currentStreak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text("\(entry.data.currentStreak)-day streak")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetColors.textPrimary)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetColors.accent)
                Text("\(entry.data.totalWorkoutsAllTime) total workouts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetColors.textPrimary)
            }
        }
    }

    private func nextWorkoutSection(_ session: WidgetPlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT SESSION")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(WidgetColors.accent)
                    Text(session.sessionName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WidgetColors.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                Link(destination: URL(string: "strengthtracker://workout/start")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("Start")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(WidgetColors.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(WidgetColors.accent)
                    .clipShape(Capsule())
                }
            }

            // Exercise preview
            HStack(spacing: 4) {
                ForEach(Array(session.exerciseNames.prefix(4).enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(WidgetColors.textSecondary)
                        .lineLimit(1)

                    if name != session.exerciseNames.prefix(4).last {
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundStyle(WidgetColors.textTertiary)
                    }
                }
            }
        }
    }

    private func dayLabel(_ index: Int) -> String {
        ["M", "T", "W", "T", "F", "S", "S"][index]
    }
}

// MARK: - Active Workout Small View

struct ActiveWorkoutSmallView: View {
    let entry: TrainingHubEntry

    var body: some View {
        guard let active = entry.data.activeWorkout else {
            return AnyView(AnalyticsSmallView(entry: entry))
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("ACTIVE")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(.green)
                }

                Spacer()

                Text(active.currentExerciseName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WidgetColors.textPrimary)
                    .lineLimit(2)

                Text("\(active.completedSets)/\(active.totalPlannedSets) sets")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetColors.accent)

                // Elapsed time
                Text(active.startedAt, style: .timer)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WidgetColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(URL(string: "strengthtracker://workout"))
        )
    }
}

// MARK: - Active Workout Medium View

struct ActiveWorkoutMediumView: View {
    let entry: TrainingHubEntry

    var body: some View {
        guard let active = entry.data.activeWorkout else {
            return AnyView(AnalyticsMediumView(entry: entry))
        }

        return AnyView(
            HStack(spacing: 12) {
                // Left: Exercise info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text(active.workoutName)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Text(active.currentExerciseName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WidgetColors.textPrimary)
                        .lineLimit(2)

                    Text("\(active.completedSets)/\(active.totalPlannedSets) sets")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WidgetColors.accent)

                    // Set target info
                    if let weight = active.nextSetWeight, let reps = active.nextSetReps {
                        Text("Next: \(String(format: "%g", weight))kg x \(reps)")
                            .font(.system(size: 11))
                            .foregroundStyle(WidgetColors.textSecondary)
                    }

                    Text(active.startedAt, style: .timer)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WidgetColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 4)

                // Right: Rest timer or action
                VStack(spacing: 8) {
                    if active.isResting, let endDate = active.restEndDate {
                        Text("REST")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(WidgetColors.accent)

                        Text(timerInterval: Date()...endDate, countsDown: true)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetColors.textPrimary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 6) {
                            Button(intent: AddRestTimeIntent()) {
                                Text("+15s")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(WidgetColors.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)

                            Button(intent: SkipRestTimerIntent()) {
                                Text("Skip")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(WidgetColors.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Spacer()

                        Text("READY")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(.green)

                        Button(intent: CompleteSetIntent()) {
                            VStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 28))
                                Text("Complete Set")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(WidgetColors.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(WidgetColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(URL(string: "strengthtracker://workout"))
        )
    }
}

// MARK: - Active Workout Large View

struct ActiveWorkoutLargeView: View {
    let entry: TrainingHubEntry

    var body: some View {
        guard let active = entry.data.activeWorkout else {
            return AnyView(AnalyticsLargeView(entry: entry))
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text(active.workoutName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(active.startedAt, style: .timer)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WidgetColors.textSecondary)
                }

                // Current exercise
                VStack(alignment: .leading, spacing: 4) {
                    Text(active.currentExerciseName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(WidgetColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        Label("\(active.completedSets)/\(active.totalPlannedSets) sets", systemImage: "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WidgetColors.accent)

                        if let weight = active.nextSetWeight, let reps = active.nextSetReps {
                            Label("\(String(format: "%g", weight))kg x \(reps)", systemImage: "scalemass")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WidgetColors.textSecondary)
                        }
                    }
                }

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                // Rest timer or complete set
                if active.isResting, let endDate = active.restEndDate {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("REST TIMER")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.0)
                                .foregroundStyle(WidgetColors.accent)

                            Text(timerInterval: Date()...endDate, countsDown: true)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(WidgetColors.textPrimary)
                        }

                        Spacer()

                        VStack(spacing: 6) {
                            Button(intent: AddRestTimeIntent()) {
                                Text("+15s")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(WidgetColors.textPrimary)
                                    .frame(width: 60)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)

                            Button(intent: SkipRestTimerIntent()) {
                                Text("Skip")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(WidgetColors.accent)
                                    .frame(width: 60)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button(intent: CompleteSetIntent()) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                Text("Complete Set")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(WidgetColors.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(WidgetColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        if active.nextExerciseName != nil {
                            Button(intent: SkipExerciseIntent()) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(WidgetColors.textSecondary)
                                    .frame(width: 44, height: 40)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                // Next exercise preview
                if let nextName = active.nextExerciseName {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(WidgetColors.textTertiary)
                        Text("Next: \(nextName)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WidgetColors.textSecondary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 11))
                            .foregroundStyle(WidgetColors.accent)
                        Text("Last exercise!")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WidgetColors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(URL(string: "strengthtracker://workout"))
        )
    }
}
#endif
