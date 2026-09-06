import XCTest
import SwiftUI
@testable import StrengthTracker
@testable import StrengthTrackerShared

/// Production cards rendered at compact and accessibility sizes for visual review.
@MainActor
final class AnalyticsViewRenderingTests: XCTestCase {
    func testAnalyticsCardsAtPhoneAndAccessibilitySizes() async throws {
        let repo = MockWorkoutRepository()
        let quality = WorkoutQualityScoreService(workoutRepository: repo, muscleBalanceService: MuscleBalanceService(), healthKitService: MockHealthKitService(), userPreferencesService: UserPreferencesService())
        let service = WorkoutAnalyticsService(analyticsRepository: MockAnalyticsRepository(), workoutRepository: repo, exerciseRepository: MockExerciseRepository(), vectorizer: WorkoutVectorizer(), searchService: VectorSearchService(), plateauService: PlateauDetectionService(), muscleBalanceService: MuscleBalanceService(), recommendationService: ExerciseRecommendationService())
        let model = WorkoutAnalyticsViewModel(analyticsService: service, qualityScoreService: quality, featureGate: AnalyticsFeatureGate(workoutRepository: repo))
        model.insights = WorkoutInsights(generatedAt: Date(), workoutCount: 115, plateaus: [], muscleBalance: nil, recommendations: [], recoveryPatterns: [], optimalVolumes: [], trainingLoad: TrainingLoad(acuteLoad: 27, chronicLoad: 35, acwr: 0.77, loadZone: .optimal))
        model.aggregateQuality = AggregateQualityScore(ewmaOverall: 73.5, ewmaVolume: 73, ewmaIntensity: 76, ewmaBalance: 56, ewmaConsistency: 89, trendVsPrior: -6, percentileRank: 0.5, workoutsIncluded: 110, computedAt: Date())
        for (name, width, typeSize) in [("compact", 375.0, DynamicTypeSize.large), ("accessibility", 430.0, DynamicTypeSize.accessibility2)] {
            let content = VStack(spacing: 14) {
                AnalyticsLoadCard(viewModel: model)
                AnalyticsQualityCard(viewModel: model)
                AnalyticsTrendRow(trend: OverloadTrend(exerciseId: UUID(), exerciseName: "Weighted hanging knee raise with a long exercise name", weeklyE1RMs: [], slopePerWeek: 0.3, trendStatus: .progressing, overloadIndex: 1), viewModel: model)
                AdvancedInsightsCardView(viewModel: model)
            }.padding(18).background(STColors.background).foregroundStyle(STColors.textPrimary)
                .environment(\.dynamicTypeSize, typeSize).environment(\.colorScheme, .dark)
            let host = UIHostingController(rootView: content)
            let size = host.sizeThatFits(in: CGSize(width: width, height: 4000))
            XCTAssertGreaterThan(size.height, 500)
            XCTAssertLessThanOrEqual(size.width, width + 1)
            let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: width, height: size.height)))
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await Task.yield()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "analytics-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertNotNil(image.pngData())
            window.isHidden = true
        }
    }
    func testSharedExerciseHistoryAtPhoneAndAccessibilitySizes() async throws {
        let exercise = AnalyticsTestHelpers.makeExercise(name: "Weighted hanging knee raise with a long name")
        let workouts = (0..<14).map { index in
            let date = Date().addingTimeInterval(Double(index - 14) * 7 * 86400)
            return AnalyticsTestHelpers.makeWorkout(exercises: [AnalyticsTestHelpers.makeWorkoutExercise(exercise: exercise,
                sets: [AnalyticsTestHelpers.makeCompletedSet(weight: 20 + Double(index) * 0.2, reps: 8)])], startedAt: date, completedAt: date.addingTimeInterval(3600))
        }
        for (name, width, typeSize) in [("compact", 375.0, DynamicTypeSize.large), ("accessibility", 430.0, DynamicTypeSize.accessibility2)] {
            let content = NavigationStack {
                ExerciseHistoryDetailView(exercise: exercise, workouts: workouts, bodyWeightKg: 70, weightUnit: .kg)
            }.environment(\.dynamicTypeSize, typeSize)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 950))
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            await Task.yield()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "complement-exercise-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(image.size.width, width)
            XCTAssertNotNil(image.pngData())
            window.isHidden = true
        }
    }

}

