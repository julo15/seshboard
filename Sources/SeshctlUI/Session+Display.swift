import Foundation
import SwiftUI
import SeshctlCore

struct SessionAgeDisplay {
    let timestamp: Date
    var now: Date = Date()
    var calendar: Calendar = .current

    private var elapsedSeconds: Int {
        max(0, Int(now.timeIntervalSince(timestamp)))
    }

    var label: String {
        let e = elapsedSeconds
        if e < 55 { return "\(e)s" }
        if e < 3600 { return "\(e / 60)m" }
        if e < 86400 { return "\(e / 3600)h" }
        return "\(e / 86400)d"
    }

    /// Numeric dim factor applied uniformly to the timestamp text and the
    /// status indicator. Bucketed by calendar day (not elapsed time) — today,
    /// yesterday, older.
    var opacity: Double {
        if calendar.isDate(timestamp, inSameDayAs: now) { return 1.0 }
        if calendar.isDateInYesterday(timestamp) { return 0.7 }
        return 0.45
    }
}

extension Session {
    var primaryName: String {
        gitRepoName ?? (directory as NSString).lastPathComponent
    }

    var nonStandardDirName: String? {
        guard let repoName = gitRepoName else { return nil }
        let dirName = (directory as NSString).lastPathComponent
        return dirName != repoName ? dirName : nil
    }
}
