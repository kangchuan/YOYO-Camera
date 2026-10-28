import Foundation
import Testing
@testable import Yoyo

struct AutomationFormattersTests {
    private let english = Locale(identifier: "en_US")
    private let chinese = Locale(identifier: "zh_Hans_CN")

    // MARK: - Month / day text

    @Test func monthDayTextUsesMonthNamesInEnglish() {
        #expect(AutomationFormatters.monthDayText(month: 10, day: 27, locale: english) == "October 27")
        #expect(AutomationFormatters.monthDayText(month: 1, day: 1, locale: english) == "January 1")
    }

    @Test func monthDayTextKeepsNumericMonthsInChinese() {
        #expect(AutomationFormatters.monthDayText(month: 10, day: 27, locale: chinese) == "10月27日")
        #expect(AutomationFormatters.monthDayText(month: 12, day: 31, locale: chinese) == "12月31日")
    }

    @Test func shortMonthText() {
        #expect(AutomationFormatters.shortMonthText(10, locale: english) == "Oct")
        #expect(AutomationFormatters.shortMonthText(10, locale: chinese) == "10月")
    }

    // MARK: - Ordinals

    @Test func englishOrdinals() {
        #expect(AutomationFormatters.ordinalName(1, locale: english) == "1st")
        #expect(AutomationFormatters.ordinalName(2, locale: english) == "2nd")
        #expect(AutomationFormatters.ordinalName(3, locale: english) == "3rd")
        #expect(AutomationFormatters.ordinalName(4, locale: english) == "4th")
        #expect(AutomationFormatters.ordinalName(5, locale: english) == "5th")
        #expect(AutomationFormatters.ordinalName(11, locale: english) == "11th")
        #expect(AutomationFormatters.ordinalName(21, locale: english) == "21st")
    }

    @Test func chineseOrdinalsStayNumeric() {
        #expect(AutomationFormatters.ordinalName(2, locale: chinese) == "第2")
    }

    // MARK: - Nth weekday phrase

    /// The real templates, duplicated here on purpose: this is the assertion that catches an English
    /// template regressing into "10 Nth 2 Weekday Tuesday".
    private let englishTemplate = "%4$@, %3$@ week of %1$@"
    private let chineseTemplate = "%2$@%3$@个%4$@"

    @Test func nthWeekdayReadsNaturallyInEnglish() {
        let output = AutomationFormatters.nthWeekdayText(
            template: englishTemplate,
            monthName: "October",
            shortMonth: "Oct",
            ordinal: AutomationFormatters.ordinalName(2, locale: english),
            weekday: "Tuesday"
        )
        #expect(output == "Tuesday, 2nd week of October")
    }

    @Test func nthWeekdayReadsNaturallyInChinese() {
        let output = AutomationFormatters.nthWeekdayText(
            template: chineseTemplate,
            monthName: "十月",
            shortMonth: AutomationFormatters.shortMonthText(10, locale: chinese),
            ordinal: AutomationFormatters.ordinalName(2, locale: chinese),
            weekday: "周二"
        )
        #expect(output == "10月第2个周二")
    }

    @Test func shippedNthWeekdayTemplatesUsePositionalPlaceholders() {
        let expected = ["en": englishTemplate, "zh-Hans": chineseTemplate]
        for (language, expectedTemplate) in expected {
            guard let template = rawString("summary_nth_weekday_of_month", language: language) else {
                Issue.record("Missing summary_nth_weekday_of_month in \(language).lproj")
                continue
            }
            #expect(template == expectedTemplate)
            // Unpositioned placeholders would shift arguments around once a translation reorders them.
            #expect(!template.contains("%@"))
            #expect(!template.contains("Nth"))
            let usedArguments = (1 ... 4).filter { template.contains("%\($0)$@") }
            #expect(usedArguments.count >= 2)
        }
    }

    @Test func shippedNthWeekdayTemplateRendersWithoutPlaceholders() {
        // Uses whatever language the test host is running in — the point is that nothing leaks.
        let output = AutomationFormatters.nthWeekdayText(month: 10, weekday: 3, nth: 2)
        #expect(!output.contains("%"))
        #expect(!output.contains("Nth"))
        #expect(!output.contains("月月"))
    }

    private func rawString(_ key: String, language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }
}
