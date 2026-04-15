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

    var foregroundStyle: HierarchicalShapeStyle {
        if elapsedSeconds < 60 { return .primary }
        if elapsedSeconds < 3600 { return .secondary }
        if elapsedSeconds < 86400 { return .tertiary }
        return .quaternary
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
