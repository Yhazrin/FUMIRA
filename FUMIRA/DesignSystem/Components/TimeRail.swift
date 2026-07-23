import SwiftUI

/// Compatibility wrapper — continuous time scrubbing is implemented by ``WaveTimeRail``.
struct TimeRail: View {
    let value: Double
    var chrome: WaveTimeRailChrome = .paper
    let onChange: (Double) -> Void

    var body: some View {
        WaveTimeRail(value: value, chrome: chrome, onChange: onChange)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var value = 0.0

        var body: some View {
            TimeRail(value: value) { value = $0 }
                .padding()
                .background(PosterPalette.paper)
        }
    }
    return PreviewWrapper()
}