/// Native input behavior is exercised in a real hosting window, including first-responder changes.
@MainActor
final class WorkoutNumberInputTests: XCTestCase {
    func testNumericPolicyAndLocale() {
        XCTAssertEqual(STNumericKind.weight.parsed("102,5"), .value(102.5))
        XCTAssertEqual(STNumericKind.weight.parsed("102.5"), .value(102.5))
        XCTAssertEqual(STNumericKind.weight.acceptedDraft("100,2500"), "100,25")
        XCTAssertNil(STNumericKind.weight.acceptedDraft("100,251"))
        XCTAssertNil(STNumericKind.weight.acceptedDraft("1,2.3"))
        XCTAssertNil(STNumericKind.weight.acceptedDraft("NaN"))
        XCTAssertNil(STNumericKind.weight.acceptedDraft("1e3"))
        XCTAssertEqual(STNumericKind.weight.parsed("-10.5"), .value(-10.5))
        XCTAssertEqual(STNumericKind.weight.parsed(""), .value(nil))
        XCTAssertEqual(STNumericKind.weight.parsed("0"), .value(0))
        XCTAssertEqual(STNumericKind.weight.parsed("."), .invalid)
        XCTAssertEqual(STNumericKind.reps.parsed("8"), .value(8))
        XCTAssertEqual(STNumericKind.reps.parsed("8.5"), .invalid)
        XCTAssertEqual(STNumericKind.reps.parsed("-1"), .invalid)
        XCTAssertEqual(STNumericKind.rpe.parsed("7,5"), .value(7.5))
        XCTAssertEqual(STNumericKind.rpe.parsed("0"), .invalid)
        XCTAssertEqual(STNumericKind.rpe.parsed("11"), .invalid)
        XCTAssertEqual(STNumericKind.rir.parsed("0"), .value(0))
        XCTAssertEqual(STNumericKind.rir.parsed("10"), .invalid)
        XCTAssertEqual(STNumericKind.formatted(100.25, locale: Locale(identifier: "sv_SE")), "100,25")
        XCTAssertEqual(STNumericKind.formatted(100.0, locale: Locale(identifier: "en_US")), "100")
        XCTAssertEqual(STNumericKind.formatted(nil), "")
    }

    private func fields(in view: UIView) -> [STNumericTextField] {
        (view as? STNumericTextField).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
    }
    private func host<V: View>(_ view: V, width: CGFloat = 375, height: CGFloat = 700) -> UIWindow {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        return window
    }
    private func settle() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
    private struct EditorFixture: View {
        var showIntensity = true
        var onWeight: (Double?) -> Void = { _ in }
        var onReps: (Int?) -> Void = { _ in }
        var onIntensity: (Double?) -> Void = { _ in }
        @State private var weight: Double? = 100
        @State private var reps: Int? = 10
        @State private var intensity: Double?
        var body: some View {
            STSetValuesEditor(weight: weight, reps: reps, intensity: intensity, showIntensity: showIntensity,
                intensityMetric: .rpe, weightUnit: .kg, context: "Set 1",
                onWeightChange: { weight = $0; onWeight($0) }, onRepsChange: { reps = $0; onReps($0) },
                onIntensityChange: { intensity = $0; onIntensity($0) }).padding(16).background(STColors.surface)
        }
    }
    private func editor(showIntensity: Bool = true, onWeight: @escaping (Double?) -> Void = { _ in }, onReps: @escaping (Int?) -> Void = { _ in }, onIntensity: @escaping (Double?) -> Void = { _ in }) -> some View {
        EditorFixture(showIntensity: showIntensity, onWeight: onWeight, onReps: onReps, onIntensity: onIntensity)
    }

