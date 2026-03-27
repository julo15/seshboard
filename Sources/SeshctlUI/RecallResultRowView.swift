import SwiftUI
import SeshctlCore

public struct RecallResultRowView: View {
    let result: RecallResult
    let isActive: Bool
    let hostApp: HostAppInfo?
    var onDetail: (() -> Void)?

    public init(result: RecallResult, isActive: Bool = false, hostApp: HostAppInfo? = nil, onDetail: (() -> Void)? = nil) {
        self.result = result
        self.isActive = isActive
        self.hostApp = hostApp
        self.onDetail = onDetail
    }

    public var body: some View {
        ResultRowLayout(
            status: { statusIndicator },
            relativeTime: relativeTime,
            content: { mainContent },
            toolName: result.agent,
            hostApp: hostApp,
            onDetail: onDetail
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(isActive ? .green : .gray)
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(projectName)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(scoreLabel)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(roleTag)
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(roleColor)
            }

            Text(snippet)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

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
            ? Color.accentColor
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
