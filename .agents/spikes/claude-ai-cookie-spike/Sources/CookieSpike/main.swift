import AppKit
import Darwin
import WebKit

// Force line-buffered stdout so output appears immediately when piped to a file.
setvbuf(stdout, nil, _IOLBF, 0)

@MainActor
final class Spike: NSObject, WKNavigationDelegate {
    let window: NSWindow
    let webView: WKWebView
    let urlField: NSTextField
    var apiHit = false

    override init() {
        let windowWidth: CGFloat = 1000
        let windowHeight: CGFloat = 840
        let toolbarHeight: CGFloat = 40
        let contentRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        self.window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: contentRect)

        self.urlField = NSTextField(frame: NSRect(
            x: 10,
            y: windowHeight - toolbarHeight + 9,
            width: windowWidth - 80,
            height: 22
        ))
        urlField.placeholderString = "Paste the magic-link URL here, press Enter"

        let goButton = NSButton(frame: NSRect(
            x: windowWidth - 60,
            y: windowHeight - toolbarHeight + 6,
            width: 50,
            height: 28
        ))
        goButton.title = "Go"
        goButton.bezelStyle = .rounded

        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: NSRect(
            x: 0,
            y: 0,
            width: windowWidth,
            height: windowHeight - toolbarHeight
        ), configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"

        contentView.addSubview(urlField)
        contentView.addSubview(goButton)
        contentView.addSubview(webView)
        window.contentView = contentView
        window.title = "Claude.ai Cookie Spike"
        window.center()
        window.level = .floating

        super.init()

        goButton.target = self
        goButton.action = #selector(goPressed)
        urlField.target = self
        urlField.action = #selector(goPressed)
        webView.navigationDelegate = self

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        print("→ Opened WKWebView at https://claude.ai/login")
        print("→ Use the email / magic-link path. When you get the email,")
        print("   right-click the magic link and 'Copy Link'. Paste into the URL bar,")
        print("   press Enter. Spike will detect login and hit the API.")
    }

    @objc func goPressed() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else {
            print("❌ Not a valid URL: \(raw)")
            return
        }
        print("→ Navigating to pasted URL: \(url.absoluteString)")
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        print("↪ didFinish: \(url.absoluteString)")
        guard !apiHit else { return }
        Task { @MainActor in
            await self.checkCookiesAndAPI()
        }
    }

    func checkCookiesAndAPI() async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let all = await store.allCookies()
        let claudeCookies = all.filter { $0.domain.hasSuffix("claude.ai") }

        // Heuristic: logged in when BOTH sessionKey and sessionKeyLC are present.
        guard claudeCookies.contains(where: { $0.name == "sessionKey" }),
              claudeCookies.contains(where: { $0.name == "sessionKeyLC" }) else {
            return
        }

        print("\n=== Cookies for claude.ai (n=\(claudeCookies.count)) ===")
        for c in claudeCookies.sorted(by: { $0.name < $1.name }) {
            let preview = c.value.count > 12
                ? "\(c.value.prefix(8))…(len=\(c.value.count))"
                : c.value
            let exp = c.expiresDate.map { "\($0)" } ?? "session"
            print("  \(c.name)  httpOnly=\(c.isHTTPOnly)  secure=\(c.isSecure)  expires=\(exp)  domain=\(c.domain)  value=\(preview)")
        }

        if let sessionKey = claudeCookies.first(where: { $0.name == "sessionKey" }) {
            print("\n--- sessionKey (assumption A test) ---")
            print("  isHTTPOnly: \(sessionKey.isHTTPOnly)   ← want: true (means HttpOnly is not a blocker)")
            if let exp = sessionKey.expiresDate {
                let lifetime = exp.timeIntervalSinceNow / 86_400
                print("  expiresDate: \(exp)")
                print("  measured lifetime from now: \(String(format: "%.1f", lifetime)) days")
            } else {
                print("  expiresDate: session-only (lost on browser close)")
            }
        }

        apiHit = true

        let cookieHeader = claudeCookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        var req = URLRequest(url: URL(string: "https://claude.ai/v1/code/sessions?limit=1")!)
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue("managed-agents-2026-04-01", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        req.setValue("https://claude.ai/code", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.httpShouldSetCookies = false
        sessionConfig.httpCookieAcceptPolicy = .never
        let urlSession = URLSession(configuration: sessionConfig)

        print("\n=== GET /v1/code/sessions?limit=1 (using cookies from WKWebView) ===")
        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                print("❌ Non-HTTP response")
                return
            }
            print("HTTP \(http.statusCode)")
            let preview = String(data: data.prefix(800), encoding: .utf8) ?? "<non-utf8>"
            print("Body preview:\n\(preview)")
            print("\n--- Verdict ---")
            if http.statusCode == 200 {
                print("✅ Login inside WKWebView + cookies captured from WKHTTPCookieStore + URLSession request → 200.")
                print("   Plan's auth approach is viable if this login flow (email/magic-link) is acceptable.")
            } else {
                print("❌ Non-200 (\(http.statusCode)). Cookies captured from WebView may be missing something browser-specific (TLS fingerprint, extra CF cookies set only under challenge).")
            }
        } catch {
            print("❌ Request failed: \(error)")
        }
        fflush(stdout)
        print("\n(spike exiting)")
        fflush(stdout)
        exit(0)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let spike = Spike()
    withExtendedLifetime(spike) {
        app.run()
    }
}
