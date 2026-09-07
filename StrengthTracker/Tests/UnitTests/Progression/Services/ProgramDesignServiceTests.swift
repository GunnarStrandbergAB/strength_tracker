import Foundation
import Testing
@testable import StrengthTrackerShared

@Suite("ProgramDesignService")
struct ProgramDesignServiceTests {

    let service = ProgramDesignService()

    // MARK: - Linear Periodization

    @Test("Linear program generates correct block count (beginner 12wk -> 3 blocks)")
    func testLinearProgram_generatesCorrectBlockCount() {
        let plan = ProgressionTestHelpers.beginnerLinearPlan()
        let blocks = service.generateProgram(for: plan)

        // 12 weeks / 4 weeks per block = 3 blocks
        #expect(blocks.count == 3)

        let totalWeeks = blocks.reduce(0) { $0 + $1.weeks.count }
        #expect(totalWeeks == 12)

        // Blocks should be ordered sequentially
        for (index, block) in blocks.enumerated() {
            #expect(block.order == index)
        }
    }

    @Test("Linear program intensity increases week over week")
    func testLinearProgram_intensityIncreasesWeekOverWeek() {
        let plan = ProgressionTestHelpers.beginnerLinearPlan()
        let blocks = service.generateProgram(for: plan)

        // Collect non-deload weeks and their average intensity
        var previousIntensity: Double = 0
        for block in blocks {
            for week in block.weeks where !week.isDeload {
                let avgIntensity = averageIntensity(of: week)
                #expect(avgIntensity >= previousIntensity,
                    "Intensity should not decrease: week \(week.absoluteWeekNumber) had \(avgIntensity) vs previous \(previousIntensity)")
                previousIntensity = avgIntensity
            }
        }
        // Verify we actually saw progression (final > initial)
        let firstNonDeload = blocks.flatMap(\.weeks).first { !$0.isDeload }!
        let lastNonDeload = blocks.flatMap(\.weeks).last { !$0.isDeload }!
        #expect(averageIntensity(of: lastNonDeload) > averageIntensity(of: firstNonDeload))
    }

    @Test("Linear program intensity is clamped to goal ceiling")
    func testLinearProgram_intensityClampedToCeiling() {
        // Use a plan where intensity step would overshoot the goal ceiling
        let plan = ProgressionTestHelpers.makeTestPlan(
            name: "Clamp Test",
            exercises: ProgressionTestHelpers.standardExercises(),
            trainingStatus: .beginner, // 2.5% step = would reach ceiling before 12wk
            programType: .linear,
            primaryGoal: .hypertrophy, // intensityRange = 0.65...0.85
            weeklyFrequency: 3
        )
        let blocks = service.generateProgram(for: plan)

        let ceiling = plan.primaryGoal.intensityRange.upperBound

        for block in blocks {
            for week in block.weeks where !week.isDeload {
                for session in week.sessions {
                    for exerciseSet in session.plannedExercises {
                        #expect(exerciseSet.percentageOf1RM <= ceiling + 0.001,
                            "Intensity \(exerciseSet.percentageOf1RM) exceeds ceiling \(ceiling) at week \(week.absoluteWeekNumber)")
                    }
                }
            }
        }
    }

    @Test("Linear program has deload week every 4th (for beginner)")
    func testLinearProgram_deloadWeekEvery4th() {
        let plan = ProgressionTestHelpers.beginnerLinearPlan()
        let blocks = service.generateProgram(for: plan)
        let allWeeks = blocks.flatMap(\.weeks)

        // Every 4th week (absoluteWeekNumber 4, 8, 12) should be deload
        for week in allWeeks {
            if week.absoluteWeekNumber % 4 == 0 {
                #expect(week.isDeload,
                    "Week \(week.absoluteWeekNumber) should be deload")
            } else {
                #expect(!week.isDeload,
                    "Week \(week.absoluteWeekNumber) should NOT be deload")
            }
        }
    }

    @Test("Linear program sets decrease as intensity rises")
    func testLinearProgram_setsDecreaseAsIntensityRises() {
        let plan = ProgressionTestHelpers.beginnerLinearPlan()
        let blocks = service.generateProgram(for: plan)

        let nonDeloadWeeks = blocks.flatMap(\.weeks).filter { !$0.isDeload }
        guard let firstWeek = nonDeloadWeeks.first,
              let lastWeek = nonDeloadWeeks.last else {
            Issue.record("No non-deload weeks found")
            return
        }

        let firstSets = firstWeek.sessions.first?.plannedExercises.first?.sets ?? 0
        let lastSets = lastWeek.sessions.first?.plannedExercises.first?.sets ?? 0

        #expect(firstSets >= lastSets,
            "Sets should decrease or stay same: first=\(firstSets), last=\(lastSets)")
    }

    // MARK: - DUP (Daily Undulating Periodization)

    @Test("DUP program rotates session types (hypertrophy, strength, power within week)")
    func testDUPProgram_rotatesSessionTypes() {
        let plan = ProgressionTestHelpers.intermediateDUPPlan()
        let blocks = service.generateProgram(for: plan)

        // With 3 days/week, each week should have all three DUP types
        let firstNonDeload = blocks.flatMap(\.weeks).first { !$0.isDeload }!
        let sessionTypes = firstNonDeload.sessions.compactMap(\.dupSessionType)

        #expect(sessionTypes.contains(.hypertrophy), "Should include hypertrophy session")
        #expect(sessionTypes.contains(.strength), "Should include strength session")
        #expect(sessionTypes.contains(.power), "Should include power session")
    }

    @Test("DUP rotation carries across weeks (2 days/week sees all 3 types over 2 weeks)")
    func testDUPProgram_rotationCarriesAcrossWeeks() {
        let plan = ProgressionTestHelpers.intermediateDUPPlan2Days()
        let blocks = service.generateProgram(for: plan)

        // With 2 days/week, all 3 DUP types must appear across the first 2 non-deload weeks
        let nonDeloadWeeks = blocks.flatMap(\.weeks).filter { !$0.isDeload }
        guard nonDeloadWeeks.count >= 2 else {
            Issue.record("Need at least 2 non-deload weeks")
            return
        }

        let first2Weeks = nonDeloadWeeks.prefix(2)
        let allTypes = first2Weeks.flatMap { $0.sessions.compactMap(\.dupSessionType) }
        let uniqueTypes = Set(allTypes)

        #expect(uniqueTypes.contains(.hypertrophy), "Should include hypertrophy across first 2 weeks")
        #expect(uniqueTypes.contains(.strength), "Should include strength across first 2 weeks")
        #expect(uniqueTypes.contains(.power), "Should include power across first 2 weeks")
        #expect(allTypes.count == 4, "2 days/week × 2 weeks = 4 sessions, got \(allTypes.count)")
    }

    @Test("DUP program has percentage-based overload (weights increase week over week)")
    func testDUPProgram_percentageBasedOverload() {
        let plan = ProgressionTestHelpers.intermediateDUPPlan()
        let blocks = service.generateProgram(for: plan)

        // Compare same session type across non-deload weeks to verify overload
        let nonDeloadWeeks = blocks.flatMap(\.weeks).filter { !$0.isDeload }
        guard nonDeloadWeeks.count >= 2 else {
            Issue.record("Need at least 2 non-deload weeks")
            return
        }

        // Get the first session's first exercise weight for week 1 and a later week
        let week1 = nonDeloadWeeks[0]
        let week2 = nonDeloadWeeks[1]

        let weight1 = week1.sessions.first?.plannedExercises.first?.targetWeight ?? 0
        let weight2 = week2.sessions.first?.plannedExercises.first?.targetWeight ?? 0

        #expect(weight2 >= weight1,
            "Weight should increase from week 1 (\(weight1)) to week 2 (\(weight2))")
    }

    @Test("DUP program deload uses flat recovery prescription (50% 1RM, 8 reps, intensity-only — sets preserved)")
    func testDUPProgram_deloadFlatRecovery() {
        let plan = ProgressionTestHelpers.intermediateDUPPlan()
        let blocks = service.generateProgram(for: plan)

        let allWeeks = blocks.flatMap(\.weeks)
        guard let deloadWeek = allWeeks.first(where: { $0.isDeload }) else {
            Issue.record("Need a deload week")
            return
        }

        let validDUPSets = Set(DUPSessionType.allCases.map(\.sets))

        let exerciseSessions = deloadWeek.sessions.filter { !$0.plannedExercises.isEmpty }
        for session in exerciseSessions {
            // No session-type badge during deload
            #expect(session.dupSessionType == nil,
                "Deload session should have nil dupSessionType, got \(String(describing: session.dupSessionType))")

            // Label should not contain Power/Strength/Hypertrophy
            let label = session.sessionLabel.lowercased()
            #expect(!label.contains("power") && !label.contains("strength") && !label.contains("hypertrophy"),
                "Deload label should not contain session-type name, got '\(session.sessionLabel)'")

            for exerciseSet in session.plannedExercises {
                #expect(exerciseSet.percentageOf1RM == 0.50,
                    "Deload intensity should be 50% (default), got \(exerciseSet.percentageOf1RM)")
                #expect(validDUPSets.contains(exerciseSet.sets),
                    "Deload sets should match the underlying DUPSessionType.sets (3/4/5), got \(exerciseSet.sets)")
                #expect(exerciseSet.targetReps == 8,
                    "Deload reps should be 8, got \(exerciseSet.targetReps)")
            }
        }
    }

    @Test("deloadIntensity parameter overrides default deload weight % across program types")
    func testDeloadIntensity_parameterOverride() {
        let plans: [ProgressionPlan] = [
            ProgressionTestHelpers.beginnerLinearPlan(),
            ProgressionTestHelpers.intermediateDUPPlan(),
            ProgressionTestHelpers.intermediateWUPPlan(),
            ProgressionTestHelpers.intermediateBlockPlan(),
        ]

        for plan in plans {
            let blocks = service.generateProgram(for: plan, deloadIntensity: 0.40)
            let deloadSessions = blocks.flatMap(\.weeks).filter(\.isDeload).flatMap(\.sessions)
            let deloadExercises = deloadSessions.flatMap(\.plannedExercises)
            guard !deloadExercises.isEmpty else { continue }
            for exerciseSet in deloadExercises {
                #expect(exerciseSet.percentageOf1RM == 0.40,
                    "\(plan.programType): deload intensity should follow parameter (0.40), got \(exerciseSet.percentageOf1RM)")
            }
        }
    }

    @Test("DUP deload sessions have isDeload = true, non-deload sessions have isDeload = false")
    func testDUPProgram_isDeloadFlagCorrect() {
        let plan = ProgressionTestHelpers.intermediateDUPPlan()
        let blocks = service.generateProgram(for: plan)

        for block in blocks {
            for week in block.weeks {
                for session in week.sessions {
                    if week.isDeload {
                        #expect(session.isDeload,
                            "Session in deload week \(week.absoluteWeekNumber) should have isDeload = true")
                    } else {
                        #expect(!session.isDeload,
                            "Session in non-deload week \(week.absoluteWeekNumber) should have isDeload = false")
                    }
                }
            }
        }
    }

    // MARK: - WUP (Weekly Undulating Periodization)

    @Test("WUP program alternates rep schemes week-to-week")
    func testWUPProgram_alternatesRepSchemes() {
        let plan = ProgressionTestHelpers.intermediateWUPPlan()
        let blocks = service.generateProgram(for: plan)

        let nonDeloadWeeks = blocks.flatMap(\.weeks).filter { !$0.isDeload }
        guard nonDeloadWeeks.count >= 3 else {
            Issue.record("Need at least 3 non-deload weeks")
            return
        }

        // Get target reps from first exercise of first session of each week
        let repsPerWeek = nonDeloadWeeks.prefix(3).map { week -> Int in
            week.sessions.first?.plannedExercises.first?.targetReps ?? 0
        }

        // All 3 weeks should have different rep counts (hypertrophy vs strength vs power)
        let uniqueReps = Set(repsPerWeek)
        #expect(uniqueReps.count >= 2,
            "WUP should alternate rep schemes, got: \(repsPerWeek)")
    }

    // MARK: - Block Periodization

    @Test("Block program phases in correct order (accumulation -> transmutation -> realization -> deload)")
    func testBlockProgram_phasesInCorrectOrder() {
        // Advanced plans skip the scheduled deload phase (M1) — use intermediate here.
        let plan = ProgressionTestHelpers.intermediateBlockPlan()
        let blocks = service.generateProgram(for: plan)

        #expect(blocks.count == 4, "Block program should have 4 phases")

        let expectedPhases: [BlockPhase] = [.accumulation, .transmutation, .realization, .deload]
        for (index, expectedPhase) in expectedPhases.enumerated() {
            #expect(blocks[index].blockPhase == expectedPhase,
                "Block \(index) should be \(expectedPhase), got \(String(describing: blocks[index].blockPhase))")
        }

        // Verify week durations match phase.weekDuration
        #expect(blocks[0].durationWeeks == BlockPhase.accumulation.weekDuration)
        #expect(blocks[1].durationWeeks == BlockPhase.transmutation.weekDuration)
        #expect(blocks[2].durationWeeks == BlockPhase.realization.weekDuration)
        #expect(blocks[3].durationWeeks == BlockPhase.deload.weekDuration)
    }

    @Test("Advanced block program skips the scheduled deload phase (M1)")
    func testBlockProgram_advancedSkipsDeloadPhase() {
        let plan = ProgressionTestHelpers.advancedBlockPlan()
        let blocks = service.generateProgram(for: plan)

        #expect(blocks.count == 3, "Advanced macrocycle ends after realization")
        #expect(blocks.allSatisfy { $0.blockPhase != .deload })
        let allSessions = blocks.flatMap(\.weeks).flatMap(\.sessions)
        #expect(allSessions.allSatisfy { !$0.isDeload },
            "Advanced plans must contain no scheduled deload sessions")
    }

    @Test("Block program intensity matches phase ranges")
    func testBlockProgram_intensityMatchesPhase() {
        // Intermediate: includes the deload phase asserted at blocks[3]
        let plan = ProgressionTestHelpers.intermediateBlockPlan()
        let blocks = service.generateProgram(for: plan)

        // Accumulation: 65-75%
        let accumIntensities = blocks[0].weeks.flatMap(\.sessions).flatMap(\.plannedExercises).map(\.percentageOf1RM)
        for intensity in accumIntensities {
            #expect(intensity >= 0.64 && intensity <= 0.76,
                "Accumulation intensity \(intensity) outside 65-75% range")
        }

        // Transmutation: 78-88%
        let transIntensities = blocks[1].weeks.flatMap(\.sessions).flatMap(\.plannedExercises).map(\.percentageOf1RM)
        for intensity in transIntensities {
            #expect(intensity >= 0.77 && intensity <= 0.89,
                "Transmutation intensity \(intensity) outside 78-88% range")
        }

        // Realization: 88-100%
        let realIntensities = blocks[2].weeks.flatMap(\.sessions).flatMap(\.plannedExercises).map(\.percentageOf1RM)
        for intensity in realIntensities {
            #expect(intensity >= 0.87 && intensity <= 1.01,
                "Realization intensity \(intensity) outside 88-100% range")
        }

        // Deload: lower intensity
        let deloadIntensities = blocks[3].weeks.flatMap(\.sessions).flatMap(\.plannedExercises).map(\.percentageOf1RM)
        for intensity in deloadIntensities {
            #expect(intensity <= 0.65,
                "Deload intensity \(intensity) should be well below working intensities")
        }
    }

    // MARK: - Day Spread

    @Test("Day spread for 3 days is Mon/Wed/Fri")
    func testDaySpread_3days_MWF() {
        let plan = ProgressionTestHelpers.makeTestPlan(
            exercises: ProgressionTestHelpers.standardExercises(),
            programType: .linear,
            primaryGoal: .hypertrophy,
            weeklyFrequency: 3
        )
        let blocks = service.generateProgram(for: plan)

        let firstWeek = blocks.first!.weeks.first!
        let days = firstWeek.sessions.compactMap(\.dayOfWeek)

        #expect(days == [2, 4, 6], "3 days/week should be Mon(2)/Wed(4)/Fri(6), got \(days)")
    }

    @Test("Day spread for 4 days is Mon/Tue/Thu/Fri")
    func testDaySpread_4days_MTThF() {
        let plan = ProgressionTestHelpers.makeTestPlan(
            exercises: ProgressionTestHelpers.standardExercises(),
            programType: .linear,
            primaryGoal: .hypertrophy,
            weeklyFrequency: 4
        )
        let blocks = service.generateProgram(for: plan)

        let firstWeek = blocks.first!.weeks.first!
        let days = firstWeek.sessions.compactMap(\.dayOfWeek)

        #expect(days == [2, 3, 5, 6], "4 days/week should be Mon(2)/Tue(3)/Thu(5)/Fri(6), got \(days)")
    }

    // MARK: - Cross-Program Validation

    @Test("All programs produce exercise sets with valid weights (> 0, rounded to 2.5)")
    func testAllPrograms_exerciseSetsHaveValidWeights() {
        let plans: [ProgressionPlan] = [
            ProgressionTestHelpers.beginnerLinearPlan(),
            ProgressionTestHelpers.intermediateDUPPlan(),
            ProgressionTestHelpers.intermediateWUPPlan(),
            ProgressionTestHelpers.advancedBlockPlan(),
        ]

        for plan in plans {
            let blocks = service.generateProgram(for: plan)
            for block in blocks {
                for week in block.weeks {
                    for session in week.sessions {
                        for exerciseSet in session.plannedExercises {
                            #expect(exerciseSet.targetWeight > 0,
                                "\(plan.programType): Weight must be > 0, got \(exerciseSet.targetWeight) for \(exerciseSet.exerciseName) in week \(week.absoluteWeekNumber)")

                            let remainder = exerciseSet.targetWeight.truncatingRemainder(dividingBy: 2.5)
                            #expect(remainder < 0.001 || abs(remainder - 2.5) < 0.001,
                                "\(plan.programType): Weight \(exerciseSet.targetWeight) not rounded to 2.5 for \(exerciseSet.exerciseName)")
                        }
                    }
                }
            }
        }
    }

    @Test("All programs produce sessions with non-empty labels")
    func testAllPrograms_sessionLabelsNotEmpty() {
        let plans: [ProgressionPlan] = [
            ProgressionTestHelpers.beginnerLinearPlan(),
            ProgressionTestHelpers.intermediateDUPPlan(),
            ProgressionTestHelpers.intermediateWUPPlan(),
            ProgressionTestHelpers.advancedBlockPlan(),
        ]

        for plan in plans {
            let blocks = service.generateProgram(for: plan)
            for block in blocks {
                for week in block.weeks {
                    for session in week.sessions {
                        #expect(!session.sessionLabel.isEmpty,
                            "\(plan.programType): Session label should not be empty in week \(week.absoluteWeekNumber)")
                    }
                }
            }
        }
    }

    @Test("week.isDeload is true exactly when all of its sessions are deload")
    func testAllPrograms_isDeloadMatchesWeek() {
        // Model A: deload is per-session truth; a calendar week's isDeload is the
        // all-sessions cache (a deload microcycle may straddle two calendar weeks
        // for non-Monday start dates).
        let plans: [ProgressionPlan] = [
            ProgressionTestHelpers.beginnerLinearPlan(),
            ProgressionTestHelpers.intermediateDUPPlan(),
            ProgressionTestHelpers.intermediateWUPPlan(),
            ProgressionTestHelpers.intermediateBlockPlan(),
        ]

        for plan in plans {
            let blocks = service.generateProgram(for: plan)
            var sawDeloadWeek = false
            for block in blocks {
                for week in block.weeks {
                    let allDeload = !week.sessions.isEmpty && week.sessions.allSatisfy(\.isDeload)
                    #expect(week.isDeload == allDeload,
                        "\(plan.programType): week.isDeload (\(week.isDeload)) must equal all-sessions-deload (\(allDeload)) in week \(week.absoluteWeekNumber)")
                    if week.isDeload { sawDeloadWeek = true }
                }
            }
            #expect(sawDeloadWeek, "\(plan.programType): non-advanced plans should contain at least one deload week")
        }
    }

    // MARK: - Helpers

    private func averageIntensity(of week: TrainingWeek) -> Double {
        let intensities = week.sessions.flatMap(\.plannedExercises).map(\.percentageOf1RM)
        guard !intensities.isEmpty else { return 0 }
        return intensities.reduce(0, +) / Double(intensities.count)
    }

    private func totalSets(of week: TrainingWeek) -> Int {
        week.sessions.flatMap(\.plannedExercises).reduce(0) { $0 + $1.sets }
    }
}

