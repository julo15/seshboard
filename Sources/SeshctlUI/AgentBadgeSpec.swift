import SwiftUI
import SeshctlCore

/// Pure data describing the agent-kind corner badge that overlays the host
/// app icon on each row. Composed by `BadgedIcon` (see
/// `BadgedIcon.swift`) — this struct knows nothing about rendering.
///
/// The visual language is a typographic monogram (one capital letter) on a
/// solid colored circle. The letter is the disambiguator for color-blind
/// users; the color is the at-a-glance signal for everyone else.
///
/// Adding a new agent: extend `SessionTool` first, then add a case to
/// `forAgent(_:)` below. Compiler exhaustiveness will flag every other
/// switch on `SessionTool` that needs updating. This is the canonical
/// registration point for new agent badges — see plan
/// `2026-04-29-1730-row-ui-gmail-redesign.md` (Unit 3).
public struct AgentBadgeSpec: Equatable {
    public let letter: String
    public let color: Color

    public init(letter: String, color: Color) {
        self.letter = letter
        self.color = color
    }
}

extension AgentBadgeSpec {
    /// Resolves the badge spec for a local session's agent kind. Today's
    /// mapping: Claude → orange `C`, Codex → green `X`, Gemini → blue `G`.
    public static func forAgent(_ tool: SessionTool) -> AgentBadgeSpec {
        switch tool {
        case .claude: return AgentBadgeSpec(letter: "C", color: .orange)
        case .codex:  return AgentBadgeSpec(letter: "X", color: .green)
        case .gemini: return AgentBadgeSpec(letter: "G", color: .blue)
        }
    }

    /// Resolves the badge spec for a remote claude.ai session. The `model`
    /// parameter is reserved for a future split (e.g. routing a hypothetical
    /// codex-on-claude-ai or gemini-on-claude-ai session to a non-Claude
    /// badge); today every claude.ai session is a Claude session, so this
    /// always returns the Claude badge regardless of the input.
    ///
    /// Callers should pass the session's reported model identifier when
    /// available so a future routing case lands without a signature change.
    public static func forRemote(model: String) -> AgentBadgeSpec {
        // Phase 1 contract: every remote claude.ai session uses the Claude
        // badge. The `model` parameter is intentionally ignored today.
        _ = model
        return .forAgent(.claude)
    }
}
