import Foundation

extension Calendar {
    /// A calendar with Monday as the first day of the week,
    /// used consistently across all analytics services.
    public static var mondayStart: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }
}
