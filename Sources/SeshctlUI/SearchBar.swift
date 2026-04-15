import SwiftUI

struct SearchBar<Trailing: View>: View {
    let query: String
    let isActive: Bool
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            Text("/" + query)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isActive ? .primary : .secondary)
            if isActive {
                BlinkingCursor()
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }
}

struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 1, height: 16)
            .opacity(visible ? 0.8 : 0.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
