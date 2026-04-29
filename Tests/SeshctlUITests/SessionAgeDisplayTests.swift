import Foundation
import Testing

@testable import SeshctlUI


@Suite("SessionAgeDisplay")
struct SessionAgeDisplayTests {
    /// UTC Gregorian calendar — keeps day boundaries deterministic regardless of host TZ/DST.
    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// `Calendar.isDateInYesterday` is implemented against the wall clock, not against
    /// our synthetic `now`. To keep `.yesterday` cases hermetic-ish, anchor `now` to the
    /// real "today" in UTC so Foundation agrees on what "yesterday" is. Offsets within a
    /// case are still fully deterministic.
    private static func todayNoonUTC() -> Date {
        let cal = utcCalendar
        let startOfToday = cal.startOfDay(for: Date())
        return cal.date(byAdding: .hour, value: 12, to: startOfToday)!
    }

    // MARK: - bucket

    @Test("Same calendar day (morning of now) → .today")
    func bucketSameDayMorning() {
        let cal = Self.utcCalendar
        let now = Self.todayNoonUTC()
        let morning = cal.date(byAdding: .hour, value: -6, to: now)!
        let display = SessionAgeDisplay(timestamp: morning, now: now, calendar: cal)
        #expect(display.bucket == .today)
    }

    @Test("Same calendar day (one second before now) → .today")
    func bucketSameDayJustBefore() {
        let cal = Self.utcCalendar
        let now = Self.todayNoonUTC()
        let justBefore = now.addingTimeInterval(-1)
        let display = SessionAgeDisplay(timestamp: justBefore, now: now, calendar: cal)
        #expect(display.bucket == .today)
    }

    @Test("Late last night (23:59 the day before now) → .yesterday")
    func bucketLateLastNight() {
        let cal = Self.utcCalendar
        let now = Self.todayNoonUTC()
        let startOfToday = cal.startOfDay(for: now)
        let lateLastNight = cal.date(byAdding: .minute, value: -1, to: startOfToday)!
        let display = SessionAgeDisplay(timestamp: lateLastNight, now: now, calendar: cal)
        #expect(display.bucket == .yesterday)
    }

    @Test("Early yesterday morning (00:01 the day before now) → .yesterday")
    func bucketEarlyYesterdayMorning() {
        let cal = Self.utcCalendar
        let now = Self.todayNoonUTC()
        let startOfToday = cal.startOfDay(for: now)
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday)!
        let earlyYesterday = cal.date(byAdding: .minute, value: 1, to: startOfYesterday)!
        let display = SessionAgeDisplay(timestamp: earlyYesterday, now: now, calendar: cal)
        #expect(display.bucket == .yesterday)
    }

    @Test("Two days ago (midnight) → .older")
    func bucketTwoDaysAgo() {
        let cal = Self.utcCalendar
        let now = Self.todayNoonUTC()
        let startOfToday = cal.startOfDay(for: now)
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: startOfToday)!
        let display = SessionAgeDisplay(timestamp: twoDaysAgo, now: now, calendar: cal)
        #expect(display.bucket == .older)
    }

    @Test("Thirty days ago → .older")
    func bucketThirtyDaysAgo() {
        let cal = Self.utcCalendar
        let now = Self.todayNoonUTC()
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now)!
        let display = SessionAgeDisplay(timestamp: thirtyDaysAgo, now: now, calendar: cal)
        #expect(display.bucket == .older)
    }

    @Test("Future timestamp same calendar day (1 hour after now) → .today")
    func bucketFutureSameDay() {
        let cal = Self.utcCalendar
        let now = Self.todayNoonUTC()
        let futureSameDay = cal.date(byAdding: .hour, value: 1, to: now)!
        let display = SessionAgeDisplay(timestamp: futureSameDay, now: now, calendar: cal)
        #expect(display.bucket == .today)
    }

    /// Edge case: future timestamps on a *different* calendar day fall through to `.older`
    /// because `bucket` only recognizes today/yesterday/older — there is no `.tomorrow`.
    /// This is the documented current behavior; locked in here so a future change is intentional.
    @Test("Future timestamp on next calendar day → .older (no .tomorrow bucket)")
    func bucketFutureNextDay() {
        let cal = Self.utcCalendar
        let now = Self.todayNoonUTC()
        let nextDay = cal.date(byAdding: .day, value: 1, to: now)!
        let display = SessionAgeDisplay(timestamp: nextDay, now: now, calendar: cal)
        #expect(display.bucket == .older)
    }

    // MARK: - label (Gmail-like time format)
    //
    // Same calendar day → time of day (`"1:22 PM"`).
    // Different day, same calendar year → abbreviated month + day (`"Apr 14"`).
    // Different year → abbreviated month + day + year (`"Dec 1, 2025"`).
    //
    // Locale is pinned to `en_US` in tests so the format strings are stable
    // across machines / CI; production uses `.current`.

    private static let testLocale = Locale(identifier: "en_US")

    private static func displayAt(
        year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0,
        nowYear: Int = 2026, nowMonth: Int = 4, nowDay: Int = 15,
        nowHour: Int = 12, nowMinute: Int = 0
    ) -> SessionAgeDisplay {
        let cal = Self.utcCalendar
        let timestamp = cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
        let now = cal.date(from: DateComponents(
            year: nowYear, month: nowMonth, day: nowDay,
            hour: nowHour, minute: nowMinute
        ))!
        return SessionAgeDisplay(
            timestamp: timestamp, now: now, calendar: cal, locale: testLocale
        )
    }

    // macOS 13+ DateFormatter for en_US uses a narrow no-break space (U+202F)
    // between time and AM/PM marker. Test literals use \u{202F} to match the
    // formatter's natural output exactly.

    @Test("Same calendar day, equal timestamp → time of day")
    func labelSameDayEqual() {
        let display = Self.displayAt(year: 2026, month: 4, day: 15, hour: 12)
        #expect(display.label == "12:00\u{202F}PM")
    }

    @Test("Same calendar day, earlier today → time of day")
    func labelSameDayEarlier() {
        let display = Self.displayAt(year: 2026, month: 4, day: 15, hour: 9, minute: 11)
        #expect(display.label == "9:11\u{202F}AM")
    }

    @Test("Same calendar day, late evening → time of day")
    func labelSameDayEvening() {
        let display = Self.displayAt(year: 2026, month: 4, day: 15, hour: 23, minute: 30)
        #expect(display.label == "11:30\u{202F}PM")
    }

    @Test("Yesterday → MMM d")
    func labelYesterday() {
        let display = Self.displayAt(year: 2026, month: 4, day: 14, hour: 18)
        #expect(display.label == "Apr 14")
    }

    @Test("Earlier in same year → MMM d")
    func labelEarlierThisYear() {
        let display = Self.displayAt(year: 2026, month: 1, day: 3)
        #expect(display.label == "Jan 3")
    }

    @Test("Different year → MMM d, yyyy")
    func labelDifferentYear() {
        let display = Self.displayAt(year: 2025, month: 12, day: 1)
        #expect(display.label == "Dec 1, 2025")
    }

    @Test("Future timestamp same calendar day → time of day")
    func labelFutureSameDay() {
        let display = Self.displayAt(year: 2026, month: 4, day: 15, hour: 13, minute: 30)
        #expect(display.label == "1:30\u{202F}PM")
    }

    @Test("Future timestamp next calendar day → MMM d")
    func labelFutureNextDay() {
        let display = Self.displayAt(year: 2026, month: 4, day: 16, hour: 9)
        #expect(display.label == "Apr 16")
    }
}
