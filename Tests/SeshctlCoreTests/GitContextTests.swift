import Foundation
import Testing

@testable import SeshctlCore

@Suite("GitContext.parseRepoName")
struct GitContextTests {
    @Test("HTTPS URL with .git suffix")
    func httpsWithGitSuffix() {
        let result = GitContext.parseRepoName(from: "https://github.com/user/seshctl.git")
        #expect(result == "seshctl")
    }

    @Test("HTTPS URL without .git suffix")
    func httpsWithoutGitSuffix() {
        let result = GitContext.parseRepoName(from: "https://github.com/user/seshctl")
        #expect(result == "seshctl")
    }

    @Test("SSH URL with .git suffix")
    func sshWithGitSuffix() {
        let result = GitContext.parseRepoName(from: "git@github.com:user/seshctl.git")
        #expect(result == "seshctl")
    }

    @Test("SSH URL without .git suffix")
    func sshWithoutGitSuffix() {
        let result = GitContext.parseRepoName(from: "git@github.com:user/seshctl")
        #expect(result == "seshctl")
    }

    @Test("Empty string returns nil")
    func emptyString() {
        let result = GitContext.parseRepoName(from: "")
        #expect(result == nil)
    }

    @Test("URL with trailing whitespace and newline is trimmed")
    func trailingWhitespace() {
        let result = GitContext.parseRepoName(from: "https://github.com/user/seshctl.git \n")
        #expect(result == "seshctl")
    }
}
