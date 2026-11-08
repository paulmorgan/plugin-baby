import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case catalog = "Catalog"
    case chains = "Chains"
    case audition = "Audition"
    case archive = "Archive"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .catalog: return "square.grid.2x2"
        case .chains: return "link"
        case .audition: return "play.circle"
        case .archive: return "archivebox"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppSection? = .catalog

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .navigationTitle("Plugin Baby")
        } detail: {
            switch selection ?? .catalog {
            case .catalog: CatalogView()
            case .chains: ChainsView()
            case .audition: AuditionView()
            case .archive: ArchiveView()
            }
        }
    }
}
