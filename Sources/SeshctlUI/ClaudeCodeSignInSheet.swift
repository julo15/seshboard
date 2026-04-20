import AppKit
import Foundation
import WebKit

import SeshctlCore

/// Standalone window that hosts a `WKWebView` at `claude.ai/login` so the user
/// can authenticate. Cookies are persisted to `WKWebsiteDataStore.default()`,
/// which the `RemoteClaudeCodeFetcher` reads on each refresh.
///
/// The sheet auto-dismisses on successful sign-in detection and invokes
/// `onSuccess`. If the user closes the window without completing login (title
/// bar close button), `onCancel` fires instead. Exactly one handler is invoked
/// per presentation.
///
/// Concurrency: class is `@MainActor`; all WebKit / AppKit interaction happens
/// on the main actor. Tests for the pure success-detection helper live in
/// `Tests/SeshctlUITests/ClaudeCodeSignInSheetTests.swift`.
@MainActor
public final class ClaudeCodeSignInSheet: NSObject {
    public typealias SuccessHandler = @MainActor () -> Void
    public typealias CancelHandler = @MainActor () -> Void

    // Retain-until-dismissal registry. The window is owned by the sheet, and
    // the sheet is owned by this set so callers don't have to manage lifetime.
    private static var active: Set<ClaudeCodeSignInSheet> = []

    private let window: NSWindow
    private let webView: WKWebView
    private let urlField: NSTextField
    private let infoButton: NSButton
    private let infoPopover: NSPopover
    private var successFlash: NSTextField?
    private var onSuccess: SuccessHandler?
    private var onCancel: CancelHandler?

    /// Guards against double-invocation. Once either handler has fired, this
    /// flag is true and no further calls will be made.
    private var didInvokeHandler = false

    // MARK: - Public API

    /// Presents the sign-in window. Call from the main actor.
    /// - Parameters:
    ///   - onSuccess: invoked after a brief success flash + auto-dismiss.
    ///   - onCancel: invoked when the user closes the window without completing login.
    /// - Returns: the sheet instance; retained internally until dismissal.
    @discardableResult
    public static func present(
        onSuccess: @escaping SuccessHandler,
        onCancel: @escaping CancelHandler
    ) -> ClaudeCodeSignInSheet {
        let sheet = ClaudeCodeSignInSheet(onSuccess: onSuccess, onCancel: onCancel)
        active.insert(sheet)
        sheet.show()
        return sheet
    }

    /// Close the window programmatically. If neither handler has fired yet,
    /// treats this as a cancel; the window's own close lifecycle runs the
    /// usual cleanup.
    public func dismiss() {
        window.performClose(nil)
    }

    // MARK: - Init

    private init(
        onSuccess: @escaping SuccessHandler,
        onCancel: @escaping CancelHandler
    ) {
        self.onSuccess = onSuccess
        self.onCancel = onCancel

        let windowWidth: CGFloat = 1000
        let windowHeight: CGFloat = 800
        let noticeHeight: CGFloat = 32
        let urlBarHeight: CGFloat = 36
        let contentRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Connect to Claude Code"
        window.level = .modalPanel
        window.isReleasedWhenClosed = false
        self.window = window

        let contentView = NSView(frame: contentRect)
        contentView.autoresizesSubviews = true

        // --- Notice strip (pinned to top) ---
        let noticeStrip = NSView(frame: NSRect(
            x: 0,
            y: windowHeight - noticeHeight,
            width: windowWidth,
            height: noticeHeight
        ))
        noticeStrip.autoresizingMask = [.width, .minYMargin]
        noticeStrip.wantsLayer = true
        // Subtle background band. `secondarySystemFill` is macOS 14+, so use a
        // fixed translucent gray that reads well in both light and dark modes.
        noticeStrip.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.12).cgColor

        let infoButton = NSButton(frame: NSRect(x: 10, y: 6, width: 20, height: 20))
        infoButton.bezelStyle = .inline
        infoButton.isBordered = false
        infoButton.title = ""
        infoButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Why email sign-in")
        infoButton.imagePosition = .imageOnly
        infoButton.autoresizingMask = [.maxXMargin, .minYMargin, .maxYMargin]
        self.infoButton = infoButton

