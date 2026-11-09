import Foundation

/// Scans ~/Library/Audio/Plug-Ins for installed plugin bundles.
enum PluginScanner {
    static func userPluginRoot() -> URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Audio/Plug-Ins", isDirectory: true)
    }

    static func systemPluginRoot() -> URL {
        URL(fileURLWithPath: "/Library/Audio/Plug-Ins", isDirectory: true)
    }

    static func root(for domain: PluginDomain) -> URL {
        domain == .user ? userPluginRoot() : systemPluginRoot()
    }

    static func scanAll() -> [Plugin] {
        var results: [Plugin] = []
        for domain in PluginDomain.allCases {
            let root = root(for: domain)
            for format in PluginFormat.allCases {
                let dir = root.appendingPathComponent(format.installSubdirectory, isDirectory: true)
                results.append(contentsOf: scan(dir: dir, format: format, domain: domain))
            }
        }
        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func scan(dir: URL, format: PluginFormat, domain: PluginDomain) -> [Plugin] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path),
              let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else { return [] }

        var found: [Plugin] = []
        for case let url as URL in enumerator {
            if url.pathExtension == format.fileExtension {
                enumerator.skipDescendants() // treat the bundle as a leaf
                if let plugin = makePlugin(bundle: url, format: format, domain: domain, archived: false) {
                    found.append(plugin)
                }
            }
        }
        return found
    }

    static func makePlugin(bundle: URL, format: PluginFormat, domain: PluginDomain, archived: Bool) -> Plugin? {
        // A plugin is usually a bundle (a directory with Contents/Info.plist and
        // Contents/MacOS/<exec>), but some formats — notably CLAP — may ship as a
        // single plain dylib file. In that case the file *is* the executable and
        // there is no Info.plist, so read metadata from the file directly.
        let isBundle = (try? bundle.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? true

        let info = isBundle ? loadInfoPlist(bundle: bundle) : nil
        let name = (info?["CFBundleName"] as? String)
            ?? bundle.deletingPathExtension().lastPathComponent
        let version = (info?["CFBundleShortVersionString"] as? String)
            ?? (info?["CFBundleVersion"] as? String)
            ?? "—"
        let manufacturer = manufacturerName(bundleID: info?["CFBundleIdentifier"] as? String)
        let exec = isBundle ? executableURL(bundle: bundle, info: info) : bundle
        let arch = exec.map(architecture(ofMachO:)) ?? .unknown
        let signed: Bool? = exec != nil ? isSigned(bundle) : nil
        let size = isBundle ? directorySize(bundle) : fileSize(bundle)
        let added = (try? bundle.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            ?? (try? bundle.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast

        return Plugin(
            name: name,
            manufacturer: manufacturer,
            format: format,
            domain: domain,
            version: version,
            architecture: arch,
            isSigned: signed,
            path: bundle,
            isArchived: archived,
            fileSize: size,
            dateAdded: added
        )
    }

    // MARK: - Helpers

    static func loadInfoPlist(bundle: URL) -> [String: Any]? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return obj as? [String: Any]
    }

    static func manufacturerName(bundleID: String?) -> String {
        guard let id = bundleID else { return "Unknown" }
        let parts = id.split(separator: ".")
        if parts.count >= 2 {
            let candidate = String(parts[1])
            return candidate.prefix(1).uppercased() + candidate.dropFirst()
        }
        return "Unknown"
    }

    static func executableURL(bundle: URL, info: [String: Any]?) -> URL? {
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        if let exe = info?["CFBundleExecutable"] as? String {
            let url = macOS.appendingPathComponent(exe)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let items = try? FileManager.default.contentsOfDirectory(
            at: macOS, includingPropertiesForKeys: nil), let first = items.first {
            return first
        }
        return nil
    }

    static func architecture(ofMachO exec: URL) -> Architecture {
        let result = Shell.run("/usr/bin/lipo", ["-archs", exec.path])
        guard result.status == 0 else { return .unknown }
        let archs = result.out
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)
        let hasIntel = archs.contains("x86_64")
        let hasArm = archs.contains("arm64") || archs.contains("arm64e")
        switch (hasIntel, hasArm) {
        case (true, true): return .universal
        case (true, false): return .intel
        case (false, true): return .appleSilicon
        default: return .unknown
        }
    }

    static func isSigned(_ bundle: URL) -> Bool {
        Shell.run("/usr/bin/codesign", ["-v", "--no-strict", bundle.path]).status == 0
    }

    /// Allocated size of a single plain file (for non-bundle plugins).
    static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(
            forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}
