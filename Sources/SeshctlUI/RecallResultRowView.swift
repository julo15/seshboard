import SwiftUI
import SeshctlCore

public struct RecallResultRowView: View {
    let result: RecallResult
    let isActive: Bool
    let hostApp: HostAppInfo?
    var searchQuery: String?
    var onDetail: (() -> Void)?

    public init(result: RecallResult, isActive: Bool = false, hostApp: HostAppInfo? = nil, searchQuery: String? = nil, onDetail: (() -> Void)? = nil) {
        self.result = result
        self.isActive = isActive
        self.hostApp = hostApp
        self.searchQuery = searchQuery
        self.onDetail = onDetail
    }

    public var body: some View {
        ResultRowLayout(
            status: { statusIndicator },
            ageDisplay: ageDisplay,
            content: { mainContent },
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
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Text(roleTag)
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.textPrimaryDimmed)
                highlightedText(snippet, query: searchQuery, perWord: true)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimaryDimmed)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var projectName: String {
        (result.project as NSString).lastPathComponent
    }

    private var scoreLabel: String {
        "\(Int(round(result.score * 100)))%"
    }

    private var roleTag: String {
        result.role == "user" ? "[you]" : "[bot]"
    }

    private var snippet: String {
        let cleaned = result.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? result.text
        return String(cleaned.prefix(200))
    }

    private var ageDisplay: SessionAgeDisplay {
        SessionAgeDisplay(timestamp: Date(timeIntervalSince1970: result.timestamp))
    }
}
