import SwiftUI
import SeshctlCore

extension View {
    /// Scrolls to the selected session on appear and when `selectedIndex` changes.
    ///
    /// The row id scheme expected is `"\(session.id)-\(session.status.rawValue)"`,
    /// matching the `.id(...)` applied to each `SessionRowView` in the list and tree views.
    /// Indices outside `0..<ordered.count` are ignored — callers can attach their own
    /// `.onChange(of: selectedIndex)` afterwards to handle non-session selections
    /// (e.g. recall results in the list view).
    func followSelectionScroll(
        ordered: [Session],
        selectedIndex: Int,
        proxy: ScrollViewProxy
    ) -> some View {
        self
            .onAppear {
                if selectedIndex >= 0 && selectedIndex < ordered.count {
                    let session = ordered[selectedIndex]
                    proxy.scrollTo("\(session.id)-\(session.status.rawValue)", anchor: .center)
                }
            }
            .onChange(of: selectedIndex) { newIndex in
                if newIndex >= 0 && newIndex < ordered.count {
                    let session = ordered[newIndex]
                    withAnimation(.easeOut(duration: 0.02)) {
                        proxy.scrollTo("\(session.id)-\(session.status.rawValue)", anchor: .center)
                    }
                }
            }
    }
}
