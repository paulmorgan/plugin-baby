import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case catalog = "Plugins"
    case chains = "Chains"
    case audition = "Audition"
    case archive = "Archive"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .catalog: return "list.bullet.rectangle"
        case .chains: return "link"
        case .audition: return "waveform"
        case .archive: return "archivebox"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                SidebarBrand()
                Divider().overlay(Theme.hairline)

                List(AppSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .font(.system(size: 13, weight: .medium))
                        .tag(section)
                }
                .scrollContentBackground(.hidden)

                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PROJECTS · TAGS")
                        .font(.system(size: 9, weight: .bold)).tracking(1.5)
                        .foregroundStyle(Theme.accentSecondary)
                    Text("& collections — coming soon")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
            .background(Theme.backgroundRaised)
            .navigationSplitViewColumnWidth(min: 200, ideal: 216)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard: DashboardView()
                case .catalog: CatalogView()
                case .chains: ChainsView()
                case .audition: AuditionView()
                case .archive: ArchiveView()
                }
            }
            .background(Theme.background)
        }
        .tint(Theme.accent)
    }
}
