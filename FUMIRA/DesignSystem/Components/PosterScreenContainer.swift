import SwiftUI

struct PosterScreenContainer<Content: View>: View {
    var background: Color = PosterPalette.canvas
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            GeometryReader { proxy in
                ScrollView {
                    content()
                        .frame(
                            maxWidth: .infinity,
                            minHeight: max(0, proxy.size.height - PosterSpacing.md * 2)
                        )
                        .padding(.horizontal, PosterSpacing.lg)
                        .padding(.vertical, PosterSpacing.md)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}
