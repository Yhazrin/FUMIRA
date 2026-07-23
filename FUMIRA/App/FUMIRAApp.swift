import SwiftUI

@main
struct FUMIRAApp: App {
    @State private var model = AppModel(dependencies: .runtime)

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.light)
                .task {
                    await model.prepare()
                }
                .onOpenURL { url in
                    model.handleDeepLink(url)
                }
        }
    }
}