@Suite("Enhanced plan editing")
struct EnhancedPlanEditingTests {
    let now = CalendarWeekBucketer.weekStart(of: ProgressionTestHelpers.fixedMondayStart)
    let settings = PlanConfiguration(durationWeeks: 12, deloadWeightPercentage: 60, deloadRestPercentage: 75)
    func makePlan() -> ProgressionPlan {
        var p = ProgressionTestHelpers.makeTestPlan(exercises: ProgressionTestHelpers.standardExercises(), trainingStatus: .advanced)
        p.startDate = now; p.trainingDays = [2, 4, 6]; p.weeklyFrequency = 3
        p.configuration = settings
        p.blocks = ProgramDesignService().generateProgram(for: p)
        p.targetEndDate = p.blocks.flatMap(\.weeks).flatMap(\.sessions).compactMap(\.scheduledDate).max()
        return p
    }
    func sessions(_ p: ProgressionPlan) -> [PlannedSession] { p.blocks.flatMap(\.weeks).flatMap(\.sessions) }

    @Test("All generators honor duration and retain programming identities", arguments: ProgramType.allCases, [4, 8, 12, 16, 52])
    func durations(type: ProgramType, duration: Int) {
        var p = makePlan(); p.programType = type; p.trainingStatus = .intermediate; p.configuration?.durationWeeks = duration
        let generated = ProgramDesignService().generateProgram(for: p).flatMap(\.weeks).flatMap(\.sessions)
        #expect(Set(generated.compactMap(\.programmingWeekNumber)).count == duration)
        #expect(generated.allSatisfy { $0.programmingWeekID != nil })
        for s in generated where s.isDeload {
            #expect(s.deloadPrescription != nil)
            #expect(s.plannedExercises.first?.targetWeight == s.deloadPrescription?.normalExercises.first.map { ($0.targetWeight * 60).rounded() / 100 })
        }
    }

