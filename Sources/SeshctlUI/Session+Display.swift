import Foundation
import SeshctlCore

extension Session {
    public var primaryName: String {
        gitRepoName ?? (directory as NSString).lastPathComponent
    }

    public var nonStandardDirName: String? {
        guard let repoName = gitRepoName else { return nil }
        let dirName = (directory as NSString).lastPathComponent
        return dirName != repoName ? dirName : nil
    }
}
