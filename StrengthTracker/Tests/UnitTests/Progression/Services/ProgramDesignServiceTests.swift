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

@Suite("Structural plan edits")
struct PlanStructureEditingTests {
    let cal = CalendarWeekBucketer.mondayCalendar
    var now: Date { CalendarWeekBucketer.weekStart(of: ProgressionTestHelpers.fixedMondayStart) }
    let settings = PlanConfiguration(durationWeeks: 12, deloadWeightPercentage: 50, deloadRestPercentage: 75)
    func date(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: now)! }
    func fixture() -> (ProgressionPlan, [WorkoutTemplate], [Exercise]) {
        let row = Exercise(id: UUID(), name: "Iso-lateral row", primaryMuscleGroup: .back, secondaryMuscleGroups: [],
            category: .cable, exerciseType: .weightedReps, instructions: nil, isCustom: true, isArchived: false,
            weightRecording: .sides())
        let press = Exercise(id: UUID(), name: "Press", primaryMuscleGroup: .chest, secondaryMuscleGroups: [],
            category: .machine, exerciseType: .weightedReps, instructions: nil, isCustom: true, isArchived: false)
        let template = WorkoutTemplate(id: UUID(), name: "Push", notes: nil, sortOrder: 0, lastUsedAt: nil, timesUsed: 0,
            exercises: [row, press].enumerated().map { index, e in
                .init(id: UUID(), exercise: e, order: index, supersetGroup: nil, notes: nil, restTimerSeconds: 120,
                    targetSets: 3, targetReps: 8, targetWeight: 41, targetDurationSeconds: nil, targetDistanceMeters: nil)
            })
        let pe = PlanExercise(exerciseId: row.id, exerciseName: row.name, primaryMuscleGroup: .back, category: .cable,
            estimated1RM: 50, oneRMSource: .userInput, current1RM: 50, isCompound: true, order: 0, weightRecording: row.weightRecording)
        let weeks: [TrainingWeek] = (1...12).map { week in
            let values = [0, 2, 3, 5, 6].map { offset in
                let d = date((week - 1) * 7 + offset)
                return PlannedSession(dayOfWeek: cal.component(.weekday, from: d), scheduledDate: d,
                    sessionLabel: "Monday - Power", plannedExercises: [.init(planExerciseId: pe.id, exerciseId: row.id,
                        exerciseName: row.name, sets: 3, targetReps: 8, targetWeight: 41, percentageOf1RM: 0.8, weightRecording: row.weightRecording)],
                    templateId: template.id, programmingWeekID: UUID(), programmingWeekNumber: week)
            }
            return TrainingWeek(weekNumber: week, absoluteWeekNumber: week, sessions: values)
        }
        let plan = ProgressionPlan(name: "Twelve weeks", status: .active, trainingStatus: .advanced, programType: .linear,
            primaryGoal: .strength, weeklyFrequency: 5, trainingDays: [2, 4, 5, 7, 1], startDate: now,
            targetEndDate: date(83), exercises: [pe], blocks: [.init(name: "Training", order: 0, durationWeeks: 12, weeks: weeks)], configuration: settings)
        return (plan, [template], [row, press])
    }
    func apply(_ request: PlanEditRequest, _ plan: ProgressionPlan, templates: [WorkoutTemplate] = [], exercises: [Exercise] = [], protected: Set<UUID> = []) throws -> ProgressionPlan {
        try PlanEditingService.applying(request, to: plan, settings: settings, templates: templates, exercises: exercises, protectedSessionIDs: protected, now: now)
    }
    func week(_ plan: ProgressionPlan, _ number: Int) -> [PlannedSession] { plan.blocks.flatMap(\.weeks).filter { $0.absoluteWeekNumber == number }.flatMap(\.sessions) }

    @Test("Five sessions become three dated deload sessions in one reversible change")
    func threeSessionDeload() throws {
        let (p, templates, exercises) = fixture(); let before = week(p, 5)
        let placements = [0, 2, 4].enumerated().map { offset, index in
            PlanSessionPlacement(sessionID: before[index].id, date: date(28 + [1, 4, 6][offset]))
        }
        let edited = try apply(.init(operation: .setWeekSchedule, week: 5, schedule: placements, isDeload: true), p, templates: templates, exercises: exercises)
        let actual = week(edited, 5)
        #expect(actual.count == 3)
        #expect(actual.allSatisfy { $0.isDeload && !$0.isSkipped && !$0.isOmitted })
        #expect(actual.allSatisfy { $0.plannedExercises[0].targetWeight == 20.5 && $0.deloadPrescription?.restPercentage == 75 })
        #expect(actual[0].displayLabel == "Push")
        #expect(actual.map(\.id) == placements.map { $0.sessionID! })
        #expect(edited.totalWeeks == 12 && edited.targetEndDate == p.targetEndDate)
        #expect(week(edited, 6) == week(p, 6))
        let restored = try apply(.init(operation: .undoEdit, editID: edited.adjustments.last!.id), edited)
        #expect(PlanScheduleSnapshot(restored) == PlanScheduleSnapshot(p))
    }

    @Test("An empty first or last week stays dated without changing numbering or finish", arguments: [1, 12])
    func restWeek(number: Int) throws {
        let (p, _, _) = fixture()
        let changed = try apply(.init(operation: .setWeekSchedule, week: number, schedule: []), p)
        #expect(week(changed, number).isEmpty)
        #expect(changed.totalWeeks == 12 && changed.targetEndDate == p.targetEndDate)
        #expect(changed.blocks.flatMap(\.weeks).first { $0.absoluteWeekNumber == number }?.weekStartDate == date((number - 1) * 7))
        let rebucketed = CalendarWeekBucketer.rebucket(changed.blocks)
        #expect(rebucketed.flatMap(\.weeks).contains { $0.absoluteWeekNumber == number && $0.sessions.isEmpty })
        #expect(PlanEditingService.weekSummaries(changed).first { $0.week == number }?.restWeek == true)
    }

    @Test("Atomic batch moves, renames and removes; failed operation leaves source intact")
    func atomicBatch() throws {
        let (p, _, _) = fixture(); let first = week(p, 5)[0], remove = week(p, 5)[1]
        let batch = PlanEditRequest(operation: .batch, operations: [
            .init(operation: .rescheduleSession, sessionID: first.id, newDate: date(29), scope: .session),
            .init(operation: .updateSession, sessionID: first.id, scope: .session, label: "Push A"),
            .init(operation: .removeSessions, sessionIDs: [remove.id])])
        let changed = try apply(batch, p)
        #expect(changed.adjustments.count == p.adjustments.count + 1)
        #expect(week(changed, 5).first { $0.id == first.id }?.sessionLabel == "Push A")
        var invalid = batch; invalid.operations?.append(.init(operation: .removeSessions, sessionIDs: [UUID()]))
        #expect(throws: PlanEditError.self) { try apply(invalid, p) }
        #expect(throws: PlanEditError.self) {
            try apply(.init(operation: .updateSession, sessionID: first.id, operations: batch.operations, label: "Ignored batch"), p)
        }
        #expect(week(p, 5).count == 5)
    }

    @Test("Partial weeks preserve completed and active sessions")
    func partialWeek() throws {
        var (p, _, _) = fixture(); let ids = week(p, 5).map(\.id)
        p.blocks[0].weeks[4].sessions[0].completedWorkoutId = UUID()
        let source = p
        #expect(throws: PlanEditError.self) { try apply(.init(operation: .setWeekSchedule, week: 5, schedule: []), source, protected: [ids[1]]) }
        let changed = try apply(.init(operation: .setWeekSchedule, week: 5, schedule: [], remainingOnly: true), p, protected: [ids[1]])
        #expect(week(changed, 5).map(\.id) == Array(ids.prefix(2)))
        #expect(week(changed, 5)[0] == week(p, 5)[0])
        #expect(throws: PlanEditError.self) { try apply(.init(operation: .removeSessions, sessionIDs: [ids[1]]), source, protected: [ids[1]]) }
    }

    @Test("Removed session restores with the same identity, with conflict-aware undo")
    func restoreAndConflict() throws {
        let (p, _, _) = fixture(); let s = week(p, 5)[0]
        let removed = try apply(.init(operation: .removeSessions, sessionIDs: [s.id]), p)
        let renamed = try apply(.init(operation: .updateSession, sessionID: week(p, 6)[0].id, scope: .session, label: "New name"), removed)
        #expect(throws: PlanEditError.self) { try apply(.init(operation: .undoEdit, editID: removed.adjustments.last!.id), renamed) }
        let restored = try apply(.init(operation: .restoreSession, sessionID: s.id, editID: removed.adjustments.last!.id), renamed)
        #expect(week(restored, 5).contains(s))
        #expect(throws: PlanEditError.self) { try apply(.init(operation: .restoreSession, sessionID: s.id, editID: removed.adjustments.last!.id), restored) }
    }

    @Test("Recurring three-day schedule leaves earlier weeks intact")
    func recurring() throws {
        let (p, _, _) = fixture()
        let rules: [PlanDayRule] = [.init(sourceWeekday: 2, weekday: 3), .init(sourceWeekday: 5, weekday: 5), .init(sourceWeekday: 1, weekday: 1)]
        let changed = try apply(.init(operation: .changeSchedule, week: 5, weeklySchedule: rules), p)
        #expect(changed.weeklyFrequency == 3 && changed.trainingDays == [1, 3, 5])
        #expect(week(changed, 4) == week(p, 4))
        #expect((5...12).allSatisfy { week(changed, $0).count == 3 })
        #expect(week(changed, 5).map(\.dayOfWeek) == [3, 5, 1])
    }

    @Test("Rest insertion shifts remaining training without losing sessions")
    func insertRest() throws {
        let (p, _, _) = fixture()
        let changed = try apply(.init(operation: .insertRestWeek, week: 5, weeks: 2), p)
        #expect(changed.totalWeeks == 14)
        #expect(week(changed, 5).isEmpty && week(changed, 6).isEmpty)
        #expect(Set(PlanEditingService.sessions(changed).map(\.id)) == Set(PlanEditingService.sessions(p).map(\.id)))
        #expect(week(changed, 7).map(\.id) == week(p, 5).map(\.id))
        #expect(changed.targetEndDate == date(97))
    }

    @Test("Explicit shortening removes only the future tail; ordinary removal preserves end")
    func shorten() throws {
        let (p, _, _) = fixture()
        let changed = try apply(.init(operation: .shortenPlan, newDate: date(55)), p)
        #expect(changed.totalWeeks == 8 && changed.targetEndDate == date(55))
        #expect(week(changed, 8) == week(p, 8))
        let removed = try apply(.init(operation: .removeSessions, sessionIDs: week(p, 12).map(\.id)), p)
        #expect(removed.totalWeeks == 12 && removed.targetEndDate == p.targetEndDate)
    }

    @Test("Added and duplicated sessions get fresh identities and no completion links")
    func addAndDuplicate() throws {
        let (p, templates, exercises) = fixture()
        let added = try apply(.init(operation: .addSession, newDate: date(29), templateID: templates[0].id, label: "Extra"), p, templates: templates, exercises: exercises)
        #expect(week(added, 5).count == 6)
        #expect(week(added, 5).first { $0.displayLabel == "Extra" }?.exerciseSnapshot != nil)
        let duplicated = try apply(.init(operation: .duplicateSession, sessionID: week(p, 5)[0].id, newDate: date(30)), p)
        let fresh = try #require(week(duplicated, 5).first { !week(p, 5).map(\.id).contains($0.id) })
        #expect(fresh.completedWorkoutId == nil && !fresh.isSkipped)
        #expect(fresh.plannedExercises == week(p, 5)[0].plannedExercises)
    }

    @Test("Reordered/removed exercises stay authoritative when a linked template changes")
    func explicitContents() throws {
        let (p, templates, exercises) = fixture(); let source = week(p, 5)[0]
        let all = try PlanEditingService.editableContents(for: source, plan: p, templates: templates, exercises: exercises)
        #expect(all.count == 2)
        let edited = try apply(.init(operation: .setSessionExercises, sessionID: source.id, scope: .session, contents: [all[0]]), p, templates: templates, exercises: exercises)
        let s = try #require(week(edited, 5).first { $0.id == source.id })
        let actual = s.resolvedTemplate(linked: templates[0], exercises: exercises)
        #expect(actual.exercises.count == 1)
        #expect(actual.exercises[0].exercise.category == .cable)
        #expect(actual.exercises[0].exercise.weightRecording == .sides())
        #expect(actual.instantiateExercises()[0].sets[0].weight == 41)
        #expect(templates[0].exercises.count == 2)
    }

    @Test("Exercise swap cannot reintroduce the original template exercise")
    func swapLaunch() throws {
        let (p, templates, exercises) = fixture(); let s = week(p, 5)[0]
        let changed = try apply(.init(operation: .changeExercise, sessionID: s.id, scope: .session,
            exerciseID: exercises[0].id, replacementExerciseID: exercises[1].id, reps: 6, weightKg: 30), p, templates: templates, exercises: exercises)
        let launched = week(changed, 5)[0].resolvedTemplate(linked: templates[0], exercises: exercises)
        #expect(!launched.exercises.contains { $0.exercise.id == exercises[0].id })
        #expect(launched.exercises[0].exercise.category == .machine)
        #expect(launched.exercises[0].targetWeight == 30)
    }

    @Test("Deload content edits use normal loads once and restore the normal prescription")
    func normalDeloadTargets() throws {
        let (p, templates, exercises) = fixture(); let s = week(p, 5)[0]
        let deloaded = try apply(.init(operation: .convertDeload, week: 5), p)
        let changed = try apply(.init(operation: .changeTargets, sessionID: s.id, scope: .session, exerciseID: exercises[0].id, weightKg: 42), deloaded, templates: templates, exercises: exercises)
        let actual = week(changed, 5)[0].resolvedTemplate(linked: templates[0], exercises: exercises)
        #expect(actual.exercises[0].targetWeight == 21)
        #expect(actual.exercises[0].setTargets.allSatisfy { $0.targetWeight == 21 })
        let normal = try apply(.init(operation: .removeDeload, week: 5), changed, templates: templates, exercises: exercises)
        #expect(week(normal, 5)[0].resolvedTemplate(linked: templates[0], exercises: exercises).exercises[0].targetWeight == 42)
    }

    @Test("Renaming does not change template or targets and preserves custom labels when moving")
    func renameMove() throws {
        let (p, templates, exercises) = fixture(); let s = week(p, 5)[0]
        let request = PlanEditRequest(operation: .updateSession, sessionID: s.id, scope: .session, label: "Monday favourite", notes: "Keep two reps in reserve")
        let renamed = try apply(request, p)
        let moved = try apply(.init(operation: .rescheduleSession, sessionID: s.id, newDate: date(29), scope: .session), renamed, templates: templates)
        let actual = week(moved, 5)[0]
        #expect(actual.sessionLabel == "Monday favourite")
        #expect(actual.templateId == s.templateId && actual.plannedExercises == s.plannedExercises)
        #expect(actual.resolvedTemplate(linked: templates[0], exercises: exercises).notes == "Keep two reps in reserve")
        #expect(templates[0].notes == nil)
        let preview = try PlanEditingService.preview(plan: p, request: request, settings: settings, templates: templates, exercises: exercises, now: now)
        #expect(preview.detailLines?.first?.contains("Notes: Keep two reps in reserve") == true)
    }

    @Test("Review shows before and after targets, side conventions, rest and effort")
    func detailedTargetReview() throws {
        let (p, templates, exercises) = fixture(); let s = week(p, 5)[0]
        let preview = try PlanEditingService.preview(plan: p, request: .init(operation: .changeTargets,
            sessionID: s.id, scope: .session, exerciseID: exercises[0].id, reps: 10, weightKg: 42, restSeconds: 90, targetRPE: 8),
            settings: settings, templates: templates, exercises: exercises, now: now)
        let detail = try #require(preview.detailLines?.first)
        for expected in ["Before:", "After:", "41 Kg/side", "42 Kg/side", "8 Reps/side", "10 Reps/side", "Rest 90 sec", "Target RPE 8"] {
            #expect(detail.contains(expected))
        }
    }

    @Test("Past unperformed sessions can move; removing them requires an explicit correction")
    func overdue() throws {
        let (p, _, _) = fixture(); let s = week(p, 1)[0]; let later = date(3)
        let request = PlanEditRequest(operation: .rescheduleSession, sessionID: s.id, newDate: date(5), scope: .session)
        let moved = try PlanEditingService.applying(request, to: p, settings: settings, now: later)
        #expect(PlanEditingService.sessions(moved).first { $0.id == s.id }?.scheduledDate == date(5))
        #expect(throws: PlanEditError.self) { try PlanEditingService.applying(.init(operation: .removeSessions, sessionIDs: [s.id]), to: p, settings: settings, now: later) }
        let preview = try PlanEditingService.preview(plan: p, request: .init(operation: .removeSessions, sessionIDs: [s.id], correctionReason: "Session was added accidentally"), settings: settings, now: later)
        #expect(preview.summaryLines.contains { $0.contains("adherence") })
    }

    @Test("Edit journal and frozen preview survive Codable without rewriting legacy data")
    func coding() throws {
        let (p, _, _) = fixture()
        let preview = try PlanEditingService.preview(plan: p, request: .init(operation: .setWeekSchedule, week: 5, schedule: []), settings: settings, now: now)
        let copy = try JSONDecoder().decode(PlanEditPreview.self, from: JSONEncoder().encode(preview))
        #expect(copy == preview)
        let edited = try apply(.init(operation: .setWeekSchedule, week: 5, schedule: []), p)
        #expect(try JSONDecoder().decode(ProgressionPlan.self, from: JSONEncoder().encode(edited)) == edited)
    }
}

