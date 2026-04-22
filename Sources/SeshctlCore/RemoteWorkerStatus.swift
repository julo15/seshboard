import Foundation

/// The `worker_status` values we know how to interpret from the claude.ai
/// `/v1/code/sessions` response. Stored as the raw string (matching the API
/// surface) in `RemoteClaudeCodeSession.workerStatus`; use the failable
/// initializer to get a typed value and a `default` case to cover anything
/// the API returns that we haven't modelled yet.
///
/// Keep this in sync with `RemoteClaudeCodeRowView.Status` — every case here
/// needs a mapping in the row's `status(workerStatus:...)` decision table.
public enum RemoteWorkerStatus: String, CaseIterable, Sendable {
    case idle
    case running
    case waiting
    case requiresAction = "requires_action"
    case disconnected
}

/// The `connection_status` values we know how to interpret. Same pattern as
/// `RemoteWorkerStatus` — the DB column stays string-typed, this enum exists
/// for type-safe matching at the point of use.
public enum RemoteConnectionStatus: String, CaseIterable, Sendable {
    case connected
    case disconnected
}
