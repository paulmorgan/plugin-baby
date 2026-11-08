import SwiftUI

struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: ArchiveEntry.ID?

    var body: some View {
        Group {
            if model.archive.isEmpty {
                ContentUnavailableView(
                    "No archived plugins",
                    systemImage: "archivebox",
                    description: Text("Archive a plugin from the Catalog to move it out of the way. It stays here, fully recoverable, until you restore or delete it.")
                )
            } else {
                Table(model.archive, selection: $selectedID) {
                    TableColumn("Name", value: \.pluginName)
                    TableColumn("Manufacturer", value: \.manufacturer)
                    TableColumn("Format") { Text($0.format.rawValue) }
                    TableColumn("Archived") { Text($0.archivedAt, style: .date) }
                }
                .contextMenu(forSelectionType: ArchiveEntry.ID.self) { ids in
                    if let id = ids.first,
                       let entry = model.archive.first(where: { $0.id == id }) {
                        Button("Restore to original location") {
                            model.restore(entry)
                        }
                        Button("Delete (move to Trash)", role: .destructive) {
                            model.deleteArchived(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("Archive")
        .navigationSubtitle("\(model.archive.count) items")
    }
}
