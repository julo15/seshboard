import Foundation
import Testing

@testable import SeshctlUI


/// Char-budget tests for `chooseTruncation`. The pure helper is fully
/// deterministic and table-testable; the measurement adapter
/// (`widthBudgetToCharBudget`) is environmental and not tested here.
@Suite("SenderText.chooseTruncation")
struct SenderTextTests {
    // MARK: - Happy paths

    @Test("Short string with no suffix fits comfortably and is returned unchanged")
    func happyPathNoSuffixFits() {
        let result = chooseTruncation(
            repoPart: "seshctl",
            dirSuffix: nil,
            repoBudgetChars: 20,
            suffixBudgetChars: 0
        )
        #expect(result == TruncationResult(displayedRepo: "seshctl", displayedSuffix: nil))
    }

    @Test("Repo + suffix that fits in combined budget is returned unchanged")
    func happyPathWithSuffixFits() {
        let result = chooseTruncation(
            repoPart: "seshctl",
            dirSuffix: "wt2",
            repoBudgetChars: 10,
            suffixBudgetChars: 10
        )
        #expect(result == TruncationResult(displayedRepo: "seshctl", displayedSuffix: "wt2"))
    }

    // MARK: - Tail-truncate (no suffix)

    @Test("No suffix and repo overflows → tail ellipsis on repo")
    func tailTruncateWhenNoSuffix() {
        let result = chooseTruncation(
            repoPart: "compound-engineering",
            dirSuffix: nil,
            repoBudgetChars: 10,
            suffixBudgetChars: 0
        )
        // Budget 10 → keep 9 chars + "…"
        #expect(result == TruncationResult(displayedRepo: "compound-…", displayedSuffix: nil))
    }

    @Test("No suffix, budget 1 → repo collapses to a single ellipsis")
    func tailTruncateBudgetOne() {
        let result = chooseTruncation(
            repoPart: "longname",
            dirSuffix: nil,
            repoBudgetChars: 1,
            suffixBudgetChars: 0
        )
        #expect(result == TruncationResult(displayedRepo: "…", displayedSuffix: nil))
    }

    // MARK: - Middle-ellipsis preserving suffix

