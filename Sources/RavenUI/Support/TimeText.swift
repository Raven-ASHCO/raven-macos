import Foundation

/// The time phrases of strings.en.json (`time.*`), with the same rules in all three apps:
/// `{when}` ("5 min ago"), the heartbeat's `{when}` ("now", "5 s"), `{left}` ("about 22 hours"),
/// `{time}` ("Tue 14:05") and `{secs}` ("0.4").
public enum TimeText {
    /// This computer's zone at `date`, named as the CLI and the terminal app name it (E2 r38: every
    /// time names its zone): "UTC", "UTC+1", "UTC-5", "UTC+5:30".
    public static func zone(_ date: Date, calendar: Calendar = .current) -> String {
        let off = calendar.timeZone.secondsFromGMT(for: date)
        if off == 0 { return "UTC" }
        let sign = off < 0 ? "-" : "+"
        let a = abs(off)
        let (h, m) = (a / 3600, a % 3600 / 60)
        return m == 0 ? "UTC\(sign)\(h)" : "UTC\(sign)\(h):" + String(format: "%02d", m)
    }

    /// A clock time with its zone, as the CLI writes it: "14:05 (UTC+1)".
    static func zoned(_ text: String, _ date: Date, calendar: Calendar) -> String {
        "\(text) (\(zone(date, calendar: calendar)))"
    }

    /// `{time}`: the local weekday from `time.weekdays` (Monday first) and the 24-hour clock with
    /// this computer's zone, e.g. "Tue 14:05 (UTC+1)". No system date formatter, so nothing appears
    /// in another language.
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let days = Strings.shared.options(.timeWeekdays)
        // Calendar weekday: 1 = Sunday ... 7 = Saturday; the list starts on Monday.
        let index = ((c.weekday ?? 2) + 5) % 7
        let day = days.indices.contains(index) ? days[index] : ""
        let hm = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        return zoned(day.isEmpty ? hm : day + " " + hm, date, calendar: calendar)
    }

    public static func clock(ms: Int64) -> String { clock(Date(ms: ms)) }

    /// `{time}` of a deadline seen at `now`: `clock` from today to 5 days ahead (each weekday names one
    /// day), else with the date too, "Sun 1 Nov 17:15 (UTC+1)" (month from `time.months`), as `raven
    /// contact list` says it: a deadline a week away must not read like today.
    public static func deadline(ms: Int64, now: Date, calendar: Calendar = .current) -> String {
        let date = Date(ms: ms)
        let ahead = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                            to: calendar.startOfDay(for: date)).day ?? 0
        if (0...5).contains(ahead) { return clock(date, calendar: calendar) }
        let c = calendar.dateComponents([.weekday, .day, .month, .hour, .minute], from: date)
        let days = Strings.shared.options(.timeWeekdays)
        let months = Strings.shared.options(.timeMonths)
        let index = ((c.weekday ?? 2) + 5) % 7
        let month = (c.month ?? 1) - 1
        let parts = [days.indices.contains(index) ? days[index] : "", String(c.day ?? 1),
                     months.indices.contains(month) ? months[month] : "",
                     String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)]
        return zoned(parts.filter { !$0.isEmpty }.joined(separator: " "), date, calendar: calendar)
    }

    /// The short time on a bubble with its zone: "13:26 (UTC+1)" for today, else the day too
    /// ("Tue 13:26 (UTC+1)").
    public static func bubble(ms: Int64, now: Date, calendar: Calendar = .current) -> String {
        let date = Date(ms: ms)
        guard calendar.isDate(date, inSameDayAs: now) else { return clock(date, calendar: calendar) }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return zoned(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0), date, calendar: calendar)
    }

    /// The line between two days of a chat: "Today", "Yesterday", else the weekday and the date
    /// ("Tue 2026-10-20"; no system date formatter, as for `clock`).
    public static func day(ms: Int64, now: Date, calendar: Calendar = .current) -> String {
        let date = Date(ms: ms)
        if calendar.isDate(date, inSameDayAs: now) { return tr(.chatToday) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return tr(.chatYesterday) }
        let c = calendar.dateComponents([.weekday, .year, .month, .day], from: date)
        let days = Strings.shared.options(.timeWeekdays)
        let index = ((c.weekday ?? 2) + 5) % 7
        let weekday = days.indices.contains(index) ? days[index] + " " : ""
        return weekday + String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whether two times fall on different days (a chat draws a day line between them).
    public static func differentDays(_ a: Int64, _ b: Int64, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(Date(ms: a), inSameDayAs: Date(ms: b))
    }

    /// `{when}` for the heartbeat: "now" for the first 3 seconds, then "4 s", then like `ago`.
    public static func heartbeat(since seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 3 { return tr(.timeNow) }
        if s < 60 { return tr(.timeSeconds, ["n": String(s)]) }
        return ago(since: seconds)
    }

    /// `{when}` for contact times: "just now", "5 min ago", "3 h ago", "1 day ago", "2 days ago".
    public static func ago(since seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return tr(.timeJustNow) }
        if s < 3600 { return tr(.timeMinutesAgo, ["n": String(s / 60)]) }
        if s < 86_400 { return tr(.timeHoursAgo, ["n": String(s / 3600)]) }
        let days = s / 86_400
        return days == 1 ? tr(.timeDayAgo) : tr(.timeDaysAgo, ["n": String(days)])
    }

    /// `{left}`: "about 40 min" under an hour (rounded up), then "about 1 hour", "about 22 hours",
    /// and from 48 hours "about 3 days".
    public static func left(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 3600 { return tr(.timeLeftMinutes, ["n": String(max(1, Int((s / 60).rounded(.up))))]) }
        let hours = Int((s / 3600).rounded())
        if hours == 1 { return tr(.timeLeftHour) }
        if hours < 48 { return tr(.timeLeftHours, ["n": String(hours)]) }
        return tr(.timeLeftDays, ["n": String(Int((s / 86_400).rounded()))])
    }

    /// `{secs}`: seconds with one decimal, from milliseconds ("0.4").
    public static func secs(ms: Int) -> String { String(format: "%.1f", Double(ms) / 1000) }
}

extension Date {
    public init(ms: Int64) { self.init(timeIntervalSince1970: TimeInterval(ms) / 1000) }
    public var ms: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}
