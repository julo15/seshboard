import Foundation
import SwiftUI
import Testing

@testable import SeshctlUI

/// Smoke / type-level tests for `ResultRowLayout`. Per AGENTS.md, SwiftUI view
/// bodies are coverage-exempt — these tests verify that each existing call-site
/// shape (recall, session, remote) constructs and produces a value of the
/// expected concrete generic type.
///
/// The compiler is the primary verifier: if `ResultRowLayout`'s init signature
/// drifts in a way that breaks any caller, this file fails to build. The
/// runtime assertions (`MemoryLayout<...>.size > 0`) just confirm the
/// constructed value exists.
@Suite("ResultRowLayout")
struct ResultRowLayoutTests {
    /// Fixed reference time keeps the construction deterministic. The exact
    /// label / bucket isn't under test here — only that `ResultRowLayout`
    /// constructs.
    private static func sampleAgeDisplay() -> SessionAgeDisplay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!
        return SessionAgeDisplay(timestamp: now, now: now, calendar: cal)
    }

    /// Mirrors the parameter shape used by `RecallResultRowView`.
    @Test("RecallResultRowView-style call site compiles")
    func recallCallSiteShape() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("recall") },
            hostApp: nil,
            onDetail: { }
        )
        let _: ResultRowLayout<Color, Text> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }

    /// Mirrors the parameter shape used by `SessionRowView`.
    @Test("SessionRowView-style call site compiles")
    func sessionRowCallSiteShape() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("session") },
            hostApp: nil,
            accentColor: .orange,
            onDetail: { },
            isUnread: true
        )
        let _: ResultRowLayout<Color, Text> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }

    /// Mirrors the parameter shape used by `RemoteClaudeCodeRowView`.
    @Test("RemoteClaudeCodeRowView-style call site compiles")
    func remoteCallSiteShape() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("remote") },
            hostApp: nil,
            hostAppSystemSymbol: "globe",
            accentColor: nil,
            onDetail: nil
        )
        let _: ResultRowLayout<Color, Text> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }
}
