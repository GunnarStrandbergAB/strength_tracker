import Foundation

extension Calendar {
    /// A calendar with Monday as the first day of the week,
    /// used consistently across all analytics services.
    public static var mondayStart: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    /// Start of the week containing `date` under this calendar's first weekday.
    /// Bucket by this `Date`, never by a `.weekOfYear` integer (which collides
    /// across years).
    public func weekStart(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}

extension Workout {
    /// "When did I train": the canonical date every week/day bucketing uses.
    /// A session started Sunday 23:30 and finished after midnight belongs to Sunday.
    public var trainingDate: Date { startedAt }
}
