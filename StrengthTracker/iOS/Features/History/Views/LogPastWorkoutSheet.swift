#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

/// Creation sheet for retroactive workout logging: pick the historical date/time,
/// a duration (never "until now" — the workout is born complete with
/// `completedAt = startedAt + duration`), and whether to write it to Apple Health.
/// On create, the caller navigates into the workout in edit mode to add exercises.
struct LogPastWorkoutSheet: View {
    let viewModel: HistoryViewModel
    let onCreated: (Workout) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var date: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var durationMinutes: Int = 60
    @State private var saveToHealthKit = false
    @State private var isCreating = false

    private var suggestedName: String {
        "Workout – \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField(suggestedName, text: $name)
                }

                Section("When") {
                    DatePicker(
                        "Date",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(STColors.primary)

                    DatePicker(
                        "Start time",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: .hourAndMinute
                    )
                    .tint(STColors.primary)

                    Picker("Duration", selection: $durationMinutes) {
                        ForEach(Array(stride(from: 15, through: 240, by: 15)), id: \.self) { minutes in
                            Text(minutes >= 60
                                 ? "\(minutes / 60)h\(minutes % 60 > 0 ? " \(minutes % 60)m" : "")"
                                 : "\(minutes)m")
                                .tag(minutes)
                        }
                    }
                }

                Section {
                    Toggle("Save to Apple Health", isOn: $saveToHealthKit)
                } footer: {
                    Text("Writes the workout to Apple Health with its past date. Leave off if Health already has an entry for this session.")
                }

                Section {
                    Button {
                        create()
                    } label: {
                        if isCreating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create & Add Exercises")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isCreating)
                }
            }
            .navigationTitle("Log Past Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedName : name
        Task {
            if let workout = await viewModel.createRetroWorkout(
                name: finalName,
                startedAt: min(date, Date()),
                duration: TimeInterval(durationMinutes * 60),
                saveToHealthKit: saveToHealthKit
            ) {
                dismiss()
                onCreated(workout)
            }
            isCreating = false
        }
    }
}

#endif
