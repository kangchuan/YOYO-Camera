import Foundation
import Testing
@testable import Yoyo

struct RelativeTimeFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func text(secondsAgo: TimeInterval) -> String {
        RelativeTimeFormatter.string(from: now.addingTimeInterval(-secondsAgo), now: now)
    }

    // MARK: - Bucket boundaries

    @Test func underAMinuteIsJustNow() {
        #expect(text(secondsAgo: 0) == String.timeJustNow.localized)
        #expect(text(secondsAgo: 59) == String.timeJustNow.localized)
    }

    @Test func exactlyOneMinuteUsesSingularKey() {
        #expect(text(secondsAgo: 60) == String.time1MinuteAgo.localized)
        // 61s still rounds down to a single minute — that is where "1 minutes ago" used to appear.
        #expect(text(secondsAgo: 61) == String.time1MinuteAgo.localized)
    }

    @Test func pluralMinutesBeyondOne() {
        #expect(text(secondsAgo: 120) == String.timeMinutesAgo.localized(2))
        #expect(text(secondsAgo: 3599) == String.timeMinutesAgo.localized(59))
    }

    @Test func hoursBucket() {
        #expect(text(secondsAgo: 3600) == String.time1HourAgo.localized)
        #expect(text(secondsAgo: 3660) == String.time1HourAgo.localized)
        #expect(text(secondsAgo: 7200) == String.timeHoursAgo.localized(2))
        #expect(text(secondsAgo: 86_399) == String.timeHoursAgo.localized(23))
    }

    @Test func daysBucket() {
        #expect(text(secondsAgo: 86_400) == String.time1DayAgo.localized)
        #expect(text(secondsAgo: 86_460) == String.time1DayAgo.localized)
        #expect(text(secondsAgo: 61 * 86_400) == String.timeDaysAgo.localized(61))
    }

    @Test func futureTimestampsFallBackToJustNow() {
        #expect(text(secondsAgo: -30) == String.timeJustNow.localized)
    }

    // MARK: - BeyondDay styles

    @Test func absoluteStyleIsUsedPastADay() {
        let old = now.addingTimeInterval(-3 * 86_400)
        let relative = RelativeTimeFormatter.string(from: old, now: now)
        let absolute = RelativeTimeFormatter.string(from: old, now: now, beyondDay: .absolute)
        #expect(relative == String.timeDaysAgo.localized(3))
        #expect(absolute != relative)
        #expect(!absolute.isEmpty)
    }

    @Test func absoluteStyleStillUsesRelativeTextWithinADay() {
        let recent = now.addingTimeInterval(-120)
        #expect(
            RelativeTimeFormatter.string(from: recent, now: now, beyondDay: .absolute)
                == String.timeMinutesAgo.localized(2)
        )
    }
}
