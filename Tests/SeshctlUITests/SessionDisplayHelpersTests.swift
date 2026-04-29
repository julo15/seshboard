import AppKit
import Foundation
import Testing

@testable import SeshctlCore
@testable import SeshctlUI

private func makeSession(
    directory: String = "/tmp",
    gitRepoName: String? = nil,
    gitBranch: String? = nil,
    lastAsk: String? = nil,
    lastReply: String? = nil,
    status: SessionStatus = .idle,
    tool: SessionTool = .claude
) -> Session {
    Session(
        id: UUID().uuidString,
        conversationId: nil,
        tool: tool,
        directory: directory,
        launchDirectory: nil,
        hostWorkspaceFolder: nil,
        lastAsk: lastAsk,
        lastReply: lastReply,
        status: status,
        pid: nil,
        hostAppBundleId: nil,
        hostAppName: nil,
        windowId: nil,
        transcriptPath: nil,
        gitRepoName: gitRepoName,
        gitBranch: gitBranch,
        launchArgs: nil,
        startedAt: Date(),
        updatedAt: Date(),
        lastReadAt: nil
    )
}

// MARK: - senderDisplay

@Suite("Session.senderDisplay")
struct SessionSenderDisplayTests {

    @Test("Repo and dir basename match → repoPart=repo, dirSuffix=nil")
    func repoAndDirMatch() {
        let s = makeSession(
            directory: "/Users/julianlo/Documents/me/seshctl",
            gitRepoName: "seshctl"
        )
        #expect(s.senderDisplay == SenderDisplay(repoPart: "seshctl", dirSuffix: nil))
    }

    @Test("Worktree (dir basename differs) → repoPart=repo, dirSuffix=dir basename")
    func worktreeDifferentDir() {
        let s = makeSession(
            directory: "/Users/julianlo/Documents/me/seshctl-wt2",
            gitRepoName: "seshctl"
        )
        #expect(s.senderDisplay == SenderDisplay(repoPart: "seshctl", dirSuffix: "seshctl-wt2"))
    }

    @Test("Worktree collision (two sessions, same dir basename) — both get the same SenderDisplay; line 2 disambiguates")
    func worktreeCollision() {
        let a = makeSession(directory: "/work/a/tmp", gitRepoName: "seshctl")
        let b = makeSession(directory: "/work/b/tmp", gitRepoName: "seshctl")
        let expected = SenderDisplay(repoPart: "seshctl", dirSuffix: "tmp")
        #expect(a.senderDisplay == expected)
        #expect(b.senderDisplay == expected)
    }

    @Test("No git context (gitRepoName nil) → repoPart=dir basename, dirSuffix=nil")
    func noGitContext() {
        let s = makeSession(directory: "/Users/julianlo/scratch/foo", gitRepoName: nil)
        #expect(s.senderDisplay == SenderDisplay(repoPart: "foo", dirSuffix: nil))
    }
}

// MARK: - previewContent priority chain

@Suite("Session.previewContent")
struct SessionPreviewContentTests {

    @Test("Reply present → .reply(text), regardless of lastAsk")
    func replyWinsOverAsk() {
        let s = makeSession(
            lastAsk: "ignored prompt",
            lastReply: "hello",
            status: .working
        )
        #expect(s.previewContent == .reply("hello"))
    }

    @Test("Ask present, no reply → .userPrompt(text)")
    func askWhenNoReply() {
        let s = makeSession(
            lastAsk: "refactor X",
            lastReply: nil,
            status: .idle
        )
        #expect(s.previewContent == .userPrompt("refactor X"))
    }

    @Test("Both nil → .statusHint for the session's status (.working → \"Working…\")")
    func bothNilFallsBackToStatusHint() {
        let s = makeSession(lastAsk: nil, lastReply: nil, status: .working)
        #expect(s.previewContent == .statusHint("Working\u{2026}"))
    }

    @Test("Empty-string lastReply with non-empty lastAsk → .userPrompt")
    func emptyReplyFallsThroughToAsk() {
        let s = makeSession(
            lastAsk: "refactor X",
            lastReply: "",
            status: .idle
        )
        #expect(s.previewContent == .userPrompt("refactor X"))
    }

    @Test("Both empty strings → .statusHint")
    func bothEmptyStringsFallThroughToStatusHint() {
        let s = makeSession(lastAsk: "", lastReply: "", status: .idle)
        #expect(s.previewContent == .statusHint("Idle"))
    }

    @Test("Whitespace-only lastReply falls through to lastAsk")
    func whitespaceReplyFallsThrough() {
        let s = makeSession(
            lastAsk: "refactor X",
            lastReply: "   ",
            status: .idle
        )
        #expect(s.previewContent == .userPrompt("refactor X"))
    }

    @Test("Multiline reply — extracts first non-empty line")
    func multilineReplyTakesFirstNonEmptyLine() {
        let s = makeSession(
            lastReply: "\n\n  first real line  \nsecond line",
            status: .idle
        )
        #expect(s.previewContent == .reply("first real line"))
    }
}

// MARK: - statusHint

@Suite("Session.statusHint(for:)")
struct SessionStatusHintTests {

    @Test(".working → \"Working…\"")
    func working() {
        #expect(Session.statusHint(for: .working) == "Working\u{2026}")
    }

    @Test(".waiting → \"Waiting…\"")
    func waiting() {
        #expect(Session.statusHint(for: .waiting) == "Waiting\u{2026}")
    }

    @Test(".idle → \"Idle\"")
    func idle() {
        #expect(Session.statusHint(for: .idle) == "Idle")
    }

    @Test(".completed → \"Done\"")
    func completed() {
        #expect(Session.statusHint(for: .completed) == "Done")
    }

    @Test(".canceled → \"Canceled\"")
    func canceled() {
        #expect(Session.statusHint(for: .canceled) == "Canceled")
    }

    @Test(".stale → \"Ended\"")
    func stale() {
        #expect(Session.statusHint(for: .stale) == "Ended")
    }
}

// MARK: - accessibilityLabel

@Suite("Session.accessibilityLabel(hostApp:agent:)")
struct SessionAccessibilityLabelTests {

    private func makeHostApp(name: String) -> HostAppInfo {
        HostAppInfo(bundleId: "test.bundle", name: name, icon: NSImage())
    }

    @Test("Local — Ghostty + claude → \"Ghostty, Claude\"")
    func localGhosttyClaude() {
        let host = makeHostApp(name: "Ghostty")
        #expect(Session.accessibilityLabel(hostApp: host, agent: .claude) == "Ghostty, Claude")
    }

    @Test("Remote — nil hostApp + claude → \"Globe, Claude\"")
    func remoteNilClaude() {
        #expect(Session.accessibilityLabel(hostApp: nil, agent: .claude) == "Globe, Claude")
    }

    @Test("Local — Terminal + codex → \"Terminal, Codex\"")
    func localTerminalCodex() {
        let host = makeHostApp(name: "Terminal")
        #expect(Session.accessibilityLabel(hostApp: host, agent: .codex) == "Terminal, Codex")
    }

    @Test("Local — Ghostty + gemini → \"Ghostty, Gemini\"")
    func localGhosttyGemini() {
        let host = makeHostApp(name: "Ghostty")
        #expect(Session.accessibilityLabel(hostApp: host, agent: .gemini) == "Ghostty, Gemini")
    }
}
