import Foundation
import Observation

/// Central app state and the operations the UI drives.
@MainActor
@Observable
final class AppModel {
    var plugins: [Plugin] = []
    var chains: [Chain] = []
    var archive: [ArchiveEntry] = []

    var searchText = ""
    var formatFilter: PluginFormat?
    var isScanning = false
    var lastError: String?

    let audition = AuditionEngine()
    private let archiver = ArchiveManager()

    func initialLoad() async {
        chains = Persistence.shared.loadChains()
        archive = Persistence.shared.loadManifest()
        await rescan()
    }

    func rescan() async {
        isScanning = true
        let scanned = await Task.detached { PluginScanner.scanAll() }.value
        plugins = scanned
        isScanning = false
    }

    var filteredPlugins: [Plugin] {
        plugins.filter { plugin in
            (formatFilter == nil || plugin.format == formatFilter)
            && (searchText.isEmpty
                || plugin.name.localizedCaseInsensitiveContains(searchText)
                || plugin.manufacturer.localizedCaseInsensitiveContains(searchText))
        }
    }

    func plugin(forIdentity key: String) -> Plugin? {
        plugins.first { $0.identityKey == key }
    }

    // MARK: - Archive / restore / delete

    func archivePlugin(_ plugin: Plugin) {
        do {
            let entry = try archiver.archive(plugin)
            archive.append(entry)
            Persistence.shared.saveManifest(archive)
            plugins.removeAll { $0.id == plugin.id }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore(_ entry: ArchiveEntry) {
        do {
            try archiver.restore(entry)
            archive.removeAll { $0.id == entry.id }
            Persistence.shared.saveManifest(archive)
            Task { await rescan() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteArchived(_ entry: ArchiveEntry) {
        do {
            try archiver.trashArchived(entry)
            archive.removeAll { $0.id == entry.id }
            Persistence.shared.saveManifest(archive)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Chains

    func addChain(_ name: String) {
        chains.append(Chain(name: name))
        Persistence.shared.saveChains(chains)
    }

    func deleteChain(_ chain: Chain) {
        chains.removeAll { $0.id == chain.id }
        Persistence.shared.saveChains(chains)
    }

    func addPlugin(_ plugin: Plugin, to chainID: UUID) {
        guard let index = chains.firstIndex(where: { $0.id == chainID }) else { return }
        if !chains[index].pluginIdentityKeys.contains(plugin.identityKey) {
            chains[index].pluginIdentityKeys.append(plugin.identityKey)
            Persistence.shared.saveChains(chains)
        }
    }

    func removePlugin(at offset: Int, from chainID: UUID) {
        guard let index = chains.firstIndex(where: { $0.id == chainID }),
              chains[index].pluginIdentityKeys.indices.contains(offset) else { return }
        chains[index].pluginIdentityKeys.remove(at: offset)
        Persistence.shared.saveChains(chains)
    }
}