    @Test("Repo overflows but suffix fits → middle-ellipsis repo, preserve suffix in full")
    func middleEllipsisPreservingSuffix() {
        // Total = 30. Natural = 20 + 3 + 14 = 37. Suffix fits in suffixBudget.
        // effective_repo_budget = 30 - (14 + 3) = 13.
        // Middle-ellipsize "compound-engineering" (20) to 13:
        //   interior = 12, head = 6, tail = 6 → "compou" + "…" + "eering"
        let result = chooseTruncation(
            repoPart: "compound-engineering",
            dirSuffix: "wt-feature-foo",
            repoBudgetChars: 13,
            suffixBudgetChars: 17
        )
        #expect(result == TruncationResult(
            displayedRepo: "compou…eering",
            displayedSuffix: "wt-feature-foo"
        ))
    }

    @Test("Short suffix gives back budget to repo, which still middle-ellipsizes")
    func middleEllipsisReclaimsSuffixBudget() {
        // Repo 20, suffix 3. Total budget = 30. Natural = 20 + 3 + 3 = 26.
        // 26 <= 30 → fits comfortably (no truncation).
        let result = chooseTruncation(
            repoPart: "compound-engineering",
            dirSuffix: "wt2",
            repoBudgetChars: 13,
            suffixBudgetChars: 17
        )
        #expect(result == TruncationResult(
            displayedRepo: "compound-engineering",
            displayedSuffix: "wt2"
        ))
    }

    // MARK: - Suffix-only fallback (degenerate)

    @Test("Suffix exceeds its budget → repo collapses to … and suffix tail-truncates")
    func suffixOnlyFallback() {
        // suffix.count = 33 > suffixBudget = 10 → degenerate.
        // total = 20, prefixCost = 4 → suffixRoom = 16.
        // tail-truncate suffix to 16: 15 chars + "…"
        let result = chooseTruncation(
            repoPart: "seshctl",
            dirSuffix: "this-is-a-very-long-worktree-name",
            repoBudgetChars: 10,
            suffixBudgetChars: 10
        )
        #expect(result == TruncationResult(
            displayedRepo: "…",
            displayedSuffix: "this-is-a-very-…"
        ))
    }

    @Test("Suffix exceeds budget and total budget too small for repo placeholder → drop repo")
    func suffixOnlyDropRepo() {
        // suffix.count = 5 > suffixBudget = 1 → degenerate.
        // total = 2, prefixCost = 4 → totalBudget !> prefixCost → drop repo.
        // suffix gets total budget = 2 → "…" since 5 > 2 and budget 2 > 1.
        let result = chooseTruncation(
            repoPart: "abc",
            dirSuffix: "fffff",
            repoBudgetChars: 1,
            suffixBudgetChars: 1
        )
        // tail-truncate "fffff" to budget 2 → keep 1 + "…" = "f…"
        #expect(result == TruncationResult(
            displayedRepo: "",
            displayedSuffix: "f…"
        ))
    }

    // MARK: - Edge cases — narrow / zero / exact

    @Test("Exactly fits — total counts equal budget → no ellipsis")
    func exactlyFits() {
        // Natural = 3 + 3 + 1 = 7. Total budget = 7.
        let result = chooseTruncation(
            repoPart: "abc",
            dirSuffix: "d",
            repoBudgetChars: 3,
            suffixBudgetChars: 4
        )
        #expect(result == TruncationResult(displayedRepo: "abc", displayedSuffix: "d"))
    }

    @Test("Exactly fits with no suffix — repo length equals total budget → no ellipsis")
    func exactlyFitsNoSuffix() {
        let result = chooseTruncation(
            repoPart: "abcdef",
            dirSuffix: nil,
            repoBudgetChars: 6,
            suffixBudgetChars: 0
        )
        #expect(result == TruncationResult(displayedRepo: "abcdef", displayedSuffix: nil))
    }

    @Test("Both budgets zero with non-empty repo → empty without crash")
    func zeroBudgetsNonEmptyInput() {
        let result = chooseTruncation(
            repoPart: "abc",
            dirSuffix: nil,
            repoBudgetChars: 0,
            suffixBudgetChars: 0
        )
        #expect(result == TruncationResult(displayedRepo: "", displayedSuffix: nil))
    }

    @Test("Negative budgets are clamped to zero → empty without crash")
    func negativeBudgetsClamp() {
        let result = chooseTruncation(
            repoPart: "abc",
            dirSuffix: "d",
            repoBudgetChars: -5,
            suffixBudgetChars: -5
        )
        // suffix.count=1 > suffixBudget=0 → degenerate path. prefixCost=4
        // totalBudget=0, not > 4 → drop repo. suffix gets budget 0 → "".
        #expect(result == TruncationResult(displayedRepo: "", displayedSuffix: ""))
    }

    // MARK: - Empty inputs

    @Test("Empty repo and nil suffix → empty result without crash")
    func emptyRepoNilSuffix() {
        let result = chooseTruncation(
            repoPart: "",
            dirSuffix: nil,
            repoBudgetChars: 10,
            suffixBudgetChars: 10
        )
        #expect(result == TruncationResult(displayedRepo: "", displayedSuffix: nil))
    }

    @Test("Empty repo and empty suffix string → suffix normalized to nil, empty result")
    func emptyRepoEmptySuffix() {
        let result = chooseTruncation(
            repoPart: "",
            dirSuffix: "",
            repoBudgetChars: 10,
            suffixBudgetChars: 10
        )
        #expect(result == TruncationResult(displayedRepo: "", displayedSuffix: nil))
    }

    @Test("Empty suffix string with non-empty repo → suffix normalized to nil")
    func emptySuffixNormalizes() {
        // With dirSuffix="" treated as nil, and repo fitting in totalBudget=20, this is
        // a happy-path no-suffix case.
        let result = chooseTruncation(
            repoPart: "seshctl",
            dirSuffix: "",
            repoBudgetChars: 10,
            suffixBudgetChars: 10
        )
        #expect(result == TruncationResult(displayedRepo: "seshctl", displayedSuffix: nil))
    }

    // MARK: - Char-budget edge — zero on one side

    @Test("Zero repo budget but suffix fits in suffix budget → middle-ellipsizes repo to leftover")
    func zeroRepoBudgetSuffixFits() {
        // total = 5, natural = 3 + 3 + 1 = 7. suffix.count=1 <= 5 → not degenerate.
        // effective_repo_budget = 5 - (1 + 3) = 1. middle-ellipsize "abc" to 1 → "…".
        let result = chooseTruncation(
            repoPart: "abc",
            dirSuffix: "d",
            repoBudgetChars: 0,
            suffixBudgetChars: 5
        )
        #expect(result == TruncationResult(displayedRepo: "…", displayedSuffix: "d"))
    }

    @Test("Zero suffix budget with short suffix → degenerate path drops repo and tail-truncates suffix")
    func zeroSuffixBudgetShortSuffix() {
        // suffix.count=2 > suffixBudget=0 → degenerate. total=10, prefixCost=4,
        // 10 > 4 → suffixRoom=6. tail-truncate "wt" (2) to 6 → "wt" (fits).
        let result = chooseTruncation(
            repoPart: "seshctl",
            dirSuffix: "wt",
            repoBudgetChars: 10,
            suffixBudgetChars: 0
        )
        #expect(result == TruncationResult(displayedRepo: "…", displayedSuffix: "wt"))
    }
}
