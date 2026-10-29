import Foundation
import Testing
@testable import RavenUI

@Suite struct StringsTests {
    let strings = Strings.shared

    @Test func bundledTableLoads() {
        #expect(strings.texts.count > 100)
        #expect(tr(.appName) == "Raven")
    }

    /// Every key the app uses exists in strings.en.json (the enum lists every key used).
    @Test func everyUsedKeyExists() {
        let missing = Str.allCases.filter { !strings.has($0.rawValue) }
        #expect(missing.isEmpty, "keys missing from strings.en.json: \(missing.map(\.rawValue))")
    }

    /// No source file looks a text up by a raw string key behind the enums' back.
    @Test func sourcesUseOnlyEnumKeys() throws {
        let sources = packageRoot.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("texts[\""), "raw key lookup in \(file.lastPathComponent)")
        }
    }

    /// Every `tr(.key)` in the sources names a case of `Str` (so `everyUsedKeyExists` covers it), and
    /// there is no fallback text table any more: every text comes from strings.en.json.
    @Test func noFallbackTexts() throws {
        #expect(!FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("MissingStrings.md").path))
        let sources = packageRoot.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let cases = Set(Str.allCases.map { "\($0)" })
        let pattern = try NSRegularExpression(pattern: #"tr\(\.([A-Za-z0-9]+)"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.range(of: #"\bProposed\b"#, options: .regularExpression) == nil,
                    "fallback texts in \(file.lastPathComponent)")
            for m in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let name = String(text[Range(m.range(at: 1), in: text)!])
                #expect(cases.contains(name), "\(file.lastPathComponent) uses tr(.\(name)), which is not a Str case")
            }
        }
    }

    @Test func placeholdersFill() {
        for key in Str.allCases {
            guard let template = strings.texts[key.rawValue] else { continue }
            let names = Strings.placeholders(in: template)
            var args: [String: String] = [:]
            for n in names { args[n] = "X" }
            let filled = tr(key, args)
            #expect(!filled.contains("{"), "\(key.rawValue) left a placeholder: \(filled)")
        }
        #expect(tr(.homeInTouch, ["when": "5 min ago"]) == "In touch 5 min ago")
        #expect(tr(.tickWaiting, ["name": "Mina", "time": "Wed 12:05"]) == "Waiting for Mina · until Wed 12:05")
    }

    @Test func optionListsMatchSettingValues() {
        #expect(strings.options(.settingsWhenQuitOptions).count == RavenSettings.whenQuitValues.count)
        #expect(strings.options(.settingsKeepChatsOptions).count == RavenSettings.keepChatsValues.count)
    }

    /// The time rules are the same in all three apps.
    @Test func timePhrases() {
        #expect(TimeText.heartbeat(since: 1) == "now")
        #expect(TimeText.heartbeat(since: 5) == "5 s")
        #expect(TimeText.heartbeat(since: 59) == "59 s")
        #expect(TimeText.heartbeat(since: 120) == "2 min ago")
        #expect(TimeText.ago(since: 30) == "just now")
        #expect(TimeText.ago(since: 300) == "5 min ago")
        #expect(TimeText.ago(since: 3 * 3600 + 50 * 60) == "3 h ago")
        #expect(TimeText.ago(since: 30 * 3600) == "1 day ago")
        #expect(TimeText.ago(since: 50 * 3600) == "2 days ago")
        #expect(TimeText.left(-5) == "about 1 min")
        #expect(TimeText.left(35 * 60) == "about 35 min")
        #expect(TimeText.left(34 * 60 + 10) == "about 35 min")          // minutes round up
        #expect(TimeText.left(60 * 60) == "about 1 hour")
        #expect(TimeText.left(89 * 60) == "about 1 hour")
        #expect(TimeText.left(90 * 60) == "about 2 hours")
        #expect(TimeText.left(22 * 3600 - 10 * 60) == "about 22 hours")
        #expect(TimeText.left(47 * 3600) == "about 47 hours")
        #expect(TimeText.left(72 * 3600) == "about 3 days")
        #expect(TimeText.secs(ms: 420) == "0.4")
    }

    /// `{time}`: weekday from `time.weekdays` and the 24-hour clock, in the local time zone.
    @Test func clockUsesTheWeekdayList() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let tuesday = Date(timeIntervalSince1970: 1_792_505_100)        // 2026-10-20 14:05 UTC, a Tuesday
        #expect(TimeText.clock(tuesday, calendar: calendar) == "Tue 14:05 (UTC)")
        #expect(TimeText.clock(tuesday.addingTimeInterval(5 * 86_400 + 10 * 3600), calendar: calendar) == "Mon 00:05 (UTC)")
        #expect(TimeText.clock(tuesday.addingTimeInterval(-2 * 86_400), calendar: calendar) == "Sun 14:05 (UTC)")
        #expect(strings.options(.timeWeekdays) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    }

    /// Every clock time names this computer's zone, as the CLI does (E2 r38): "UTC", "UTC+1",
    /// "UTC-5", "UTC+5:30", "UTC-3:30", from the offset at that time.
    @Test func clockTimesNameTheirZone() {
        let tuesday = Date(timeIntervalSince1970: 1_792_505_100)        // 2026-10-20 14:05 UTC
        func cal(_ seconds: Int) -> Calendar {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(secondsFromGMT: seconds)!
            return c
        }
        #expect(TimeText.zone(tuesday, calendar: cal(0)) == "UTC")
        #expect(TimeText.clock(tuesday, calendar: cal(3600)) == "Tue 15:05 (UTC+1)")
        #expect(TimeText.clock(tuesday, calendar: cal(-5 * 3600)) == "Tue 09:05 (UTC-5)")
        #expect(TimeText.clock(tuesday, calendar: cal(5 * 3600 + 1800)) == "Tue 19:35 (UTC+5:30)")
        #expect(TimeText.zone(tuesday, calendar: cal(-(3 * 3600 + 1800))) == "UTC-3:30")
        #expect(TimeText.bubble(ms: tuesday.ms, now: tuesday, calendar: cal(3600)) == "15:05 (UTC+1)")
        #expect(TimeText.deadline(ms: tuesday.ms + 7 * 86_400_000, now: tuesday, calendar: cal(3600))
                == "Tue 27 Oct 15:05 (UTC+1)")
        // Day lines stay a day ("Today", "Tue 2026-10-20"), as in the terminal app.
        #expect(!TimeText.day(ms: tuesday.ms, now: tuesday.addingTimeInterval(3 * 86_400), calendar: cal(3600)).contains("UTC"))
    }

    /// A deadline's `{time}` (E1 round 4): short from today to 5 days ahead, with the date from 6 days
    /// ahead (a week away read on the same weekday looked like now) and for a past one, as `raven
    /// contact list` says it.
    @Test func deadlineHasTheDateFromSixDaysAhead() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let sunday = Date(timeIntervalSince1970: 1_792_948_500)         // 2026-10-25 17:15 UTC, a Sunday
        let day: Int64 = 86_400_000
        let deadline = { (ms: Int64) in TimeText.deadline(ms: sunday.ms + ms, now: sunday, calendar: calendar) }
        #expect(deadline(0) == "Sun 17:15 (UTC)")
        #expect(deadline(day) == "Mon 17:15 (UTC)")
        #expect(deadline(5 * day) == "Fri 17:15 (UTC)")
        #expect(deadline(6 * day) == "Sat 31 Oct 17:15 (UTC)")
        #expect(deadline(7 * day) == "Sun 1 Nov 17:15 (UTC)")
        #expect(deadline(-day) == "Sat 24 Oct 17:15 (UTC)")
        // Days, not hours: 23:59 five days on is still short, 00:01 on the sixth is not.
        #expect(deadline(5 * day + 6 * 3_600_000 + 44 * 60_000) == "Fri 23:59 (UTC)")
        #expect(deadline(5 * day + 6 * 3_600_000 + 46 * 60_000) == "Sat 31 Oct 00:01 (UTC)")
        #expect(strings.options(.timeMonths).count == 12)
    }
}

/// The bundled copies must match the shared design files (run scripts/sync-design.sh after a change).
@Suite struct DesignSyncTests {
    @Test(arguments: [
        ("strings.en", "json", "strings.en.json"),
        ("tokens", "json", "tokens.json"),
        ("raven-mark-1024", "png", "assets/raven-mark-1024.png"),
        ("raven-mark-64", "png", "assets/raven-mark-64.png"),
    ])
    func bundledCopyMatchesDesign(name: String, ext: String, source: String) throws {
        let bundled = try #require(RavenResources.data(name, ext))
        let original = try Data(contentsOf: designRoot.appendingPathComponent(source))
        #expect(bundled == original, "\(source) changed: run scripts/sync-design.sh")
    }
}
