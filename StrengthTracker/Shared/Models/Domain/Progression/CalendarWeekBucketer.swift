import Foundation

/// Restructures programmed sessions into Monday-anchored calendar-week buckets (Model A).
///
/// Programming (intensity / deload) is generated per microcycle: the k-th microcycle's
/// sessions land on the k-th occurrence of each training day on/after the plan start date
/// (`assignSequentialDates`). Plan *weeks* are then re-derived as calendar-week buckets of
/// those dated sessions (`rebucket`): a Saturday start yields a week 1 containing only the
/// Sat/Sun sessions, middle weeks run Mon–Sun, and the final week may be partial.
/// Deload remains a per-session truth (`PlannedSession.isDeload`).
public enum CalendarWeekBucketer {

    /// Monday-first calendar used for all week bucketing.
    public static var mondayCalendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    /// Start of the Monday-anchored week containing `date`.
    public static func weekStart(of date: Date, calendar: Calendar = mondayCalendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    // MARK: - Sequential Date Assignment (microcycle semantics)

    /// Assigns concrete scheduled dates to sessions while weeks are still microcycles
    /// (`absoluteWeekNumber` == microcycle index): the k-th microcycle uses the k-th
    /// occurrence of each training day on/after `startDate`.
    ///
    /// - Parameter onlyMissing: when true, only sessions with a nil `scheduledDate` are
    ///   dated (migration mode — preserves user-rescheduled dates).
    public static func assignSequentialDates(
        to blocks: inout [TrainingBlock],
        startDate: Date,
        onlyMissing: Bool = false,
        calendar: Calendar = .current
    ) {
        let planStartDay = calendar.startOfDay(for: startDate)
        let startWeekday = calendar.component(.weekday, from: planStartDay) // Sun=1..Sat=7

        for blockIdx in blocks.indices {
            for weekIdx in blocks[blockIdx].weeks.indices {
                let weekNum = blocks[blockIdx].weeks[weekIdx].absoluteWeekNumber
                let weekAnchor = calendar.date(byAdding: .day, value: (weekNum - 1) * 7, to: planStartDay)!

                for sessionIdx in blocks[blockIdx].weeks[weekIdx].sessions.indices {
                    if onlyMissing,
                       blocks[blockIdx].weeks[weekIdx].sessions[sessionIdx].scheduledDate != nil {
                        continue
                    }
                    guard let dow = blocks[blockIdx].weeks[weekIdx].sessions[sessionIdx].dayOfWeek else { continue }
                    let dayOffset = (dow - startWeekday + 7) % 7
                    let sessionDate = calendar.date(byAdding: .day, value: dayOffset, to: weekAnchor)!
                    blocks[blockIdx].weeks[weekIdx].sessions[sessionIdx].scheduledDate = sessionDate
                }
            }
        }
    }

    // MARK: - Calendar-Week Re-bucketing

    /// Regroups each block's sessions into Monday-anchored calendar-week buckets.
    ///
    /// - The anchor is the week start of the earliest session date across ALL blocks, so
    ///   week 1 is never empty. If no session has a date, the blocks are returned unchanged.
    /// - Sessions with a nil `scheduledDate` stay grouped with their original week's other
    ///   sessions: they fall into the bucket of the original week's earliest dated session.
    ///   A week with no dated sessions at all is carried through verbatim, appended after
    ///   the dated buckets in original order (deterministic; cannot be calendar-bucketed).
    /// - Idempotent: bucket week ids are reused via a per-block weekStart → existing week id
    ///   map (first wins), so re-running on already-bucketed blocks produces identical
    ///   structure and ids.
    public static func rebucket(
        _ blocks: [TrainingBlock],
        calendar: Calendar = mondayCalendar
    ) -> [TrainingBlock] {
        let allDates = blocks
            .flatMap(\.weeks)
            .flatMap(\.sessions)
            .compactMap(\.scheduledDate)
        guard let earliest = allDates.min() else { return blocks }
        let anchor = weekStart(of: earliest, calendar: calendar)

        return blocks.map { block in
            rebucketBlock(block, anchor: anchor, calendar: calendar)
        }
    }

    private static func rebucketBlock(
        _ block: TrainingBlock,
        anchor: Date,
        calendar: Calendar
    ) -> TrainingBlock {
        // Map weekStart → existing week (first wins), keyed by the week's own earliest
        // dated session. Enables id reuse and field preservation across re-runs.
        var existingWeekByStart: [Date: TrainingWeek] = [:]
        for week in block.weeks {
            guard let earliest = week.sessions.compactMap(\.scheduledDate).min() else { continue }
            let key = weekStart(of: earliest, calendar: calendar)
            if existingWeekByStart[key] == nil {
                existingWeekByStart[key] = week
            }
        }

        // Group sessions into buckets keyed by weekStart; undated weeks pass through verbatim.
        var buckets: [Date: [PlannedSession]] = [:]
        var undatedWeeks: [TrainingWeek] = []
        for week in block.weeks {
            let fallbackKey = week.sessions.compactMap(\.scheduledDate).min()
                .map { weekStart(of: $0, calendar: calendar) }
            guard let fallbackKey else {
                undatedWeeks.append(week)
                continue
            }
            for session in week.sessions {
                let key = session.scheduledDate.map { weekStart(of: $0, calendar: calendar) } ?? fallbackKey
                buckets[key, default: []].append(session)
            }
        }

        var newWeeks: [TrainingWeek] = buckets.keys.sorted().enumerated().map { ordinal, start in
            let sessions = buckets[start]!.sorted {
                ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture)
            }
            let daysFromAnchor = calendar.dateComponents([.day], from: anchor, to: start).day ?? 0
            let existing = existingWeekByStart[start]
            return TrainingWeek(
                id: existing?.id ?? UUID(),
                weekNumber: ordinal + 1,
                absoluteWeekNumber: daysFromAnchor / 7 + 1,
                sessions: sessions,
                isDeload: !sessions.isEmpty && sessions.allSatisfy(\.isDeload),
                isCompleted: existing?.isCompleted ?? false,
                completedAt: existing?.completedAt
            )
        }
        newWeeks.append(contentsOf: undatedWeeks)

        var newBlock = block
        newBlock.weeks = newWeeks
        newBlock.durationWeeks = newWeeks.count
        return newBlock
    }
}
