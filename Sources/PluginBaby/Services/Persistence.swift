import Foundation

/// Local, file-based storage under ~/Library/Application Support/Plugin Baby.
struct Persistence {
    static let shared = Persistence()

    let appSupport: URL
    let archiveDir: URL
    let samplesDir: URL
    let chainsFile: URL
    let manifestFile: URL
    let pluginCacheFile: URL

    init() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // Prefer the standard Application Support location, but fall back to a
        // user-writable path if it can't be created (e.g. a misconfigured Mac
        // where ~/Library/Application Support is root-owned).
        var candidates: [URL] = []
        if let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(appSup.appendingPathComponent("Plugin Baby", isDirectory: true))
        }
        candidates.append(home.appendingPathComponent("Library/Plugin Baby", isDirectory: true))
        candidates.append(home.appendingPathComponent(".plugin-baby", isDirectory: true))

        var chosen = candidates.last!
        for candidate in candidates {
            let archive = candidate.appendingPathComponent("archive", isDirectory: true)
            if (try? fm.createDirectory(at: archive, withIntermediateDirectories: true)) != nil {
                chosen = candidate
                break
            }
        }

        appSupport = chosen
        archiveDir = chosen.appendingPathComponent("archive", isDirectory: true)
        samplesDir = chosen.appendingPathComponent("samples", isDirectory: true)
        chainsFile = chosen.appendingPathComponent("chains.json")
        manifestFile = chosen.appendingPathComponent("archive-manifest.json")
        pluginCacheFile = chosen.appendingPathComponent("plugins-cache.json")
        try? fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: samplesDir, withIntermediateDirectories: true)
    }

    /// Human-readable location where Plugin Baby keeps its data.
    var locationDescription: String {
        appSupport.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    func loadChains() -> [Chain] {
        guard let data = try? Data(contentsOf: chainsFile) else { return [] }
        return (try? JSONDecoder().decode([Chain].self, from: data)) ?? []
    }

    func saveChains(_ chains: [Chain]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(chains) {
            try? data.write(to: chainsFile, options: .atomic)
        }
    }

    func loadManifest() -> [ArchiveEntry] {
        guard let data = try? Data(contentsOf: manifestFile) else { return [] }
        return (try? JSONDecoder().decode([ArchiveEntry].self, from: data)) ?? []
    }

    func saveManifest(_ entries: [ArchiveEntry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: manifestFile, options: .atomic)
        }
    }

    // MARK: - Plugin list cache

    /// The cached result of the last successful scan, plus when it was taken.
    /// Loading from this lets the app start instantly without re-scanning.
    private struct PluginCache: Codable {
        var scannedAt: Date
        var plugins: [Plugin]
    }

    func savePluginCache(_ plugins: [Plugin], scannedAt: Date) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(PluginCache(scannedAt: scannedAt, plugins: plugins)) {
            try? data.write(to: pluginCacheFile, options: .atomic)
        }
    }

    /// The last saved plugin list and its scan date, or nil if none exists yet.
    func loadPluginCache() -> (plugins: [Plugin], scannedAt: Date)? {
        guard let data = try? Data(contentsOf: pluginCacheFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cache = try? decoder.decode(PluginCache.self, from: data) else { return nil }
        return (cache.plugins, cache.scannedAt)
    }
}
