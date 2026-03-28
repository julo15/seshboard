import Foundation

/// Single source of truth for all known terminal and editor apps.
public enum TerminalApp: String, CaseIterable, Sendable {
    case terminal
    case iterm2
    case warp
    case ghostty
    case vscode
    case vscodeInsiders
    case cursor

    // MARK: - Properties

    public var bundleId: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm2: "com.googlecode.iterm2"
        case .warp: "dev.warp.Warp-Stable"
        case .ghostty: "com.mitchellh.ghostty"
        case .vscode: "com.microsoft.VSCode"
        case .vscodeInsiders: "com.microsoft.VSCodeInsiders"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        }
    }

    public var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm2: "iTerm2"
        case .warp: "Warp"
        case .ghostty: "Ghostty"
        case .vscode: "VS Code"
        case .vscodeInsiders: "VS Code Insiders"
        case .cursor: "Cursor"
        }
    }

    public var uriScheme: String? {
        switch self {
        case .terminal, .iterm2, .warp, .ghostty: nil
        case .vscode: "vscode"
        case .vscodeInsiders: "vscode-insiders"
        case .cursor: "cursor"
        }
    }

    // MARK: - Capabilities

    public var supportsTTYFocus: Bool {
        switch self {
        case .terminal, .iterm2, .ghostty: true
        case .warp, .vscode, .vscodeInsiders, .cursor: false
        }
    }

    public var supportsAppleScriptResume: Bool {
        switch self {
        case .terminal, .iterm2, .ghostty: true
        case .warp, .vscode, .vscodeInsiders, .cursor: false
        }
    }

    public var supportsURIHandler: Bool {
        switch self {
        case .vscode, .vscodeInsiders, .cursor: true
        case .terminal, .iterm2, .warp, .ghostty: false
        }
    }

    // MARK: - Lookup

    public static func from(bundleId: String) -> TerminalApp? {
        allCases.first { $0.bundleId == bundleId }
    }

    // MARK: - Collections

    public static let allTerminals: [TerminalApp] = [.terminal, .iterm2, .warp, .ghostty]

    public static let allVSCodeVariants: [TerminalApp] = [.vscode, .vscodeInsiders, .cursor]

    public static var allBundleIds: [String] {
        allCases.map(\.bundleId)
    }
}
