import SwiftUI
import AppKit
import SeshctlCore

/// SwiftUI view that lists detected editor integrations (one row per
/// `TerminalApp.allVSCodeVariants` whose `.app` is installed on this Mac)
/// and offers per-row Install / Reinstall / Update buttons
/// for the bundled seshctl extension.
///
/// Backed by `ExtensionInstaller` for survey + install. Long-running
/// subprocess calls are dispatched off the MainActor; `@State` mutations
/// always hop back via `Task { @MainActor in ... }`.
public struct IntegrationsView: View {
    private let installer: ExtensionInstaller
    private let bundleURL: URL
    private let onClose: () -> Void

    @State private var rows: [EditorIntegration] = []
    @State private var inFlight: Set<TerminalApp> = []
    @State private var lastError: [TerminalApp: String] = [:]
    @State private var expandedErrors: Set<TerminalApp> = []
    @State private var didInitialSurvey: Bool = false

    public init(installer: ExtensionInstaller, bundleURL: URL, onClose: @escaping () -> Void) {
        self.installer = installer
        self.bundleURL = bundleURL
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            content

            Divider()

            footer
        }
        .frame(minWidth: 500, idealWidth: 520, minHeight: 380, idealHeight: 420)
        .task {
            refresh()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Editor Integrations")
                .font(.headline)
            Text("Install the Seshctl companion extension into your editors. Detected editors only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty && didInitialSurvey {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows, id: \.app) { row in
                        rowView(for: row)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No supported editors detected on this Mac.\nInstall VS Code or Cursor, then reopen this window.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { onClose() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(for row: EditorIntegration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: row.appURL.path))
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.app.displayName)
                        .font(.body)
                    Text(statusLine(for: row))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if inFlight.contains(row.app) {
                    ProgressView()
                        .controlSize(.small)
                }

                actionButton(for: row)
            }

            if let message = lastError[row.app] {
                errorRow(for: row.app, message: message)
            }
        }
    }

    @ViewBuilder
    private func actionButton(for row: EditorIntegration) -> some View {
        let title = actionTitle(for: row)
        let isInFlight = inFlight.contains(row.app)
        let isDisabled = isInFlight || row.status == .cliUnavailable

        if case .outdated = row.status {
            Button(title) { runInstall(row.app) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isDisabled)
        } else {
            Button(title) { runInstall(row.app) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDisabled)
        }
    }

    @ViewBuilder
    private func errorRow(for app: TerminalApp, message: String) -> some View {
        let truncated = truncate(message, limit: 120)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(truncated)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(expandedErrors.contains(app) ? "Hide" : "Details") {
                    if expandedErrors.contains(app) {
                        expandedErrors.remove(app)
                    } else {
                        expandedErrors.insert(app)
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            if expandedErrors.contains(app) {
                ScrollView {
                    Text(message)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(maxHeight: 100)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.leading, 44) // align with text column past the 32pt icon + 12pt spacing
    }

    // MARK: - Helpers

    private func statusLine(for row: EditorIntegration) -> String {
        switch row.status {
        case .notInstalled:
            return "Not installed"
        case .installed(let v):
            return "Installed v\(v)"
        case .outdated(let installed, let bundled):
            return "Installed v\(installed) — update available (v\(bundled))"
        case .cliUnavailable:
            return "Editor CLI not found — install the 'Shell Command' helper from the Command Palette"
        }
    }

    private func actionTitle(for row: EditorIntegration) -> String {
        switch row.status {
        case .notInstalled:
            return "Install Extension"
        case .installed:
            return "Reinstall"
        case .outdated(_, let bundled):
            return "Update to v\(bundled)"
        case .cliUnavailable:
            return "Install Extension"
        }
    }

    private func refresh() {
        // Rebind locally so the detached task captures these immutable values
        // instead of `self` — keeps the closure Sendable under Swift 6.
        let installer = self.installer
        let bundleURL = self.bundleURL
        Task.detached(priority: .userInitiated) {
            let result = installer.surveyInstalledEditors(bundleURL: bundleURL)
            await MainActor.run {
                self.rows = result
                self.didInitialSurvey = true
            }
        }
    }

    private func runInstall(_ app: TerminalApp) {
        guard !inFlight.contains(app) else { return }
        inFlight.insert(app)
        lastError[app] = nil
        expandedErrors.remove(app)

        let installer = self.installer
        let bundleURL = self.bundleURL
        Task.detached(priority: .userInitiated) {
            let outcome: Result<EditorExtensionStatus, Error>
            do {
                let status = try installer.install(editor: app, bundleURL: bundleURL)
                outcome = .success(status)
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run {
                self.inFlight.remove(app)
                switch outcome {
                case .success:
                    self.lastError[app] = nil
                case .failure(let error):
                    self.lastError[app] = self.errorMessage(from: error)
                }
                self.refresh()
            }
        }
    }

    private func errorMessage(from error: Error) -> String {
        if let installError = error as? InstallError {
            switch installError {
            case .timeout:
                return "Install timed out (30s)"
            case .cliNotFound:
                return "Editor CLI not found"
            case .bundledVsixMissing:
                return "Bundled extension is missing"
            case .subprocessFailed(let stderr, let status):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Install failed (exit \(status))" : trimmed
            }
        }
        return "\(error)"
    }

    private func truncate(_ s: String, limit: Int) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count <= limit { return oneLine }
        let endIndex = oneLine.index(oneLine.startIndex, offsetBy: limit)
        return String(oneLine[..<endIndex]) + "…"
    }
}
