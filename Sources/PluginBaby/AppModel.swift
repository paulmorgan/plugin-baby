import Foundation
import Observation

/// The hub of the app. Holds the lists the UI shows (plugins, chains, archive)
/// and the actions it triggers (rescan, archive, validate, edit chains). Views
/// read from it and call its methods; it calls the Services. Start here.
enum PluginSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case manufacturer = "Manufacturer"
    case recent = "Recently added"
    case size = "Size"
    var id: String { rawValue }
}

/// Central app state and the operations the UI drives.
@MainActor
@Observable
final class AppModel {
    var plugins: [Plugin] = []
    var chains: [Chain] = []
    var archive: [ArchiveEntry] = []

    var searchText = ""
    var formatFilter: PluginFormat?
    var sort: PluginSort = .name
    var isScanning = false
    var lastError: String?

    /// When the currently shown plugin list was scanned (from the cache or a
    /// live scan). Nil until the first scan completes.
    var lastScanDate: Date?

    /// Set true on launch when the cached list is older than `staleAfterDays`,
    /// so the UI can offer to rescan. The user can accept or keep the old list.
    var showStaleScanPrompt = false

    /// A cached list older than this (in days) is considered stale on launch.
    let staleAfterDays = 30

    /// The plugin shown in the dashboard detail panel.
    var selectedPluginID: Plugin.ID?

    /// auval results, keyed by plugin identity.
    var validation: [String: ValidationStatus] = [:]
    var isValidatingAll = false

    let audition = AuditionEngine()
    private let archiver = ArchiveManager()

    /// Whether the Mac is Apple Silicon (true even under Rosetta), for health.
    let hostIsAppleSilicon: Bool =
        Shell.run("/usr/sbin/sysctl", ["-n", "hw.optional.arm64"]).out
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1"

    func initialLoad() async {
        chains = Persistence.shared.loadChains()
        archive = Persistence.shared.loadManifest()

        // Prefer the cached list for an instant start. Only scan automatically
        // on the very first run, when no cache exists yet. If the cache is old,
        // flag it so the UI can ask whether to rescan.
        if let cache = Persistence.shared.loadPluginCache() {
            plugins = cache.plugins
            lastScanDate = cache.scannedAt
            refreshSelection()
            if let age = cacheAgeDays, age >= staleAfterDays {
                showStaleScanPrompt = true
            }
        } else {
            await rescan()
        }
    }

    func rescan() async {
        isScanning = true
        let scanned = await Task.detached { PluginScanner.scanAll() }.value
        plugins = scanned
        lastScanDate = Date()
        Persistence.shared.savePluginCache(scanned, scannedAt: lastScanDate!)
        refreshSelection()
        isScanning = false
    }

    /// Keep a valid selection for the detail panel after the list changes.
    private func refreshSelection() {
        if selectedPluginID == nil || !plugins.contains(where: { $0.id == selectedPluginID }) {
            selectedPluginID = filteredPlugins.first?.id
        }
    }

    /// Age of the shown list in whole days, or nil if never scanned.
    var cacheAgeDays: Int? {
        guard let date = lastScanDate else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }

    /// Short human description of when the list was last scanned.
    var lastScanDescription: String {
        guard let days = cacheAgeDays else { return "never scanned" }
        switch days {
        case 0: return "scanned today"
        case 1: return "scanned yesterday"
        default: return "scanned \(days) days ago"
        }
    }

    // MARK: - Filtering / sorting

    var filteredPlugins: [Plugin] {
        let base = plugins.filter { plugin in
            (formatFilter == nil || plugin.format == formatFilter)
            && (searchText.isEmpty
                || plugin.name.localizedCaseInsensitiveContains(searchText)
                || plugin.manufacturer.localizedCaseInsensitiveContains(searchText))
        }
        switch sort {
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .manufacturer:
            return base.sorted {
                $0.manufacturer.localizedCaseInsensitiveCompare($1.manufacturer) == .orderedAscending
            }
        case .recent:
            return base.sorted { $0.dateAdded > $1.dateAdded }
        case .size:
            return base.sorted { $0.fileSize > $1.fileSize }
        }
    }

    func plugin(forIdentity key: String) -> Plugin? {
        plugins.first { $0.identityKey == key }
    }

    var selectedPlugin: Plugin? {
        plugins.first { $0.id == selectedPluginID }
    }

    // MARK: - Dashboard stats

    var manufacturersCount: Int { Set(plugins.map(\.manufacturer)).count }

    var recentlyAdded: [Plugin] {
        plugins.filter { $0.dateAdded > .distantPast }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    var recentlyAddedCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return plugins.filter { $0.dateAdded > cutoff }.count
    }

    func health(for plugin: Plugin) -> PluginHealth {
        PluginHealth.evaluate(plugin, hostIsAppleSilicon: hostIsAppleSilicon)
    }

    var healthIssueCount: Int { plugins.filter { !health(for: $0).isOK }.count }
    var validationFailureCount: Int { validation.values.filter { $0 == .failed }.count }
    /// Total "issues" surfaced on the dashboard: health warnings + auval failures.
    var issueCount: Int { healthIssueCount + validationFailureCount }

    // MARK: - Validation (auval)

    func validationStatus(for plugin: Plugin) -> ValidationStatus {
        if plugin.format != .audioUnit { return .notApplicable }
        return validation[plugin.identityKey] ?? .unknown
    }

    func validate(_ plugin: Plugin) {
        guard plugin.format == .audioUnit else { return }
        let key = plugin.identityKey
        validation[key] = .running
        Task {
            let status = await Task.detached { ValidationService.validate(plugin) }.value
            validation[key] = status
        }
    }

    func validateAllAUs() {
        guard !isValidatingAll else { return }
        let aus = plugins.filter { $0.format == .audioUnit }
        guard !aus.isEmpty else { return }
        isValidatingAll = true
        for au in aus { validation[au.identityKey] = .running }
        Task {
            for au in aus {
                let status = await Task.detached { ValidationService.validate(au) }.value
                validation[au.identityKey] = status
            }
            isValidatingAll = false
        }
    }

    // MARK: - Archive / restore / delete

    func archivePlugin(_ plugin: Plugin) {
        do {
            let entry = try archiver.archive(plugin)
            archive.append(entry)
            Persistence.shared.saveManifest(archive)
            plugins.removeAll { $0.id == plugin.id }
            if selectedPluginID == plugin.id { selectedPluginID = filteredPlugins.first?.id }
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
