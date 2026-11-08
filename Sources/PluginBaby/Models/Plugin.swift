import Foundation

/// A single installed (or archived) plugin bundle on disk.
struct Plugin: Identifiable, Hashable, Codable {
    var name: String
    var manufacturer: String
    var format: PluginFormat
    var version: String
    var architecture: Architecture
    var isSigned: Bool?
    var path: URL
    var isArchived: Bool
    var fileSize: Int64

    /// Stable identity used to reference a plugin from chains, independent of
    /// whether it is currently installed or archived.
    var identityKey: String { "\(format.rawValue)|\(manufacturer)|\(name)" }

    var id: String { identityKey }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