        let noticeLabel = NSTextField(labelWithString: "Use email to sign in — Google isn't supported here.")
        noticeLabel.frame = NSRect(x: 34, y: 7, width: windowWidth - 44, height: 18)
        noticeLabel.font = NSFont.systemFont(ofSize: 12)
        noticeLabel.textColor = .secondaryLabelColor
        noticeLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]

        noticeStrip.addSubview(infoButton)
        noticeStrip.addSubview(noticeLabel)

        // --- Info popover content ---
        let infoPopover = NSPopover()
        infoPopover.behavior = .transient
        let infoContent = NSViewController()
        let infoView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 120))
        let infoText = NSTextField(wrappingLabelWithString:
            "Google's \"Continue with Google\" button is blocked inside embedded " +
            "browsers. Use the email + magic-link option instead. When the " +
            "magic-link email arrives, right-click the link, choose \"Copy Link " +
            "Address\", and paste it into the URL bar above."
        )
        infoText.frame = NSRect(x: 12, y: 12, width: 316, height: 96)
        infoText.font = NSFont.systemFont(ofSize: 12)
        infoView.addSubview(infoText)
        infoContent.view = infoView
        infoPopover.contentViewController = infoContent
        self.infoPopover = infoPopover

        // --- URL bar row (pinned below notice) ---
        let urlBarRow = NSView(frame: NSRect(
            x: 0,
            y: windowHeight - noticeHeight - urlBarHeight,
            width: windowWidth,
            height: urlBarHeight
        ))
        urlBarRow.autoresizingMask = [.width, .minYMargin]

        let urlLabel = NSTextField(labelWithString: "Paste magic-link URL:")
        urlLabel.frame = NSRect(x: 10, y: 9, width: 150, height: 18)
        urlLabel.font = NSFont.systemFont(ofSize: 12)
        urlLabel.textColor = .labelColor
        urlLabel.autoresizingMask = [.maxXMargin]
        urlBarRow.addSubview(urlLabel)

        let goButtonWidth: CGFloat = 50
        let goButtonMargin: CGFloat = 10
        let urlFieldX: CGFloat = 165
        let urlFieldWidth = windowWidth - urlFieldX - goButtonWidth - goButtonMargin - goButtonMargin

        let urlField = NSTextField(frame: NSRect(
            x: urlFieldX,
            y: 7,
            width: urlFieldWidth,
            height: 22
        ))
        urlField.placeholderString = "Paste URL here — right-click the link in your email → Copy Link Address"
        urlField.font = NSFont.systemFont(ofSize: 12)
        urlField.autoresizingMask = [.width]
        self.urlField = urlField
        urlBarRow.addSubview(urlField)

        let goButton = NSButton(frame: NSRect(
            x: windowWidth - goButtonWidth - goButtonMargin,
            y: 4,
            width: goButtonWidth,
            height: 28
        ))
        goButton.title = "Go"
        goButton.bezelStyle = .rounded
        goButton.autoresizingMask = [.minXMargin]
        urlBarRow.addSubview(goButton)

        // --- WebView (fills the rest) ---
        let config = WKWebViewConfiguration()
        // Explicitly use the shared persistent data store so cookies land where
        // the fetcher can read them.
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webViewHeight = windowHeight - noticeHeight - urlBarHeight
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: windowWidth, height: webViewHeight),
            configuration: config
        )
        webView.customUserAgent = RemoteClaudeCodeFetcher.safariUserAgent
        webView.autoresizingMask = [.width, .height]
        self.webView = webView

        contentView.addSubview(webView)
        contentView.addSubview(urlBarRow)
        contentView.addSubview(noticeStrip)

        window.contentView = contentView
        window.center()

        super.init()

        // Wire up targets/delegates after super.init.
        infoButton.target = self
        infoButton.action = #selector(infoButtonClicked(_:))
        goButton.target = self
        goButton.action = #selector(goPressed)
        urlField.target = self
        urlField.action = #selector(goPressed)
        webView.navigationDelegate = self
        window.delegate = self

        // Initial load.
        if let loginURL = URL(string: "https://claude.ai/login") {
            webView.load(URLRequest(url: loginURL))
        }
    }

    // MARK: - Presentation

    private func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Actions

    @objc private func goPressed() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw) else { return }
        webView.load(URLRequest(url: url))
    }

    @objc private func infoButtonClicked(_ sender: NSButton) {
        if infoPopover.isShown {
            infoPopover.performClose(sender)
        } else {
            infoPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }

    // MARK: - Success detection helper (pure, tested)

    /// Returns `true` when the sheet should consider the user logged in.
    /// Pure function — no side effects.
    ///
    /// Two sufficient conditions:
    /// 1. URL host is `claude.ai` and path starts with `/code`.
    /// 2. Cookies scoped to `.claude.ai` include both `sessionKey` and
    ///    `sessionKeyLC`.
    ///
    /// Either alone triggers success.
    ///
    /// `nonisolated` so tests and any non-main-actor call site can use it —
    /// the function is pure, so actor isolation serves no purpose here.
    nonisolated static func shouldConsiderSignedIn(url: URL?, cookies: [HTTPCookie]) -> Bool {
        if let url = url,
           url.host == "claude.ai",
           url.path.hasPrefix("/code") {
            return true
        }

        let claudeCookies = cookies.filter { $0.domain.hasSuffix("claude.ai") }
        let hasSessionKey = claudeCookies.contains { $0.name == "sessionKey" }
        let hasSessionKeyLC = claudeCookies.contains { $0.name == "sessionKeyLC" }
        return hasSessionKey && hasSessionKeyLC
    }

    // MARK: - Success / cancel routing

    /// Invoked from `didFinish` after checking cookies. Shows the "Signed in"
    /// flash and closes the window, which in turn fires `onSuccess`.
    private func handleSignInSuccess() {
        guard !didInvokeHandler else { return }
        // Flash an overlay, then close.
        showSignedInFlash()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.fireSuccessAndClose()
        }
    }

    private func fireSuccessAndClose() {
        guard !didInvokeHandler else { return }
        didInvokeHandler = true
        let handler = onSuccess
        onSuccess = nil
        onCancel = nil
        window.orderOut(nil)
        window.close()
        Self.active.remove(self)
        handler?()
    }

    private func showSignedInFlash() {
        guard successFlash == nil, let contentView = window.contentView else { return }
        let flash = NSTextField(labelWithString: "✓ Signed in")
        flash.font = NSFont.boldSystemFont(ofSize: 18)
        flash.textColor = .white
        flash.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.9)
        flash.drawsBackground = true
        flash.isBezeled = false
        flash.isEditable = false
        flash.alignment = .center
        flash.wantsLayer = true
        flash.layer?.cornerRadius = 6
        let flashWidth: CGFloat = 140
        let flashHeight: CGFloat = 32
        let x = (contentView.bounds.width - flashWidth) / 2
        let y = (contentView.bounds.height - flashHeight) / 2
        flash.frame = NSRect(x: x, y: y, width: flashWidth, height: flashHeight)
        flash.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        contentView.addSubview(flash)
        successFlash = flash
    }
}

// MARK: - WKNavigationDelegate

extension ClaudeCodeSignInSheet: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didInvokeHandler else { return }
        let currentURL = webView.url
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            if Self.shouldConsiderSignedIn(url: currentURL, cookies: cookies) {
                self.handleSignInSuccess()
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension ClaudeCodeSignInSheet: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        // If we haven't already invoked a handler (success path), treat this
        // close as a user cancel.
        guard !didInvokeHandler else {
            Self.active.remove(self)
            return
        }
        didInvokeHandler = true
        let handler = onCancel
        onSuccess = nil
        onCancel = nil
        Self.active.remove(self)
        handler?()
    }
}