    func testTapReplaceNextAndDoneCommitExactlyOnce() async throws {
        var weights: [Double?] = [], reps: [Int?] = [], intensity: [Double?] = []
        let window = host(editor(onWeight: { weights.append($0) }, onReps: { reps.append($0) }, onIntensity: { intensity.append($0) }))
        defer { window.isHidden = true }
        await settle()
        let fields = fields(in: window.rootViewController!.view)
        XCTAssertEqual(fields.count, 3)
        let weight = try XCTUnwrap(fields.first)
        XCTAssertTrue(weight.becomeFirstResponder())
        await settle()
        XCTAssertEqual(weight.text(in: try XCTUnwrap(weight.selectedTextRange)), "100")
        weight.insertText("102,5")
        XCTAssertTrue(weights.isEmpty) // draft, not a partially typed persisted value
        let delegate = try XCTUnwrap(weight.delegate as? STNumberField.Coordinator)
        delegate.goNext()
        await settle()
        XCTAssertEqual(weights, [102.5])
        XCTAssertTrue(fields[1].isFirstResponder)
        XCTAssertEqual(fields[1].text(in: try XCTUnwrap(fields[1].selectedTextRange)), "10")
        fields[1].insertText("8")
        (fields[1].delegate as? STNumberField.Coordinator)?.goNext()
        await settle()
        fields[2].insertText("7,5")
        XCTAssertTrue(STNumericTextField.commitActiveInput())
        XCTAssertEqual(reps, [8])
        XCTAssertEqual(intensity, [7.5])
        XCTAssertNil(STNumericTextField.active)
        XCTAssertEqual(weights.count, 1)
        XCTAssertTrue(weight.becomeFirstResponder())
        await settle()
        XCTAssertEqual(weight.text(in: try XCTUnwrap(weight.selectedTextRange)), STNumericKind.formatted(102.5))
        XCTAssertTrue(weight.resignFirstResponder())
        XCTAssertEqual(weights.count, 1)
    }

    func testAccessoryPresentOnEveryReopenAndHiddenIntensitySkipped() async throws {
        let window = host(editor(showIntensity: false))
        defer { window.isHidden = true }
        await settle()
        let fields = fields(in: window.rootViewController!.view)
        XCTAssertEqual(fields.count, 2)
        for _ in 0..<3 {
            XCTAssertTrue(fields[0].becomeFirstResponder())
            await settle()
            let toolbar = try XCTUnwrap(fields[0].inputAccessoryView as? UIToolbar)
            XCTAssertEqual(toolbar.items?.compactMap(\.title), ["Previous", "Next", "Done"])
            XCTAssertEqual(fields[0].keyboardAppearance, .dark)
            XCTAssertFalse(try XCTUnwrap(toolbar.items?.first).isEnabled)
            (fields[0].delegate as? STNumberField.Coordinator)?.goNext()
            await settle()
            XCTAssertTrue(fields[1].isFirstResponder)
            let lastToolbar = try XCTUnwrap(fields[1].inputAccessoryView as? UIToolbar)
            XCTAssertFalse(try XCTUnwrap(lastToolbar.items?.first(where: { $0.title == "Next" })).isEnabled)
            (fields[1].delegate as? STNumberField.Coordinator)?.goPrevious()
            XCTAssertTrue(fields[0].isFirstResponder)
            (fields[0].delegate as? STNumberField.Coordinator)?.done()
            XCTAssertNil(STNumericTextField.active)
        }
    }

    func testInvalidIntensityStaysEditableAndNeverClamps() async throws {
        var values: [Double?] = []
        let window = host(editor(onIntensity: { values.append($0) }))
        defer { window.isHidden = true }
        await settle()
        let field = try XCTUnwrap(fields(in: window.rootViewController!.view).last)
        XCTAssertTrue(field.becomeFirstResponder())
        await settle()
        field.insertText("11")
        XCTAssertFalse(STNumericTextField.commitActiveInput())
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertTrue(values.isEmpty)
        field.selectAll(nil); field.insertText("7.5")
        XCTAssertTrue(STNumericTextField.commitActiveInput())
        XCTAssertEqual(values, [7.5])
    }

    func testUntouchedLbsVisitAndExternalUpdatePreserveModel() async throws {
        var values: [Double?] = []
        let navigation = STFieldNavigation()
        let originalKg = 45.35929094356398
        let component = STNumberField(value: WeightUnit.lbs.fromKg(originalKg), kind: .weight, label: "Weight lbs",
            navigation: navigation, position: 0, onCommit: { values.append($0) }, onError: { _ in })
        let window = host(component.frame(height: 52).padding())
        defer { window.isHidden = true }
        await settle()
        let field = try XCTUnwrap(fields(in: window.rootViewController!.view).first)
        XCTAssertTrue(field.becomeFirstResponder()); await settle()
        XCTAssertTrue(field.resignFirstResponder())
        XCTAssertTrue(values.isEmpty)
        XCTAssertTrue(field.becomeFirstResponder()); await settle()
        let delegate = try XCTUnwrap(field.delegate as? STNumberField.Coordinator)
        delegate.parent = STNumberField(value: 110, kind: .weight, label: "Weight lbs", navigation: navigation, position: 0,
            onCommit: { values.append($0) }, onError: { _ in })
        XCTAssertTrue(field.resignFirstResponder())
        XCTAssertEqual(field.text, "110")
        XCTAssertTrue(values.isEmpty)
    }

