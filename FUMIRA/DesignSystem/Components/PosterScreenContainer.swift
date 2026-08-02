import SwiftUI

struct PosterScreenContainer<Content: View>: View {
    var background: Color = ClayPalette.cream
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            ClayAppBackground(color: background)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    content()
                        .frame(
                            maxWidth: .infinity,
                            minHeight: max(
                                0,
                                proxy.size.height
                                    - ClaySpacing.sm * 2
                                    - proxy.safeAreaInsets.top
                                    - proxy.safeAreaInsets.bottom
                            ),
                            alignment: .top
                        )
                        .padding(.horizontal, ClaySpacing.xxl)
                        .padding(.vertical, ClaySpacing.sm)
                        .safeAreaPadding(.top)
                        .safeAreaPadding(.bottom)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
    }
}
