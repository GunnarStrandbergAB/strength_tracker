#if canImport(SwiftUI)
import SwiftUI
import StrengthTrackerShared

struct SetInputSheet: View {
    let exerciseId: UUID
    let exerciseName: String
    let previousSet: ExerciseSet?
    let onLog: (Double?, Int?, SetType, Double?) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var weight: String = ""
    @State private var reps: String = ""
    @State private var setType: SetType = .normal
    @State private var rpe: Double = 7.0
    @State private var includeRPE = false
    @State private var isLogging = false

    init(
        exerciseId: UUID,
        exerciseName: String,
        previousSet: ExerciseSet? = nil,
        onLog: @escaping (Double?, Int?, SetType, Double?) async -> Void
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.previousSet = previousSet
        self.onLog = onLog

        if let previous = previousSet {
            _weight = State(initialValue: previous.weight.map { String(format: "%.1f", $0) } ?? "")
            _reps = State(initialValue: previous.reps.map { String($0) } ?? "")
            _setType = State(initialValue: previous.setType)
            if let previousRPE = previous.rpe {
                _rpe = State(initialValue: previousRPE)
                _includeRPE = State(initialValue: true)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exerciseName)
                        .font(.headline)
                }

                Section("Set Details") {
                    HStack {
                        Text("Weight")
                            .frame(width: 80, alignment: .leading)
                        TextField("0", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.semibold)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Reps")
                            .frame(width: 80, alignment: .leading)
                        TextField("0", text: $reps)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.semibold)
                        Text("reps")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Set Type") {
                    Picker("Type", selection: $setType) {
                        ForEach(SetType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Track RPE", isOn: $includeRPE)

                    if includeRPE {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("RPE")
                                Spacer()
                                Text(String(format: "%.0f", rpe))
                                    .font(.headline)
                                    .monospacedDigit()
                            }

                            Slider(value: $rpe, in: 1...10, step: 0.5)

                            HStack {
                                Text("1")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("10")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("RPE (Rate of Perceived Exertion)")
                } footer: {
                    if includeRPE {
                        Text("1 = Very easy, 10 = Maximum effort")
                    }
                }

                if let previous = previousSet, previous.weight != nil || previous.reps != nil {
                    Section("Previous Set") {
                        HStack {
                            if let w = previous.weight {
                                Text("\(String(format: "%.1f", w)) kg")
                            }
                            if previous.weight != nil && previous.reps != nil {
                                Text("×")
                                    .foregroundStyle(.secondary)
                            }
                            if let r = previous.reps {
                                Text("\(r) reps")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Log Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLogging)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Log Set") {
                        logSet()
                    }
                    .fontWeight(.semibold)
                    .disabled(isLogging || !isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !weight.isEmpty || !reps.isEmpty
    }

    private func logSet() {
        guard !isLogging else { return }

        isLogging = true

        let weightValue = Double(weight)
        let repsValue = Int(reps)
        let rpeValue = includeRPE ? rpe : nil

        Task {
            await onLog(weightValue, repsValue, setType, rpeValue)
            dismiss()
        }
    }
}
#endif
