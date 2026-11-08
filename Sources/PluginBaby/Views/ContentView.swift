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
            VStack(alignment: .leading, spacing: 0) {
                BrandHeader()
                List(AppSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection ?? .catalog {
            case .catalog: CatalogView()
            case .chains: ChainsView()
            case .audition: AuditionView()
            case .archive: ArchiveView()
            }
        }
        .tint(Theme.accent)
    }
}

/// Electric wordmark shown at the top of the sidebar.
struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.fill")
                    .foregroundStyle(Theme.brandGradient)
                Text(Theme.wordmark)
                    .font(.system(.headline, design: .rounded)).bold()
                    .foregroundStyle(Theme.brandGradient)
            }
            Text(Theme.tagline)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