extension PlanStructureEditingTests {
    @Test("Template replacement preserves distinct repeated exercise occurrences and timed targets")
    func repeatedAndTimedTemplate() throws {
        let (p, _, exercises) = fixture(); let s = week(p, 5)[0]
        let timer = Exercise(id: UUID(), name: "Plank", primaryMuscleGroup: .core, secondaryMuscleGroups: [], category: .bodyweight,
            exerciseType: .duration, instructions: nil, isCustom: true, isArchived: false)
        let template = WorkoutTemplate(id: UUID(), name: "Mixed", notes: nil, sortOrder: 0, lastUsedAt: nil, timesUsed: 0, exercises: [
            .init(id: UUID(), exercise: exercises[0], order: 0, supersetGroup: nil, notes: nil, restTimerSeconds: 60, targetSets: 1, targetReps: 10, targetWeight: 10, targetDurationSeconds: nil, targetDistanceMeters: nil, isWarmUp: true),
            .init(id: UUID(), exercise: exercises[0], order: 1, supersetGroup: nil, notes: nil, restTimerSeconds: 120, targetSets: 3, targetReps: 8, targetWeight: 41, targetDurationSeconds: nil, targetDistanceMeters: nil),
            .init(id: UUID(), exercise: timer, order: 2, supersetGroup: nil, notes: nil, restTimerSeconds: 60, targetSets: 2, targetReps: nil, targetWeight: nil, targetDurationSeconds: 45, targetDistanceMeters: nil)
        ])
        let changed = try apply(.init(operation: .changeTemplate, sessionID: s.id, scope: .session, templateID: template.id), p, templates: [template], exercises: exercises + [timer])
        let actual = week(changed, 5)[0].resolvedTemplate(linked: template, exercises: exercises + [timer])
        #expect(actual.exercises.count == 3)
        #expect(Set(actual.exercises.map(\.id)).count == 3)
        #expect(actual.exercises[0].isWarmUp)
        #expect(actual.instantiateExercises()[2].sets[0].durationSeconds == 45)
        #expect(actual.exercises[0].exercise.category == .cable)
        let preview = try PlanEditingService.preview(plan: p, request: .init(operation: .changeTemplate, sessionID: s.id, scope: .session, templateID: template.id),
            settings: settings, templates: [template], exercises: exercises + [timer], now: now)
        #expect(preview.detailLines?.first?.contains("Plank: 2 sets · 45 sec") == true)
    }

