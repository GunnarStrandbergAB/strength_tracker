import Foundation

/// Turns a tool's `workout_date` / `workout_name` arguments into the right
/// `WorkoutEditor`: the active workout when no date is given, otherwise the
/// completed workout started on that day.
@MainActor
public final class WorkoutEditorResolver {
    private let workoutViewModel: WorkoutViewModel
    private let coordinator: WorkoutSessionCoordinator
    private let workoutRepository: any WorkoutRepository
    private let makeHistoryViewModel: @MainActor () -> HistoryViewModel
    private let onHistoryWorkoutChanged: ((Workout) -> Void)?
    private let calendar: Calendar

    /// One dedicated instance, reused across tool calls.
    private lazy var historyViewModel: HistoryViewModel = makeHistoryViewModel()

    public init(
        workoutViewModel: WorkoutViewModel,
        coordinator: WorkoutSessionCoordinator,
        workoutRepository: any WorkoutRepository,
        makeHistoryViewModel: @escaping @MainActor () -> HistoryViewModel,
        onHistoryWorkoutChanged: ((Workout) -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        self.workoutViewModel = workoutViewModel
        self.coordinator = coordinator
        self.workoutRepository = workoutRepository
        self.makeHistoryViewModel = makeHistoryViewModel
        self.onHistoryWorkoutChanged = onHistoryWorkoutChanged
        self.calendar = calendar
    }

    public func activeEditor() throws -> any WorkoutEditor {
        if workoutViewModel.watchActiveWorkout != nil, !workoutViewModel.isActive {
            throw WorkoutEditError.watchWorkoutInProgress
        }
        guard workoutViewModel.isActive, workoutViewModel.currentWorkout != nil else {
            throw WorkoutEditError.noActiveWorkout
        }
        return ActiveWorkoutEditor(viewModel: workoutViewModel, coordinator: coordinator)
    }

    /// `date` nil → active workout. Otherwise a completed workout started on that
    /// day (yyyy-MM-dd), disambiguated by `workoutName` when several exist.
    public func resolve(date: String?, workoutName: String?) async throws -> any WorkoutEditor {
        guard let date, !date.isEmpty else {
            return try activeEditor()
        }
        guard let day = AIJSON.parseDate(date) else {
            throw WorkoutEditError.invalidArgument("workout_date must be yyyy-MM-dd.")
        }
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let completed = try await workoutRepository.fetchByDateRange(start, end)
            .filter { $0.completedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }

        var candidates = completed
        if candidates.count > 1, let workoutName, !workoutName.isEmpty {
            let named = candidates.filter { $0.name.caseInsensitiveCompare(workoutName) == .orderedSame }
            if !named.isEmpty { candidates = named }
        }

        switch candidates.count {
        case 0:
            if let active = workoutViewModel.currentWorkout, workoutViewModel.isActive,
               calendar.isDate(active.startedAt, inSameDayAs: day) {
                throw WorkoutEditError.workoutNotFound(
                    "Only the active workout '\(active.name)' exists on \(date); omit workout_date to edit it."
                )
            }
            throw WorkoutEditError.workoutNotFound(
                "No completed workout on \(date).\(await nearbyHint(around: day))"
            )
        case 1:
            return historyEditor(for: candidates[0])
        default:
            throw WorkoutEditError.ambiguousWorkout(candidates: candidates.map(describe))
        }
    }

    /// For confirm-card execution: the workout is already known by id.
    public func resolve(workoutID: UUID) async throws -> any WorkoutEditor {
        if let active = workoutViewModel.currentWorkout, workoutViewModel.isActive, active.id == workoutID {
            return try activeEditor()
        }
        guard let workout = try await workoutRepository.fetchAll().first(where: { $0.id == workoutID }),
              workout.completedAt != nil else {
            throw WorkoutEditError.workoutNotFound("That workout no longer exists.")
        }
        return historyEditor(for: workout)
    }

    // MARK: Private

    private func historyEditor(for workout: Workout) -> HistoryWorkoutEditor {
        HistoryWorkoutEditor(viewModel: historyViewModel, workout: workout, onWorkoutChanged: onHistoryWorkoutChanged)
    }

    private func describe(_ workout: Workout) -> String {
        let time = workout.startedAt.formatted(date: .omitted, time: .shortened)
        return "'\(workout.name)' \(time) (\(workout.exercises.count) exercises)"
    }

    private func nearbyHint(around day: Date) async -> String {
        guard let start = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: day)),
              let end = calendar.date(byAdding: .day, value: 4, to: calendar.startOfDay(for: day)),
              let nearby = try? await workoutRepository.fetchByDateRange(start, end)
                .filter({ $0.completedAt != nil }),
              !nearby.isEmpty else { return "" }
        let list = nearby
            .sorted { $0.startedAt < $1.startedAt }
            .map { "\(AIJSON.dateString($0.startedAt)) '\($0.name)'" }
            .joined(separator: ", ")
        return " Nearby: \(list)."
    }
}