    @Test("Three inserted deload weeks extend 12 to 15 without losing prescriptions")
    func multipleInsertions() throws {
        let original = makePlan()
        let changed = try PlanEditingService.applying(.init(operation: .insertDeload, week: 5, weeks: 3), to: original, settings: settings, now: now)
        #expect(changed.totalWeeks == 15)
        #expect(sessions(changed).count == sessions(original).count + 9)
        for s in sessions(original) {
            let updated = try #require(sessions(changed).first { $0.id == s.id })
            #expect(updated.plannedExercises == s.plannedExercises)
            #expect(updated.programmingWeekID == s.programmingWeekID)
            let delta = (s.programmingWeekNumber ?? 0) >= 5 ? 21 : 0
            #expect(updated.scheduledDate == Calendar.current.date(byAdding: .day, value: delta, to: s.scheduledDate!))
        }
    }

    @Test("Conversion is reversible and does not change the finish date")
    func conversion() throws {
        let original = makePlan()
        let changed = try PlanEditingService.applying(.init(operation: .convertDeload, week: 5), to: original, settings: settings, now: now)
        #expect(changed.targetEndDate == original.targetEndDate)
        let restored = try PlanEditingService.applying(.init(operation: .removeDeload, week: 5), to: changed, settings: settings, now: now)
        #expect(sessions(restored) == sessions(original))
    }