    @Test("Moving retained omitted deload sessions schedules them and preserves the captured policy")
    func retainedDeloadPolicy() throws {
        var (p, templates, exercises) = fixture(); p.deloadDays = [2]
        let deloaded = try apply(.init(operation: .convertDeload, week: 5, deloadWeightPercentage: 60, deloadRestPercentage: 50), p)
        let source = week(deloaded, 5)[1]
        #expect(source.isOmitted)
        let schedule = [PlanSessionPlacement(sessionID: source.id, templateID: templates[0].id, date: date(29))]
        let changed = try apply(.init(operation: .setWeekSchedule, week: 5, schedule: schedule), deloaded, templates: templates, exercises: exercises)
        let actual = try #require(week(changed, 5).first)
        #expect(actual.isDeload && !actual.isOmitted)
        #expect(actual.deloadPrescription?.weightPercentage == 60)
        #expect(actual.plannedExercises[0].targetWeight == 24.6)
    }

    @Test("Moving a schedule uses calendar days across clock and month boundaries")
    func calendarDayShift() throws {
        var (p, _, _) = fixture()
        let february = cal.date(from: DateComponents(year: 2026, month: 2, day: 23))!
        let offset = cal.dateComponents([.day], from: now, to: february).day!
        p.startDate = february
        p.targetEndDate = cal.date(byAdding: .day, value: offset, to: p.targetEndDate!)
        for w in p.blocks[0].weeks.indices { for i in p.blocks[0].weeks[w].sessions.indices {
            p.blocks[0].weeks[w].sessions[i].scheduledDate = cal.date(byAdding: .day, value: offset, to: p.blocks[0].weeks[w].sessions[i].scheduledDate!)
        } }
        let moved = try PlanEditingService.applying(.init(operation: .shiftSchedule, newDate: february, days: 56), to: p, settings: settings, now: february)
        for source in PlanEditingService.sessions(p) {
            let target = try #require(PlanEditingService.sessions(moved).first { $0.id == source.id })
            #expect(target.scheduledDate == cal.date(byAdding: .day, value: 56, to: source.scheduledDate!))
            #expect(cal.component(.hour, from: target.scheduledDate!) == cal.component(.hour, from: source.scheduledDate!))
            #expect(target.dayOfWeek == source.dayOfWeek)
        }
    }

    @Test("A single explicit removal never broadens to the surrounding week")
    func exactRemoval() throws {
        let (p, _, _) = fixture(); let source = week(p, 5)[0]
        let changed = try apply(.init(operation: .removeSessions, sessionID: source.id), p)
        #expect(week(changed, 5).count == 4)
        #expect(!week(changed, 5).contains { $0.id == source.id })
    }
}
