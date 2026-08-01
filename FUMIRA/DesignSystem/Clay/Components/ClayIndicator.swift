import SwiftUI

/// Clay indicator dot — status light with highlight and shadow.
struct ClayIndicator: View {
    let color: Color

    init(_ color: Color = ClayPalette.orange) {
        self.color = color
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.40))
                    .frame(width: 7, height: 7)
                    .padding(3)
            }
            .shadow(
                color: ClayShadow.small.color,
                radius: ClayShadow.small.radius,
                x: ClayShadow.small.x,
                y: ClayShadow.small.y
            )
    }
}
