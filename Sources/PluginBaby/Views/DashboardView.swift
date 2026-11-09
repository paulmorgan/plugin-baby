import SwiftUI

/// The home screen: summary stat tiles, recently-added plugins, and the detail panel for the selected plugin.
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 12)]

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                statTiles
                toolbar(model: model)
                Divider().overlay(Theme.hairline)
                grid
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            DetailPanel()
        }
        .background(Theme.background)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PLUGIN BABY")
                    .font(.system(size: 10, weight: .bold)).tracking(2)
                    .foregroundStyle(Theme.accent)
                Text("Welcome back")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Text("Plugin Baby \(appVersion)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "v\(v ?? "0.1")"
    }

    // MARK: Stat tiles

    private var statTiles: some View {
        HStack(spacing: 12) {
            StatTile(
                label: "My Plugins",
                value: "\(model.plugins.count)",
                note: model.issueCount > 0 ? "\(model.issueCount) issues" : nil,
                noteColor: Theme.accentSecondary,
                systemImage: "square.stack.3d.up.fill")
            StatTile(
                label: "Recently Added",
                value: "\(model.recentlyAddedCount)",
                note: "last 30 days",
                noteColor: Theme.textSecondary,
                systemImage: "clock.arrow.circlepath")
            StatTile(
                label: "Manufacturers",
                value: "\(model.manufacturersCount)",
                systemImage: "building.2.fill")
            StatTile(
                label: "Health",
                value: "\(model.plugins.count - model.healthIssueCount)/\(model.plugins.count)",
                note: model.healthIssueCount > 0 ? "\(model.healthIssueCount) warnings" : "all clear",
                noteColor: model.healthIssueCount > 0 ? Color(red: 1.0, green: 0.72, blue: 0.2)
                                                      : Color(red: 0.3, green: 0.9, blue: 0.55),
                systemImage: "heart.text.square.fill")
        }
    }

    // MARK: Toolbar

    private func toolbar(model: AppModel) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search plugins…", text: Binding(
                    get: { model.searchText }, set: { model.searchText = $0 }))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.4)))

            Menu {
                Button("All formats") { model.formatFilter = nil }
                Divider()
                ForEach(PluginFormat.allCases) { fmt in
                    Button(fmt.rawValue) { model.formatFilter = fmt }
                }
            } label: {
                Label(model.formatFilter?.rawValue ?? "Filters", systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.borderlessButton).fixedSize()

            Menu {
                ForEach(PluginSort.allCases) { s in
                    Button(s.rawValue) { model.sort = s }
                }
            } label: {
                Label(model.sort.rawValue, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton).fixedSize()

            Spacer()

            if model.isScanning || model.isValidatingAll {
                ProgressView().controlSize(.small)
            }
            Text(model.lastScanDescription)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            Button { Task { await model.rescan() } } label: {
                Label("Scan", systemImage: "arrow.clockwise")
            }
            Button { model.validateAllAUs() } label: {
                Label("Validate all", systemImage: "checkmark.seal")
            }
            .disabled(model.isValidatingAll)
        }
    }

    // MARK: Grid

    private var grid: some View {
        Group {
            if model.plugins.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.filteredPlugins) { plugin in
                            PluginCard(
                                plugin: plugin,
                                selected: plugin.id == model.selectedPluginID,
                                onSelect: { model.selectedPluginID = plugin.id })
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            PlugMark(size: 54)
            Text("No plugins found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Drop Audio Units, VST3, VST, or CLAP plugins into your\nAudio Plug-Ins folders, then hit Scan.")
                .multilineTextAlignment(.center)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Button { Task { await model.rescan() } } label: {
                Label("Scan now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
