import Testing
import Foundation
@testable import StrengthTrackerShared

@Suite("ExerciseListViewModel")
@MainActor
struct ExerciseListViewModelTests {

    // MARK: - Helpers

    private func makeExercise(
        name: String = "Bench Press",
        category: ExerciseCategory = .barbell,
        primaryMuscleGroup: MuscleGroup = .chest
    ) -> Exercise {
        Exercise(
            id: UUID(),
            name: name,
            primaryMuscleGroup: primaryMuscleGroup,
            secondaryMuscleGroups: [],
            category: category,
            exerciseType: .weightedReps,
            instructions: nil,
            isCustom: false,
            isArchived: false
        )
    }

    private func makeViewModel() -> (ExerciseListViewModel, InMemoryExerciseRepository) {
        let repo = InMemoryExerciseRepository()
        let vm = ExerciseListViewModel(exerciseRepository: repo)
        return (vm, repo)
    }

    // MARK: - Initial State

    @Test("Initial state has empty exercises, no loading, no error")
    func initialState() {
        let (vm, _) = makeViewModel()
        #expect(vm.exercises.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.searchText == "")
        #expect(vm.selectedCategory == nil)
        #expect(vm.selectedMuscleGroup == nil)
    }

    // MARK: - loadExercises

    @Test("loadExercises populates exercises from repository")
    func loadExercises() async throws {
        let (vm, repo) = makeViewModel()
        _ = try await repo.save(makeExercise(name: "Bench Press"))
        _ = try await repo.save(makeExercise(name: "Squat"))

        await vm.loadExercises()

        #expect(vm.exercises.count == 2)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Filtering

    @Test("searchText filters exercises by name case-insensitive")
    func searchFilter() async throws {
        let (vm, repo) = makeViewModel()
        _ = try await repo.save(makeExercise(name: "Bench Press"))
        _ = try await repo.save(makeExercise(name: "Incline Bench"))
        _ = try await repo.save(makeExercise(name: "Squat"))

        await vm.loadExercises()
        vm.searchText = "bench"

        #expect(vm.filteredExercises.count == 2)
        #expect(vm.filteredExercises.allSatisfy { $0.name.lowercased().contains("bench") })
    }

    @Test("selectedCategory filters by ExerciseCategory")
    func categoryFilter() async throws {
        let (vm, repo) = makeViewModel()
        _ = try await repo.save(makeExercise(name: "Bench", category: .barbell))
        _ = try await repo.save(makeExercise(name: "Curl", category: .dumbbell))
        _ = try await repo.save(makeExercise(name: "Squat", category: .barbell))

        await vm.loadExercises()
        vm.selectedCategory = .barbell

        #expect(vm.filteredExercises.count == 2)
        #expect(vm.filteredExercises.allSatisfy { $0.category == .barbell })
    }

    @Test("selectedMuscleGroup filters by primary MuscleGroup")
    func muscleGroupFilter() async throws {
        let (vm, repo) = makeViewModel()
        _ = try await repo.save(makeExercise(name: "Bench", primaryMuscleGroup: .chest))
        _ = try await repo.save(makeExercise(name: "Row", primaryMuscleGroup: .back))

        await vm.loadExercises()
        vm.selectedMuscleGroup = .chest

        #expect(vm.filteredExercises.count == 1)
        #expect(vm.filteredExercises[0].primaryMuscleGroup == .chest)
    }

    @Test("Combined filters work together")
    func combinedFilters() async throws {
        let (vm, repo) = makeViewModel()
        _ = try await repo.save(makeExercise(name: "Barbell Bench", category: .barbell, primaryMuscleGroup: .chest))
        _ = try await repo.save(makeExercise(name: "DB Bench", category: .dumbbell, primaryMuscleGroup: .chest))
        _ = try await repo.save(makeExercise(name: "Barbell Row", category: .barbell, primaryMuscleGroup: .back))
        _ = try await repo.save(makeExercise(name: "Squat", category: .barbell, primaryMuscleGroup: .quadriceps))

        await vm.loadExercises()
        vm.searchText = "bench"
        vm.selectedCategory = .barbell

        #expect(vm.filteredExercises.count == 1)
        #expect(vm.filteredExercises[0].name == "Barbell Bench")
    }

    @Test("Empty search text returns all exercises")
    func emptySearch() async throws {
        let (vm, repo) = makeViewModel()
        _ = try await repo.save(makeExercise(name: "Bench"))
        _ = try await repo.save(makeExercise(name: "Squat"))

        await vm.loadExercises()
        vm.searchText = ""

        #expect(vm.filteredExercises.count == 2)
    }

    @Test("Clearing filters shows all exercises")
    func clearFilters() async throws {
        let (vm, repo) = makeViewModel()
        _ = try await repo.save(makeExercise(name: "Bench", category: .barbell))
        _ = try await repo.save(makeExercise(name: "Curl", category: .dumbbell))

        await vm.loadExercises()
        vm.selectedCategory = .barbell
        #expect(vm.filteredExercises.count == 1)

        vm.selectedCategory = nil
        #expect(vm.filteredExercises.count == 2)
    }

    // MARK: - saveExercise upsert

    @Test("Saving the same exercise id twice updates in place — no duplicate row")
    func saveExerciseUpserts() async {
        let (vm, _) = makeViewModel()
        var exercise = makeExercise(name: "Glute Drive", category: .machine)

        await vm.saveExercise(exercise)
        #expect(vm.exercises.count == 1)

        exercise.equipmentBrand = "Hammer Strength"
        exercise.loadingType = .plateLoaded
        await vm.saveExercise(exercise)

        #expect(vm.exercises.count == 1)
        #expect(vm.exercises[0].equipmentBrand == "Hammer Strength")
        #expect(vm.exercises[0].loadingType == .plateLoaded)
    }

    @Test("Renaming via save re-sorts the list")
    func saveExerciseResorts() async {
        let (vm, _) = makeViewModel()
        var abduction = makeExercise(name: "Abduction")
        await vm.saveExercise(abduction)
        await vm.saveExercise(makeExercise(name: "Curl"))
        #expect(vm.exercises.map(\.name) == ["Abduction", "Curl"])

        abduction.name = "Zercher Squat"
        await vm.saveExercise(abduction)
        #expect(vm.exercises.map(\.name) == ["Curl", "Zercher Squat"])
    }
}
