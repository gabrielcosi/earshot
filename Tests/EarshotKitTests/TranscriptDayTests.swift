import Foundation
import Testing

@testable import EarshotKit

@Suite struct TranscriptDayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
            ?? .distantPast
    }

    @Test func headingsFollowTheCalendarDay() {
        let now = date(2026, 9, 25, 9)
        let day = { TranscriptDay.of($0, now: now, calendar: calendar) }
        #expect(day(date(2026, 9, 25, 0)) == .today)
        #expect(day(date(2026, 9, 24, 23)) == .yesterday)
        #expect(day(date(2026, 9, 23)) == .previousSevenDays)
        #expect(day(date(2026, 9, 18)) == .previousSevenDays)
        #expect(day(date(2026, 9, 17)) == .previousThirtyDays)
        #expect(day(date(2026, 8, 26)) == .previousThirtyDays)
        #expect(day(date(2026, 8, 25)) == .month(8))
        #expect(day(date(2026, 1, 2)) == .month(1))
        #expect(day(date(2025, 12, 31)) == .year(2025))
    }

    @Test func previousDaysReachBackOverTheNewYear() {
        #expect(
            TranscriptDay.of(date(2025, 12, 28), now: date(2026, 1, 3), calendar: calendar)
                == .previousSevenDays)
    }

    /// A file dated ahead of the clock, after a time zone change, is still listed.
    @Test func aDateAheadOfNowIsToday() {
        #expect(
            TranscriptDay.of(date(2026, 9, 26), now: date(2026, 9, 25), calendar: calendar)
                == .today)
    }

    @Test func groupsAreNewestFirstAndSoAreTheirItems() {
        let now = date(2026, 9, 25, 18)
        let dates = [
            date(2026, 9, 24, 10), date(2026, 9, 25, 9), date(2026, 9, 25, 15),
            date(2026, 3, 1), date(2026, 9, 24, 20),
        ]
        let groups = TranscriptDay.grouped(dates, by: { $0 }, now: now, calendar: calendar)
        #expect(groups.map(\.day) == [.today, .yesterday, .month(3)])
        #expect(groups.first?.items == [date(2026, 9, 25, 15), date(2026, 9, 25, 9)])
        #expect(groups.dropFirst().first?.items == [date(2026, 9, 24, 20), date(2026, 9, 24, 10)])
    }
}

@Suite struct TranscriptFilenameTests {
    @Test func theFilenameGivesBackWhenTheSessionStarted() throws {
        let started = try #require(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 25, hour: 11, minute: 48)))
        let name = MarkdownExport.filename(for: started)
        #expect(MarkdownExport.date(fromFilename: name) == started)
    }

    @Test func aRenamedFileHasNoDateInItsName() {
        #expect(MarkdownExport.date(fromFilename: "Weekly sync.md") == nil)
    }
}
