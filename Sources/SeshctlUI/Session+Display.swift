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

    enum AgeBucket: Int, CaseIterable {
        case today, yesterday, older
        var displayName: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .older: return "Older"
            }
        }
    }

    /// Calendar-day bucket — used to insert recency section headers in lists.
    var bucket: AgeBucket {
        if calendar.isDate(timestamp, inSameDayAs: now) { return .today }
        if calendar.isDateInYesterday(timestamp) { return .yesterday }
        return .older
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
