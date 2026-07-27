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
                            minHeight: max(
                                0,
                                proxy.size.height
                                    - PosterSpacing.md * 2
                            ),
                            alignment: .top
                        )
                        .padding(.horizontal, PosterSpacing.lg)
                        // RootView already lays utility pages inside the system
                        // safe area. Reapplying these insets here creates the
                        // large empty band above every page title.
                        .padding(.vertical, PosterSpacing.md)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}
