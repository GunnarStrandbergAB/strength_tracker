import SwiftUI
import StrengthTrackerShared

struct ExerciseDetailView: View {
    let exercise: Exercise
    var progressViewModel: ProgressViewModel? = nil
    var analyticsViewModel: WorkoutAnalyticsViewModel? = nil
    var personalRecordService: PersonalRecordService? = nil

    @State private var records: [PersonalRecord] = []
    @State private var showAddPR = false

    private var weightUnit: WeightUnit {
        progressViewModel?.weightUnit ?? analyticsViewModel?.weightUnit ?? .kg
    }

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Category", value: exercise.category.rawValue.capitalized)
                LabeledContent("Type", value: exercise.exerciseType.rawValue.capitalized)
            }

            Section("Muscle Groups") {
                LabeledContent("Primary", value: exercise.primaryMuscleGroup.rawValue.capitalized)
                if !exercise.secondaryMuscleGroups.isEmpty {
                    LabeledContent("Secondary") {
                        Text(
                            exercise.secondaryMuscleGroups
                                .map { $0.rawValue.capitalized }
                                .joined(separator: ", ")
                        )
                    }
                }
            }

            if let instructions = exercise.instructions {
                Section("Instructions") {
                    Text(instructions)
                }
            }

            if personalRecordService != nil {
                Section("Personal Records") {
                    if records.isEmpty {
                        Text("No records yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bestByType, id: \.recordType) { record in
                            LabeledContent(record.recordType.displayName) {
                                Text(record.formattedValue(weightUnit: weightUnit))
                                    .fontWeight(.semibold)
                            }
                        }
                    }

                    Button {
                        showAddPR = true
                    } label: {
                        Label("Add PR", systemImage: "plus.circle")
                    }
                }
            }

            if let progressVM = progressViewModel {
                Section("Progress") {
                    NavigationLink {
                        ExerciseProgressView(viewModel: progressVM, exercise: exercise)
                    } label: {
                        Label("View Progress Chart", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            }

            if let analyticsVM = analyticsViewModel {
                Section("Insights") {
                    ExerciseInsightsView(exercise: exercise, viewModel: analyticsVM)
                }
            }
        }
        .navigationTitle(exercise.name)
        .task {
            await loadRecords()
        }
        .sheet(isPresented: $showAddPR) {
            AddPRSheet(exercise: exercise, personalRecordService: personalRecordService!, weightUnit: weightUnit) { newRecord in
                records.append(newRecord)
            }
        }
    }

    private func loadRecords() async {
        guard let service = personalRecordService else { return }
        records = (try? await service.getRecords(for: exercise.id)) ?? []
    }

    /// Returns the best (most recent) record per type for display.
    private var bestByType: [PersonalRecord] {
        var best: [RecordType: PersonalRecord] = [:]
        for record in records {
            if let existing = best[record.recordType] {
                if record.achievedAt > existing.achievedAt {
                    best[record.recordType] = record
                }
            } else {
                best[record.recordType] = record
            }
        }
        return best.values.sorted { $0.recordType.sortOrder < $1.recordType.sortOrder }
    }
}

// MARK: - Add PR Sheet

private struct AddPRSheet: View {
    let exercise: Exercise
    let personalRecordService: PersonalRecordService
    var weightUnit: WeightUnit = .kg
    let onSave: (PersonalRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: RecordType = .estimatedOneRepMax
    @State private var valueText = ""

    private let availableTypes: [RecordType] = [.estimatedOneRepMax, .maxWeight, .maxReps]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Record Type", selection: $selectedType) {
                    ForEach(availableTypes, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                HStack {
                    Text(selectedType.unitLabel(weightUnit: weightUnit))
                        .foregroundStyle(.secondary)
                    TextField("Value", text: $valueText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("Add Personal Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value = Double(valueText), value > 0 else { return }
                        // Weight-based records are persisted in kg; convert user input.
                        let storedValue: Double
                        switch selectedType {
                        case .estimatedOneRepMax, .maxWeight, .maxVolume, .maxTotalVolume:
                            storedValue = weightUnit.toKg(value)
                        default:
                            storedValue = value
                        }
                        let record = PersonalRecord(
                            id: UUID(),
                            exerciseId: exercise.id,
                            recordType: selectedType,
                            value: storedValue,
                            setId: nil,
                            achievedAt: Date()
                        )
                        Task {
                            _ = try? await personalRecordService.saveManualRecord(record)
                            onSave(record)
                            dismiss()
                        }
                    }
                    .disabled(Double(valueText) == nil || (Double(valueText) ?? 0) <= 0)
                }
            }
        }
    }
}

// MARK: - RecordType Helpers

extension RecordType {
    var displayName: String {
        switch self {
        case .estimatedOneRepMax: return "Est. 1RM"
        case .maxWeight: return "Max Weight"
        case .maxReps: return "Max Reps"
        case .maxVolume: return "Max Volume"
        case .maxTotalVolume: return "Max Total Volume"
        case .bestPace: return "Best Pace"
        case .longestDuration: return "Longest Duration"
        case .longestDistance: return "Longest Distance"
        }
    }

    func unitLabel(weightUnit: WeightUnit = .kg) -> String {
        switch self {
        case .estimatedOneRepMax, .maxWeight: return weightUnit.symbol
        case .maxReps: return "reps"
        case .maxVolume, .maxTotalVolume: return weightUnit.symbol
        case .bestPace: return "min/km"
        case .longestDuration: return "seconds"
        case .longestDistance: return "meters"
        }
    }

    var sortOrder: Int {
        switch self {
        case .estimatedOneRepMax: return 0
        case .maxWeight: return 1
        case .maxReps: return 2
        case .maxVolume: return 3
        case .maxTotalVolume: return 4
        case .bestPace: return 5
        case .longestDuration: return 6
        case .longestDistance: return 7
        }
    }
}

extension PersonalRecord {
    func formattedValue(weightUnit: WeightUnit = .kg) -> String {
        switch recordType {
        case .maxReps:
            return "\(Int(value))"
        case .estimatedOneRepMax, .maxWeight, .maxVolume, .maxTotalVolume:
            return weightUnit.format(value)
        default:
            return String(format: "%g", value)
        }
    }
}