    @Test("Deload overlay is idempotent, preserves sets/reps, snapshots rest and survives coding")
    func overlay() throws {
        var s = sessions(makePlan())[0]; let normal = s.plannedExercises
        PlanDeloadPolicy.apply(to: &s, weightPercentage: 60, restPercentage: 50)
        let once = s.plannedExercises
        PlanDeloadPolicy.apply(to: &s, weightPercentage: 60, restPercentage: 50)
        #expect(s.plannedExercises == once)
        #expect(s.plannedExercises.map(\.sets) == normal.map(\.sets))
        #expect(s.plannedExercises.map(\.targetReps) == normal.map(\.targetReps))
        let copy = try JSONDecoder().decode(PlannedSession.self, from: JSONEncoder().encode(s))
        #expect(copy == s)
        #expect(copy.toWorkoutTemplate().deloadRestPercentage == 50)
        s.deloadPrescription?.normalExercises[0].targetWeight = 101.25
        PlanDeloadPolicy.refresh(&s)
        #expect(s.plannedExercises[0].targetWeight == 60.75)
        try PlanDeloadPolicy.remove(from: &s)
        #expect(s.plannedExercises[0].targetWeight == 101.25)
    }

    @Test("Insertion can be moved and removed, preserving original IDs and dates")
    func moveAndRemoveInserted() throws {
        let original = makePlan()
        let inserted = try PlanEditingService.applying(.init(operation: .insertDeload, week: 5), to: original, settings: settings, now: now)
        let moved = try PlanEditingService.applying(.init(operation: .moveDeload, week: 5, destinationWeek: 8), to: inserted, settings: settings, now: now)
        #expect(Set(sessions(moved).map(\.id)) == Set(sessions(inserted).map(\.id)))
        let removed = try PlanEditingService.applying(.init(operation: .removeDeload, week: 8), to: moved, settings: settings, now: now)
        #expect(sessions(removed).sorted { $0.id.uuidString < $1.id.uuidString } == sessions(original).sorted { $0.id.uuidString < $1.id.uuidString })
    }

