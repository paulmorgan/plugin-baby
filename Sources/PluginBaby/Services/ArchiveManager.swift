import Foundation
import AppKit

enum PBError: LocalizedError {
    case unsafe(String)
    var errorDescription: String? {
        switch self { case .unsafe(let message): return message }
    }
}

/// Moves plugins between their install location and Plugin Baby's archive.
/// Archive-first: nothing is destroyed without a recoverable copy.
struct ArchiveManager {
    let persistence = Persistence.shared

    /// Move an installed plugin into the archive and return its manifest entry.
    /// System (`/Library`) plugins are moved with an administrator prompt.
    func archive(_ plugin: Plugin) throws -> ArchiveEntry {
        let fm = FileManager.default

        let values = try plugin.path.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw PBError.unsafe("Refusing to archive a symbolic link.")
        }

        let safeKey = plugin.identityKey.replacingOccurrences(of: "/", with: "_")
        let destName = "\(safeKey)__\(plugin.path.lastPathComponent)"
        let dest = persistence.archiveDir.appendingPathComponent(destName)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }

        if plugin.domain.needsPrivilege {
            // Move as admin, then hand ownership of the archived copy to the user
            // so restore/delete of that copy need no further admin prompt.
            try PrivilegedFileOps.move(from: plugin.path, to: dest, chownTo: NSUserName())
        } else {
            try fm.moveItem(at: plugin.path, to: dest)
        }

        return ArchiveEntry(
            pluginName: plugin.name,
            manufacturer: plugin.manufacturer,
            format: plugin.format,
            domain: plugin.domain,
            version: plugin.version,
            originalPath: plugin.path,
            archivedPath: dest,
            fileSize: plugin.fileSize,
            identityKey: plugin.identityKey
        )
    }

    /// Move an archived plugin back to its original install location.
    /// System plugins are restored with an administrator prompt.
    func restore(_ entry: ArchiveEntry) throws {
        let fm = FileManager.default
        let dest = entry.originalPath
        if fm.fileExists(atPath: dest.path) {
            throw PBError.unsafe("A plugin already exists at the restore location.")
        }

        if entry.domain.needsPrivilege {
            try PrivilegedFileOps.move(from: entry.archivedPath, to: dest)
        } else {
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: entry.archivedPath, to: dest)
            // Clear quarantine so Gatekeeper keeps trusting the restored bundle.
            Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path])
        }
    }

    /// Hard delete: send an archived bundle to the system Trash (recoverable).
    func trashArchived(_ entry: ArchiveEntry) throws {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: entry.archivedPath, resultingItemURL: &resulting)
    }
}
