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

    // MARK: - label

    @Test("elapsedSeconds == 0 → \"0s\"")
    func labelZeroSeconds() {
        let cal = Self.utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!
        let display = SessionAgeDisplay(timestamp: now, now: now, calendar: cal)
        #expect(display.label == "0s")
    }

    @Test("elapsedSeconds == 54 → \"54s\"")
    func label54Seconds() {
        let cal = Self.utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!
        let timestamp = now.addingTimeInterval(-54)
        let display = SessionAgeDisplay(timestamp: timestamp, now: now, calendar: cal)
        #expect(display.label == "54s")
    }

    /// Quirk: the `< 55` threshold means 55s rolls into the minutes bucket, where
    /// integer division yields `"0m"`. Test pins the contract as written.
    @Test("elapsedSeconds == 55 → \"0m\" (pre-existing < 55 threshold quirk)")
    func label55SecondsRollsToZeroMinutes() {
        let cal = Self.utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!
        let timestamp = now.addingTimeInterval(-55)
        let display = SessionAgeDisplay(timestamp: timestamp, now: now, calendar: cal)
        #expect(display.label == "0m")
    }

    @Test("elapsedSeconds == 3599 → \"59m\"")
    func label3599Seconds() {
        let cal = Self.utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!
        let timestamp = now.addingTimeInterval(-3599)
        let display = SessionAgeDisplay(timestamp: timestamp, now: now, calendar: cal)
        #expect(display.label == "59m")
    }

    @Test("elapsedSeconds == 3600 → \"1h\"")
    func label3600Seconds() {
        let cal = Self.utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!
        let timestamp = now.addingTimeInterval(-3600)
        let display = SessionAgeDisplay(timestamp: timestamp, now: now, calendar: cal)
        #expect(display.label == "1h")
    }

    @Test("elapsedSeconds == 86399 → \"23h\"")
    func label86399Seconds() {
        let cal = Self.utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!
        let timestamp = now.addingTimeInterval(-86399)
        let display = SessionAgeDisplay(timestamp: timestamp, now: now, calendar: cal)
        #expect(display.label == "23h")
    }

    @Test("elapsedSeconds == 86400 → \"1d\"")
    func label86400Seconds() {
        let cal = Self.utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!
        let timestamp = now.addingTimeInterval(-86400)
        let display = SessionAgeDisplay(timestamp: timestamp, now: now, calendar: cal)
        #expect(display.label == "1d")
    }

    @Test("Future timestamp clamps elapsedSeconds to 0 → \"0s\"")
    func labelFutureClampsToZero() {
        let cal = Self.utcCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!
        let future = now.addingTimeInterval(100)
        let display = SessionAgeDisplay(timestamp: future, now: now, calendar: cal)
        #expect(display.label == "0s")
    }
}