    func testActiveTypingSurvivesExternalModelUpdate() async throws {
        var values: [Double?] = []
        let window = host(editor(onWeight: { values.append($0) }))
        defer { window.isHidden = true }
        await settle()
        let field = try XCTUnwrap(fields(in: window.rootViewController!.view).first)
        field.becomeFirstResponder(); await settle(); field.insertText("102.5")
        let delegate = try XCTUnwrap(field.delegate as? STNumberField.Coordinator)
        delegate.parent = STNumberField(value: 110, kind: .weight, label: "Weight kg", navigation: delegate.parent.navigation,
            position: 0, onCommit: { values.append($0) }, onError: { _ in })
        XCTAssertEqual(field.text, "102.5")
        XCTAssertTrue(field.resignFirstResponder())
        XCTAssertEqual(values, [102.5])
    }

    func testExerciseNoteFlushesBeforeDebounceOnFinish() async throws {
        var exercise = AnalyticsTestHelpers.makeWorkoutExercise()
        exercise.notes = "Original note"
        var savedNotes: [String] = []
        let card = ExerciseCardView(workoutExercise: exercise, onWeightChange: { _, _ in },
            onRepsChange: { _, _ in }, onToggleComplete: { _ in }, onAddSet: {},
            onNoteChange: { savedNotes.append($0) })
        let window = host(card)
        defer { window.isHidden = true }
        await settle()
        func noteInputs(in view: UIView) -> [UIView] {
            if !(view is STNumericTextField), view is UITextView || view is UITextField { return [view] }
            return view.subviews.flatMap { noteInputs(in: $0) }
        }
        let note = try XCTUnwrap(noteInputs(in: window.rootViewController!.view).first)
        XCTAssertTrue(note.becomeFirstResponder())
        if let field = note as? UITextField {
            field.selectAll(nil); field.insertText("Updated note")
        } else if let field = note as? UITextView {
            field.selectAll(nil); field.insertText("Updated note")
        }
        await settle()
        XCTAssertTrue(savedNotes.isEmpty)
        XCTAssertTrue(STNumericTextField.commitActiveInput())
        XCTAssertEqual(savedNotes, ["Updated note"])
        // The canceled debounce must not enqueue a second save after Finish has started.
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertEqual(savedNotes, ["Updated note"])
    }

    func testDropSegmentAndOrdinaryRowsRenderAtPhoneAndAccessibilitySizes() async throws {
        let set = AnalyticsTestHelpers.makeCompletedSet(weight: 999.99, reps: 12, rpe: 7.5)
        let entry = DropSetEntry(weight: 50.25, reps: 8, rpe: 8.5)
        for (name, typeSize) in [("compact", DynamicTypeSize.large), ("accessibility", .accessibility2)] {
            let content = ScrollView {
                VStack(spacing: 16) {
                    SetRowGridView(setNumber: 1, exerciseSet: set, previousText: "100 kg × 10 reps", showRPE: true,
                        onWeightChange: { _ in }, onRepsChange: { _ in }, onToggleComplete: {})
                    DropSetRowView(label: "2a", entry: entry, showIntensity: true, onWeightChange: { _ in },
                        onRepsChange: { _ in }, onIntensityChange: { _ in }, onToggleFailure: {}, onRemove: {})
                }.background(STColors.surface).padding(16)
            }.background(STColors.background).environment(\.dynamicTypeSize, typeSize).preferredColorScheme(.dark)
            let window = host(content, height: 950)
            await settle()
            let renderedView = window.rootViewController!.view!
            let renderedFields = fields(in: renderedView)
            XCTAssertEqual(renderedFields.count, 6)
            for field in renderedFields {
                let rect = field.convert(field.bounds, to: window)
                XCTAssertGreaterThanOrEqual(rect.width, 44)
                XCTAssertGreaterThanOrEqual(rect.height, 44)
                XCTAssertGreaterThanOrEqual(rect.minX, 0)
                XCTAssertLessThanOrEqual(rect.maxX, window.bounds.maxX + 1)
            }
            try await Task.sleep(for: .milliseconds(100)) // allow SwiftUI's display transaction to finish
            let image = UIGraphicsImageRenderer(bounds: renderedView.bounds).image { context in
                renderedView.layer.render(in: context.cgContext)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "workout-input-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true
        }
    }
}
