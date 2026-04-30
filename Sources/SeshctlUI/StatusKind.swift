import SwiftUI
import SeshctlCore

/// Unified status vocabulary shared by `SessionRowView` (local sessions) and
/// `RemoteClaudeCodeRowView` (cloud sessions). Both row types map their
/// type-specific status onto this so the animated dot, color palette, and
/// unread-pill treatments live in one place.
public enum StatusKind: Equatable, Sendable {
    /// Agent is actively working — pulsing orange.
    case working
    /// Agent is waiting on user input (permission prompt, pending action) —
    /// blinking blue.
    case waiting
    /// Healthy and idle — solid green.
    case idle
    /// Local: session ended normally. Solid gray, no animation.
    case completed
    /// Remote: worker disconnected (claude.ai can't reach it). Solid gray,
    /// no animation. Distinct from `.completed` semantically even though they
    /// render identically today.
    case offline
    /// Canceled — solid red (local only today).
    case canceled
    /// No longer authoritative — reaped local session, or auth-expired cached
    /// remote row. Dimmed gray.
    case stale
}

extension StatusKind {
    /// Dot color for this kind. Matches the palette both row types previously
    /// hardcoded independently.
    public var color: Color {
        switch self {
        case .working: return Theme.statusWorking
        case .waiting: return Theme.statusWaiting
        case .idle: return Theme.statusIdle
        case .completed, .offline: return .gray
        case .canceled: return Theme.statusCanceled
        case .stale: return Theme.statusStale
        }
    }

    /// Whether the `.working` pulse animation plays.
    public var isPulsing: Bool { self == .working }

    /// Whether the `.waiting` blink animation plays.
    public var isBlinking: Bool { self == .waiting }
}

extension SessionStatus {
    /// Local session status → shared UI vocabulary.
    public var statusKind: StatusKind {
        switch self {
        case .working: return .working
        case .waiting: return .waiting
        case .idle: return .idle
        case .completed: return .completed
        case .canceled: return .canceled
        case .stale: return .stale
        }
    }
}

/// Decision table mapping a remote session's reported worker/connection
/// status (plus auth-staleness) to a shared `StatusKind`. Lives on
/// `StatusKind` rather than the row view so tests can exercise the decision
/// without constructing a view.
extension StatusKind {
    /// Compute the shared-vocabulary status for a remote Claude Code session.
    /// `isStale` beats everything — the cached row is no longer authoritative
    /// when auth has expired.
    public static func forRemote(
        workerStatus: String,
        connectionStatus: String,
        isStale: Bool
    ) -> StatusKind {
        if isStale { return .stale }
        switch RemoteWorkerStatus(rawValue: workerStatus) {
        case .running: return .working
        case .waiting, .requiresAction: return .waiting
        case .disconnected: return .offline
        case .idle, .none: break // fall through to connection check
        }
        if connectionStatus == RemoteConnectionStatus.disconnected.rawValue {
            return .offline
        }
        return .idle
    }
}
