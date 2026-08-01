import SwiftUI

/// Compatibility wrapper — continuous time scrubbing is implemented by ``WaveTimeRail``.
struct TimeRail: View {
    let value: Double
    var chrome: WaveTimeRailChrome = .paper
    var isExternalValueDirectDriven = false
    var onDetent: (WaveTimeDetent) -> Void = { _ in }
    let onChange: (Double) -> Void

    var body: some View {
        WaveTimeRail(
            value: value,
            chrome: chrome,
            isExternalValueDirectDriven: isExternalValueDirectDriven,
            onDetent: onDetent,
            onChange: onChange
        )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var value = 0.0

        var body: some View {
            TimeRail(value: value) { value = $0 }
                .padding()
                .background(PosterPalette.canvas)
        }
    }
    return PreviewWrapper()
}