    @Test("Completed and active sessions block broad edits")
    func protectedWorkouts() throws {
        var p = makePlan(); let first = sessions(p)[0]
        #expect(throws: PlanEditError.self) {
            try PlanEditingService.applying(.init(operation: .convertDeload, week: 1), to: p, settings: settings, protectedSessionIDs: [first.id], now: now)
        }
        p.blocks[0].weeks[0].sessions[0].completedWorkoutId = UUID()
        #expect(throws: PlanEditError.self) {
            try PlanEditingService.applying(.init(operation: .insertDeload, week: 1), to: p, settings: settings, now: now)
        }
        let edited = try PlanEditingService.applying(.init(operation: .convertDeload, week: 5), to: p, settings: settings, now: now)
        #expect(edited.blocks[0].weeks[0].sessions[0] == p.blocks[0].weeks[0].sessions[0])
        #expect(edited.blocks[0].weeks[0].id == p.blocks[0].weeks[0].id)
    }

    @Test("Fewer deload days are omitted instead of counted as missed workouts")
    func omissions() throws {
        var p = makePlan(); p.deloadDays = [2]
        let edited = try PlanEditingService.applying(.init(operation: .convertDeload, week: 5), to: p, settings: settings, now: now)
        let week = try #require(edited.blocks.flatMap(\.weeks).first { $0.absoluteWeekNumber == 5 })
        #expect(week.sessions.filter(\.isOmitted).count == 2)
        #expect(week.sessions.filter(\.isSkipped).isEmpty)
        #expect(week.sessions.filter(\.isClosed).count == 2)
    }

    @Test("Explicit target edits are scoped and preserve precision through a deload")
    func targets() throws {
        let p = makePlan(); let source = sessions(p)[0]
        let request = PlanEditRequest(operation: .changeTargets, sessionID: source.id, scope: .session, exerciseID: source.plannedExercises[0].exerciseId, sets: 4, reps: 8, weightKg: 100.25, restSeconds: 180)
        let changed = try PlanEditingService.applying(request, to: p, settings: settings, now: now)
        let edited = try #require(sessions(changed).first { $0.id == source.id })
        #expect(edited.plannedExercises[0].targetWeight == 100.25)
        #expect(edited.plannedExercises[0].isUserOverride == true)
        #expect(sessions(changed).filter { $0.id != source.id } == sessions(p).filter { $0.id != source.id })
        let deloaded = try PlanEditingService.applying(.init(operation: .convertDeload, week: 1), to: changed, settings: settings, now: now)
        #expect(sessions(deloaded)[0].plannedExercises[0].targetWeight == 60.15)
    }

    @Test("Repeat and extend add complete weeks rather than discard the tail")
    func repeatAndExtend() throws {
        let p = makePlan()
        for op in [PlanEditRequest.Operation.repeatWeek, .extendPlan] {
            let edited = try PlanEditingService.applying(.init(operation: op, week: 5, weeks: 2), to: p, settings: settings, now: now)
            #expect(edited.totalWeeks == 14)
            #expect(Set(sessions(p).map(\.id)).isSubset(of: Set(sessions(edited).map(\.id))))
        }
    }

    @Test("Invalid targets, dates and scopes fail without a candidate")
    func invalidRequests() {
        let p = makePlan()
        for request in [PlanEditRequest(operation: .convertDeload, week: 999), .init(operation: .changeTargets, week: 1, weightKg: -.infinity),
            .init(operation: .changeTargets, week: 1, sets: -1), .init(operation: .insertDeload, week: 2, weeks: 13)] {
            #expect(throws: PlanEditError.self) { try PlanEditingService.applying(request, to: p, settings: settings, now: now) }
        }
    }
}

