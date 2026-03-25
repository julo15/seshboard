import SwiftUI
import SeshctlCore

public struct RecallResultRowView: View {
    let result: RecallResult
    let hasMatchingSession: Bool

    public init(result: RecallResult, hasMatchingSession: Bool) {
        self.result = result
        self.hasMatchingSession = hasMatchingSession
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Search icon in place of status dot
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)

            // Relative time
            Text(relativeTime)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            // Main content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Project name (last 2 path components)
                    Text(projectName)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // Score as percentage
                    Text(scoreLabel)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)

                    // Role tag
                    Text(roleTag)
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(roleColor)
                }

                // Matched text snippet
                Text(snippet)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Agent label
            Text(result.agent)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .opacity(hasMatchingSession ? 1.0 : 0.6)
    }

    /// Last 2 path components of the project path (e.g. "me/seshctl").
    private var projectName: String {
        let components = result.project
            .split(separator: "/", omittingEmptySubsequences: true)
        if components.count >= 2 {
            return "\(components[components.count - 2])/\(components[components.count - 1])"
        }
        return components.last.map(String.init) ?? result.project
    }

    private var scoreLabel: String {
        "\(Int(round(result.score * 100)))%"
    }

    private var roleTag: String {
        result.role == "user" ? "[you]" : "[bot]"
    }

    private var roleColor: Color {
        result.role == "user"
            ? Color(red: 0x9C / 255.0, green: 0x7C / 255.0, blue: 0x6B / 255.0)
            : Color(red: 0x93 / 255.0, green: 0x7C / 255.0, blue: 0xBF / 255.0)
    }

    private var snippet: String {
        let cleaned = result.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? result.text
        return String(cleaned.prefix(200))
    }

    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: result.timestamp)
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 55 { return "\(elapsed)s" }
        if elapsed < 3600 { return "\(elapsed / 60)m" }
        if elapsed < 86400 { return "\(elapsed / 3600)h" }
        return "\(elapsed / 86400)d"
    }
}
