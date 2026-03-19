import Foundation
import SeshctlCore

@MainActor
public final class NavigationState: ObservableObject {
    public enum Screen: Equatable {
        case list
        case detail

        public static func == (lhs: Screen, rhs: Screen) -> Bool {
            switch (lhs, rhs) {
            case (.list, .list): return true
            case (.detail, .detail): return true
            default: return false
            }
        }
    }

    @Published public var screen: Screen = .list
    @Published public private(set) var detailViewModel: SessionDetailViewModel?

    public init() {}

    public func openDetail(for session: Session) {
        let vm = SessionDetailViewModel(session: session)
        detailViewModel = vm
        screen = .detail
        vm.load()
    }

    public func backToList() {
        screen = .list
        detailViewModel = nil
    }
}