extension EnhancedPlanEditingTests {
    @Test("Template and exercise edits stay local and preserve reusable templates")
    func templateAndExercise() throws {
        let p = makePlan()
        let original = sessions(p)[0]
        let replacement = ProgressionTestHelpers.makeTestExercise(name: "Replacement")
        let template = WorkoutTemplate(id: UUID(), name: "New day", notes: nil, sortOrder: 0, lastUsedAt: nil, timesUsed: 0,
            exercises: [TemplateExercise(id: UUID(), exercise: replacement, order: 0, supersetGroup: nil, notes: nil, restTimerSeconds: 120,
                targetSets: 3, targetReps: 8, targetWeight: 20.25, targetDurationSeconds: nil, targetDistanceMeters: nil)])
        let changed = try PlanEditingService.applying(.init(operation: .changeTemplate, sessionID: original.id, scope: .session, templateID: template.id),
            to: p, settings: settings, templates: [template], exercises: [replacement], now: now)
        let target = try #require(sessions(changed).first { $0.id == original.id })
        #expect(target.templateId == template.id)
        #expect(target.plannedExercises.first?.targetWeight == 20.25)
        #expect(template.timesUsed == 0)
        let swapped = try PlanEditingService.applying(.init(operation: .changeExercise, sessionID: original.id, scope: .session,
            exerciseID: original.plannedExercises[0].exerciseId, replacementExerciseID: replacement.id, reps: 10, weightKg: 25.25),
            to: p, settings: settings, exercises: [replacement], now: now)
        #expect(sessions(swapped).first?.plannedExercises.first?.exerciseId == replacement.id)
        #expect(sessions(swapped).first?.plannedExercises.first?.targetWeight == 25.25)
    }

