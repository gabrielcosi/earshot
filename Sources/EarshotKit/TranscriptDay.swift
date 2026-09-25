import Foundation

/// The heading a saved transcript is listed under.
public enum TranscriptDay: Hashable, Sendable {
    case today
    case yesterday
    case previousSevenDays
    case previousThirtyDays
    /// Earlier this year.
    case month(Int)
    /// An earlier year.
    case year(Int)

    /// The headings Apple Notes lists notes under: days back by the calendar, not by 24-hour
    /// periods, so last night's call is yesterday's.
    public static func of(_ date: Date, now: Date = .now, calendar: Calendar = .current)
        -> TranscriptDay
    {
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
            ).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .yesterday
        case 2...7: return .previousSevenDays
        case 8...30: return .previousThirtyDays
        default:
            let year = calendar.component(.year, from: date)
            return year == calendar.component(.year, from: now)
                ? .month(calendar.component(.month, from: date)) : .year(year)
        }
    }

    /// Items under their headings, newest first in both.
    public static func grouped<Item>(
        _ items: [Item], by date: (Item) -> Date, now: Date = .now,
        calendar: Calendar = .current
    ) -> [(day: TranscriptDay, items: [Item])] {
        var groups: [(day: TranscriptDay, items: [Item])] = []
        for item in items.sorted(by: { date($0) > date($1) }) {
            let day = of(date(item), now: now, calendar: calendar)
            if groups.last?.day == day {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((day, [item]))
            }
        }
        return groups
    }
}
