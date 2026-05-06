import Foundation

/// Registry of browsers seshctl knows how to focus an existing tab in
/// (separate from `TerminalApp` because browsers don't host shell sessions
/// and don't share TerminalApp's capabilities). Add a case here, then handle
/// the new case in `BrowserController` — every switch over `BrowserApp` is
/// exhaustive (no `default` cases).
public enum BrowserApp: String, CaseIterable, Sendable {
    case chrome
    case arc
    case safari

    // MARK: - Properties

    public var bundleId: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .arc: "company.thebrowser.Browser"
        case .safari: "com.apple.Safari"
        }
    }

    public var displayName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .arc: "Arc"
        case .safari: "Safari"
        }
    }

    /// Name used in AppleScript `tell application "<name>"` blocks.
    /// For most apps this matches the LaunchServices display name.
    public var applicationName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .arc: "Arc"
        case .safari: "Safari"
        }
    }

    // MARK: - Lookup

    public static func from(bundleId: String) -> BrowserApp? {
        allCases.first { $0.bundleId == bundleId }
    }

    public static var allBundleIds: [String] {
        allCases.map(\.bundleId)
    }
}
