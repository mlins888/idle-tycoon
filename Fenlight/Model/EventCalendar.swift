import Foundation

/// When festivals run. Each festival repeats every year on the same dates, so no server is needed.
enum EventCalendar {
    /// A festival's dates for one year.
    struct Window: Equatable {
        /// The calendar year the festival starts in (used to tell this year's progress from last year's).
        let year: Int
        let start: Date
        /// The moment it ends (midnight after the last day).
        let end: Date
    }

    /// The window that starts in `year`.
    static func window(_ event: EventDef, startingIn year: Int, calendar: Calendar = .current) -> Window {
        let wraps = (event.end.month, event.end.day) < (event.start.month, event.start.day)
        let start = calendar.date(from: DateComponents(year: year, month: event.start.month, day: event.start.day))!
        let lastDay = calendar.date(from: DateComponents(year: wraps ? year + 1 : year,
                                                         month: event.end.month, day: event.end.day))!
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay)!
        return Window(year: year, start: start, end: end)
    }

    /// The window that contains `date`, if the festival is running then.
    static func window(_ event: EventDef, containing date: Date, calendar: Calendar = .current) -> Window? {
        let year = calendar.component(.year, from: date)
        for y in [year, year - 1] {
            let w = window(event, startingIn: y, calendar: calendar)
            if date >= w.start && date < w.end { return w }
        }
        return nil
    }

    /// The festival running at `date`, with its window.
    static func active(_ events: [EventDef], at date: Date, calendar: Calendar = .current) -> (EventDef, Window)? {
        for e in events {
            if let w = window(e, containing: date, calendar: calendar) { return (e, w) }
        }
        return nil
    }

    /// The next festival to start after `date`.
    static func next(_ events: [EventDef], after date: Date, calendar: Calendar = .current) -> (EventDef, Window)? {
        let year = calendar.component(.year, from: date)
        return events.flatMap { e in
            [year, year + 1].map { (e, window(e, startingIn: $0, calendar: calendar)) }
        }
        .filter { $0.1.start > date }
        .min { $0.1.start < $1.1.start }
    }
}
