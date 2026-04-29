import Foundation
import SwiftUI
import Testing

@testable import SeshctlUI

/// Smoke / type-level tests for `ResultRowLayout`'s additive trailing-accessory
/// slot. Per AGENTS.md, SwiftUI view bodies are coverage-exempt — these tests
/// verify that **both initializer paths** (constrained-extension default,
/// explicit `trailingAccessory:` override) compile and produce a value of the
/// expected concrete generic type.
///
/// The compiler is the primary verifier: if either init disappears or its
/// signature drifts, this file fails to build. The runtime assertions
/// (`MemoryLayout<...>.size > 0`) just confirm the constructed value exists.
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

    // MARK: - Default init (no trailing accessory)

    @Test("Constrained-extension init produces ResultRowLayout<_, _, EmptyView>")
    func defaultInitProducesEmptyViewTrailing() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("content") },
            toolName: "claude",
            hostApp: nil,
            onDetail: nil
        )

        // Compile-time witness: this assignment forces the inferred type.
        // If the constrained-extension init went away (or the default
        // `Trailing == EmptyView` constraint changed), this line fails to
        // compile rather than fail at runtime.
        let _: ResultRowLayout<Color, Text, EmptyView> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }

    @Test("Constrained-extension init accepts hostAppSystemSymbol and accentColor")
    func defaultInitWithOptionalParams() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("content") },
            toolName: "claude",
            hostApp: nil,
            hostAppSystemSymbol: "globe",
            accentColor: .blue,
            onDetail: { }
        )

        let _: ResultRowLayout<Color, Text, EmptyView> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }

    // MARK: - Explicit trailing accessory

    @Test("Explicit trailingAccessory init produces ResultRowLayout<_, _, Text>")
    func explicitAccessoryInitProducesProvidedTrailing() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("content") },
            toolName: "claude",
            hostApp: nil,
            hostAppSystemSymbol: nil,
            accentColor: nil,
            onDetail: nil,
            trailingAccessory: { Text("•") }
        )

        let _: ResultRowLayout<Color, Text, Text> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }

    @Test("Explicit EmptyView trailingAccessory still type-resolves to EmptyView")
    func explicitEmptyViewAccessory() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("content") },
            toolName: "claude",
            hostApp: nil,
            hostAppSystemSymbol: nil,
            accentColor: nil,
            onDetail: nil,
            trailingAccessory: { EmptyView() }
        )

        // Both code paths converge on the same concrete type when the
        // closure returns `EmptyView` — important so the constrained
        // extension is a true zero-cost default.
        let _: ResultRowLayout<Color, Text, EmptyView> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }

    // MARK: - Existing call-site shapes

    /// Mirrors the parameter shape used by `RecallResultRowView`. If the
    /// constrained-extension init signature drifts away from the existing
    /// callers, this fails to compile.
    @Test("RecallResultRowView-style call site compiles unchanged")
    func recallCallSiteShape() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("recall") },
            toolName: "claude",
            hostApp: nil,
            onDetail: { }
        )
        let _: ResultRowLayout<Color, Text, EmptyView> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }

    /// Mirrors the parameter shape used by `SessionRowView` (adds
    /// `accentColor:`).
    @Test("SessionRowView-style call site compiles unchanged")
    func sessionRowCallSiteShape() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("session") },
            toolName: "codex",
            hostApp: nil,
            accentColor: .orange,
            onDetail: { }
        )
        let _: ResultRowLayout<Color, Text, EmptyView> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }

    /// Mirrors the parameter shape used by `RemoteClaudeCodeRowView` (uses
    /// `hostAppSystemSymbol:` and `onDetail: nil`).
    @Test("RemoteClaudeCodeRowView-style call site compiles unchanged")
    func remoteCallSiteShape() {
        let layout = ResultRowLayout(
            status: { Color.clear },
            ageDisplay: Self.sampleAgeDisplay(),
            content: { Text("remote") },
            toolName: "claude.ai",
            hostApp: nil,
            hostAppSystemSymbol: "globe",
            accentColor: nil,
            onDetail: nil
        )
        let _: ResultRowLayout<Color, Text, EmptyView> = layout
        #expect(MemoryLayout.size(ofValue: layout) > 0)
    }
}
