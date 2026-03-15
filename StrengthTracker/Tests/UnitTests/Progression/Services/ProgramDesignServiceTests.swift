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

    @Test("DUP program deload uses flat recovery prescription (50% 1RM, 2×8, no session type)")
    func testDUPProgram_deloadReducesVolume() {
        let plan = ProgressionTestHelpers.intermediateDUPPlan()
        let blocks = service.generateProgram(for: plan)

        let allWeeks = blocks.flatMap(\.weeks)
        guard let normalWeek = allWeeks.first(where: { !$0.isDeload }),
              let deloadWeek = allWeeks.first(where: { $0.isDeload }) else {
            Issue.record("Need both normal and deload weeks")
            return
        }

        // Volume should be reduced
        let normalVolume = totalSets(of: normalWeek)
        let deloadVolume = totalSets(of: deloadWeek)
        #expect(deloadVolume < normalVolume,
            "Deload volume (\(deloadVolume)) should be less than normal (\(normalVolume))")

        // Every deload session with exercises must use flat recovery prescription
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
                    "Deload intensity should be 50%, got \(exerciseSet.percentageOf1RM)")
                #expect(exerciseSet.sets == 2,
                    "Deload sets should be 2, got \(exerciseSet.sets)")
                #expect(exerciseSet.targetReps == 8,
                    "Deload reps should be 8, got \(exerciseSet.targetReps)")
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
        let plan = ProgressionTestHelpers.advancedBlockPlan()
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

    @Test("Block program intensity matches phase ranges")
    func testBlockProgram_intensityMatchesPhase() {
        let plan = ProgressionTestHelpers.advancedBlockPlan()
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

    @Test("All programs set isDeload correctly on sessions matching week.isDeload")
    func testAllPrograms_isDeloadMatchesWeek() {
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
                        #expect(session.isDeload == week.isDeload,
                            "\(plan.programType): session.isDeload (\(session.isDeload)) != week.isDeload (\(week.isDeload)) in week \(week.absoluteWeekNumber)")
                    }
                }
            }
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
