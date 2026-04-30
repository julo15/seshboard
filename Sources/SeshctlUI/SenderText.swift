import SwiftUI

/// Layout constants for the line-1 sender column. Centralized so a future
/// width-tuning pass touches one place; the row views consume `width`
/// rather than spelling out a literal.
enum SenderColumnLayout {
    /// Fixed sender-column width (pt). Plan-documented starting point — to
    /// be tuned against real session-DB repo-name distribution post-Phase-1
    /// soak. See `.agents/plans/2026-04-29-1730-row-ui-gmail-redesign.md`
    /// (R1, "Sender column width" deferred question).
    static let width: CGFloat = 180

    /// Sender / branch font size. The column uses a monospace face, so bold
    /// alone doesn't widen glyphs the way it does in proportional faces — to
    /// mimic the "unread reads bigger" effect Gmail gets for free, bump the
    /// size 1pt on unread rows. Read rows match `.body` on macOS.
    static func textSize(isUnread: Bool) -> CGFloat {
        isUnread ? 14 : 13
    }
}

/// Renders the line-1 sender — the repo name (or directory basename when the
/// session has no git context). Worktree disambiguation lives on line 2's
/// branch slot, so this view is intentionally thin: a single monospaced
/// `Text` with stock tail truncation. The earlier two-part `repo · suffix`
/// machinery was removed when production callers stopped populating a dir
/// suffix; if a future case needs it, prefer extending `senderDisplay` to
/// return a richer type rather than reintroducing the buffered char-budget
/// truncation.
struct SenderText: View {
    /// Pre-resolved repo name (or directory basename) sourced from
    /// `Session.senderDisplay` / `RemoteClaudeCodeSession.senderDisplay`.
    let display: String
    /// When true, render at the bumped unread size (see
    /// `SenderColumnLayout.textSize(isUnread:)`). Bold weight is applied by
    /// the parent VStack — this only adjusts size.
    var isUnread: Bool = false

    var body: some View {
        Text(display)
            .font(.system(size: SenderColumnLayout.textSize(isUnread: isUnread), design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
