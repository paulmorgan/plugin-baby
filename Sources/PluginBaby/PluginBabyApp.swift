import SwiftUI

@main
struct PluginBabyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 620)
                .task { await model.initialLoad() }
        }
    }
}
