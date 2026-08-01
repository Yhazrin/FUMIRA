import SwiftUI

struct PosterScreenContainer<Content: View>: View {
    var background: Color = PosterPalette.canvas
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            // Full-bleed fill — never leave a reserved white home-indicator band.
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
                                    - proxy.safeAreaInsets.top
                                    - proxy.safeAreaInsets.bottom
                            ),
                            alignment: .top
                        )
                        .padding(.horizontal, PosterSpacing.lg)
                        .padding(.vertical, PosterSpacing.md)
                        .safeAreaPadding(.top)
                        .safeAreaPadding(.bottom)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
    }
}
