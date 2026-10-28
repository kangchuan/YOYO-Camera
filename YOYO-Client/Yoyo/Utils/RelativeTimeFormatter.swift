import Foundation

/// Relative timestamps for the history lists ("Just now", "3 minutes ago", "2 days ago").
///
/// Both `AutomationHistoryView` and `HistoryInspirationView` used to carry their own copy of this
/// logic, which is how `1 minutes ago` slipped through: the plural key was used for every count.
enum RelativeTimeFormatter {
    /// What to show once the gap is a day or more.
    enum BeyondDay {
        /// "3 days ago".
        case relative
        /// A concrete date and time — the inspiration history is a photo log, where an absolute
        /// timestamp is more useful than a running count.
        case absolute
    }

    static func string(from date: Date, now: Date = Date(), beyondDay: BeyondDay = .relative) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 {
            return String.timeJustNow.localized
        }
        if seconds < 3600 {
            return minutesText(seconds / 60)
        }
        if seconds < 86400 {
            return hoursText(seconds / 3600)
        }
        switch beyondDay {
        case .relative:
            return daysText(seconds / 86400)
        case .absolute:
            return date.formatted(
                .dateTime.year().month(.abbreviated).day().hour().minute()
                    .locale(LanguageManager.shared.locale)
            )
        }
    }

    static func minutesText(_ minutes: Int) -> String {
        minutes == 1 ? String.time1MinuteAgo.localized : String.timeMinutesAgo.localized(minutes)
    }

    static func hoursText(_ hours: Int) -> String {
        hours == 1 ? String.time1HourAgo.localized : String.timeHoursAgo.localized(hours)
    }

    static func daysText(_ days: Int) -> String {
        days == 1 ? String.time1DayAgo.localized : String.timeDaysAgo.localized(days)
    }
}
