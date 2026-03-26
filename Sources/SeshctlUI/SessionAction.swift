import AppKit
import Foundation
import SeshctlCore

/// Represents what the user wants to act on.
public enum SessionActionTarget {
    /// An active session (has a live process) — focus its terminal tab.
    case activeSession(Session)
    /// An inactive session (completed/canceled/stale) — resume it.
    case inactiveSession(Session)
    /// A recall search result, optionally linked to a matched session for focusing or host app resolution.
    case recallResult(RecallResult, matchedSession: Session? = nil)
}

/// CANONICAL ENTRY POINT — all session focus/resume actions MUST go through this type.
/// Do not create parallel code paths in AppDelegate, views, or elsewhere.
public enum SessionAction {

    /// Execute the appropriate action for the given target.
    /// - Parameters:
    ///   - target: What to act on
    ///   - markRead: Closure to mark a session as read (e.g., viewModel.markSessionRead)
    ///   - rememberFocused: Closure to remember the focused session (e.g., viewModel.rememberFocusedSession)
    ///   - dismiss: Closure to dismiss the panel
    public static func execute(
        target: SessionActionTarget,
        markRead: (Session) -> Void,
        rememberFocused: (Session) -> Void,
        dismiss: () -> Void,
        environment: SystemEnvironment? = nil
    ) {
        switch target {
        case .activeSession(let session):
            focusActiveSession(session, markRead: markRead, rememberFocused: rememberFocused, dismiss: dismiss, environment: environment)

        case .inactiveSession(let session):
            resumeInactiveSession(session, markRead: markRead, dismiss: dismiss, environment: environment)

        case .recallResult(let result, let matchedSession):
            handleRecallResult(result, matchedSession: matchedSession, markRead: markRead, rememberFocused: rememberFocused, dismiss: dismiss, environment: environment)
        }
    }

    // MARK: - Private

    private static func focusActiveSession(
        _ session: Session,
        markRead: (Session) -> Void,
        rememberFocused: (Session) -> Void,
        dismiss: () -> Void,
        environment: SystemEnvironment? = nil
    ) {
        markRead(session)
        rememberFocused(session)
        // Hide the panel first to avoid resignKey() racing with app activation,
        // which can cause a focus flicker (target app activates → panel loses key
        // → macOS briefly refocuses another window).
        dismiss()
        if let pid = session.pid {
            TerminalController.focus(pid: pid, directory: session.directory, environment: environment)
        }
    }

    private static func resumeInactiveSession(
        _ session: Session,
        markRead: (Session) -> Void,
        dismiss: () -> Void,
        environment: SystemEnvironment? = nil
    ) {
        markRead(session)
        let command = TerminalController.buildResumeCommand(session: session)
        let bundleId = TerminalController.resolveAppBundleId(session: session, environment: environment)

        if let command, TerminalController.resume(command: command, directory: session.directory, bundleId: bundleId, environment: environment) {
            dismiss()
        } else if let command {
            // Resume dispatch failed — copy command to clipboard as fallback
            copyToClipboard(command)
            dismiss()
        } else if session.pid != nil {
            // No resume command (no conversationId) but session has a PID — try focusing
            focusActiveSession(session, markRead: { _ in }, rememberFocused: { _ in }, dismiss: dismiss, environment: environment)
        }
    }

    private static func handleRecallResult(
        _ result: RecallResult,
        matchedSession: Session?,
        markRead: (Session) -> Void,
        rememberFocused: (Session) -> Void,
        dismiss: () -> Void,
        environment: SystemEnvironment? = nil
    ) {
        // If recall result matches an active session, focus it directly
        if let session = matchedSession, session.isActive {
            focusActiveSession(session, markRead: markRead, rememberFocused: rememberFocused, dismiss: dismiss, environment: environment)
            return
        }

        // Resolve the target app: prefer the matched session's host app, fall back to frontmost terminal
        let bundleId: String?
        if let session = matchedSession {
            bundleId = TerminalController.resolveAppBundleId(session: session, environment: environment)
        } else {
            bundleId = TerminalController.detectFrontmostTerminal(environment: environment)
        }

        if FileManager.default.fileExists(atPath: result.project),
           TerminalController.resume(command: result.resumeCmd, directory: result.project, bundleId: bundleId, environment: environment) {
            dismiss()
        } else {
            copyToClipboard(result.resumeCmd)
            dismiss()
        }
    }

    private static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
