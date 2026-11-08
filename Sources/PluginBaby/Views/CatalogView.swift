import SwiftUI
import AppKit

struct CatalogView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: Plugin.ID?

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack {
                Picker("Format", selection: $model.formatFilter) {
                    Text("All").tag(PluginFormat?.none)
                    ForEach(PluginFormat.allCases) { format in
                        Text(format.rawValue).tag(PluginFormat?.some(format))
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                .labelsHidden()

                Spacer()

                if model.isScanning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await model.rescan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            Table(model.filteredPlugins, selection: $selectedID) {
                TableColumn("Name", value: \.name)
                TableColumn("Manufacturer", value: \.manufacturer)
                TableColumn("Format") { Text($0.format.rawValue) }
                TableColumn("Where") { Text($0.domain.rawValue).foregroundStyle(.secondary) }
                TableColumn("Version", value: \.version)
                TableColumn("Arch") { Text($0.architecture.rawValue) }
                TableColumn("Size") { Text($0.formattedSize) }
            }
            .contextMenu(forSelectionType: Plugin.ID.self) { ids in
                if let id = ids.first,
                   let plugin = model.filteredPlugins.first(where: { $0.id == id }) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([plugin.path])
                    }
                    Button(plugin.domain.needsPrivilege ? "Archive (needs admin)…" : "Archive") {
                        model.archivePlugin(plugin)
                    }
                }
            }
        }
        .navigationTitle("Catalog")
        .navigationSubtitle("\(model.filteredPlugins.count) plugins")
        .searchable(text: $model.searchText, prompt: "Search name or manufacturer")
    }
}
