import SwiftUI

@main
struct PluginBabyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
                .task { await model.initialLoad() }
        }
    }
}
