import SwiftUI

/// Small orange "Unread" badge rendered inline in a row's title. Extracted
/// from `SessionRowView` and `RemoteClaudeCodeRowView` so both row types
/// render the same pill and any future style change (color, corner radius,
/// padding) lands in one place.
public struct UnreadPill: View {
    public init() {}

    public var body: some View {
        Text("Unread")
            .font(.system(.footnote, design: .monospaced, weight: .medium))
            .foregroundStyle(Theme.pillForeground)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.pillBackgroundUnread, in: RoundedRectangle(cornerRadius: 3))
    }
}
