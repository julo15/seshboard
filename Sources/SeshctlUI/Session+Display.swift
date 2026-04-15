import Foundation
import SeshctlCore

struct SessionAgeDisplay {
    let timestamp: Date
    let now: Date
    let calendar: Calendar

    init(timestamp: Date, now: Date = Date(), calendar: Calendar = .current) {
        self.timestamp = timestamp
        self.now = now
        self.calendar = calendar
    }

    private var elapsedSeconds: Int {
        max(0, Int(now.timeIntervalSince(timestamp)))
    }

    var label: String {
        let elapsed = elapsedSeconds
        if elapsed < 55 { return "\(elapsed)s" }
        if elapsed < 3600 { return "\(elapsed / 60)m" }
        if elapsed < 86400 { return "\(elapsed / 3600)h" }
        return "\(elapsed / 86400)d"
    }

    enum AgeBucket {
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
