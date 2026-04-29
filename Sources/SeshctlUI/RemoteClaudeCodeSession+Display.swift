import Foundation
import SeshctlCore

// MARK: - Remote (claude.ai) display helpers
//
// Mirrors the local-side helpers in `Session+Display.swift`. The view layer
// composes these into the same `SenderDisplay` / `PreviewContent` shapes so
// remote and local rows can share the same row template (Phase 1 of the
// Gmail-style row layout).

extension RemoteClaudeCodeSession {
    /// Two-part sender for the row's line-1 sender slot. Sourced from
    /// `repoUrl` via `DisplayRow.repoShortName(from:)`. Falls back to the
    /// literal `"Remote"` when no repo URL is attached. Remote rows have no
    /// per-session directory, so `dirSuffix` is always nil.
    var senderDisplay: SenderDisplay {
        if let repo = DisplayRow.repoShortName(from: repoUrl) {
            return SenderDisplay(repoPart: repo, dirSuffix: nil)
        }
        return SenderDisplay(repoPart: "Remote", dirSuffix: nil)
    }

    /// Preview content for the row's line-1 preview slot. Remote sessions
    /// have no `lastReply` / `lastAsk` priority chain — the title is the only
    /// content surface — so this always returns `.reply(title)`.
    var previewContent: PreviewContent {
        .reply(title)
    }

    /// First branch in the `branches` array, or `nil` when the array is
    /// empty. The view layer uses `nil` as the signal to collapse line 2 on
    /// remote rows.
    var branchDisplay: String? {
        branches.first
    }
}
