import Foundation
import SwiftUI
import SeshctlCore

struct SessionAgeDisplay {
    let elapsedSeconds: Int

    var label: String {
        if elapsedSeconds < 55 { return "\(elapsedSeconds)s" }
        if elapsedSeconds < 3600 { return "\(elapsedSeconds / 60)m" }
        if elapsedSeconds < 86400 { return "\(elapsedSeconds / 3600)h" }
        return "\(elapsedSeconds / 86400)d"
    }

    /// Numeric dim factor applied uniformly to the timestamp text and the status
    /// indicator. A compressed gradient — older rows recede without disappearing.
    var opacity: Double {
        if elapsedSeconds < 60 { return 1.0 }
        if elapsedSeconds < 3600 { return 0.85 }
        if elapsedSeconds < 86400 { return 0.7 }
        return 0.55
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