    @Test("Rescheduling preserves identity and skip/restore preserves targets")
    func rescheduleSkipRestore() throws {
        let p = makePlan()
        let session = sessions(p)[0]
        let date = Calendar.current.date(byAdding: .day, value: 9, to: session.scheduledDate!)!
        let changed = try PlanEditingService.applying(.init(operation: .rescheduleSession, sessionID: session.id, newDate: date, scope: .session), to: p, settings: settings, now: now)
        #expect(sessions(changed).first { $0.id == session.id }?.scheduledDate == date)
        let skipped = try PlanEditingService.applying(.init(operation: .skipSession, sessionID: session.id, scope: .session), to: changed, settings: settings, now: now)
        #expect(sessions(skipped).first { $0.id == session.id }?.isSkipped == true)
        let restored = try PlanEditingService.applying(.init(operation: .skipSession, sessionID: session.id, scope: .session, skipped: false), to: skipped, settings: settings, now: now)
        #expect(sessions(restored).first { $0.id == session.id }?.plannedExercises == session.plannedExercises)
        #expect(sessions(restored).first { $0.id == session.id }?.isSkipped == false)
    }

    @Test("Editing legacy deload targets preserves deload status and snapshots the normal targets")
    func legacyDeloadTargets() throws {
        var p = makePlan(); p.configuration = nil; p.trainingStatus = .intermediate
        p.blocks = ProgramDesignService().generateProgram(for: p)
        let s = try #require(sessions(p).first { $0.isDeload })
        let changed = try PlanEditingService.applying(.init(operation: .changeTargets, sessionID: s.id, scope: .session, weightKg: 100.25),
            to: p, settings: settings, now: now)
        let result = try #require(sessions(changed).first { $0.id == s.id })
        #expect(result.isDeload)
        #expect(changed.configuration == nil)
        #expect(result.deloadPrescription?.normalExercises.first?.targetWeight == 100.25)
        #expect(result.plannedExercises.first?.targetWeight == 60.15)
    }

    @Test("Midweek starts and calendar shifts retain weekdays and local times")
    func calendarBoundary() throws {
        var p = makePlan()
        p.startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 25, hour: 0))!
        p.blocks = ProgramDesignService().generateProgram(for: p)
        let changed = try PlanEditingService.applying(.init(operation: .insertDeload, week: 2), to: p, settings: settings, now: p.startDate)
        for old in sessions(p) {
            let new = try #require(sessions(changed).first { $0.id == old.id })
            #expect(Calendar.current.component(.weekday, from: old.scheduledDate!) == Calendar.current.component(.weekday, from: new.scheduledDate!))
            #expect(Calendar.current.component(.hour, from: old.scheduledDate!) == Calendar.current.component(.hour, from: new.scheduledDate!))
        }
        #expect(changed.totalWeeks == p.totalWeeks + 1)
    }
}
