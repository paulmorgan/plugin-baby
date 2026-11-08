import Foundation

/// A record of a plugin that has been moved into Plugin Baby's archive.
struct ArchiveEntry: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var pluginName: String
    var manufacturer: String
    var format: PluginFormat
    var domain: PluginDomain
    var version: String
    var originalPath: URL   // where to restore it to
    var archivedPath: URL   // where it currently sits in the archive
    var archivedAt: Date = Date()
    var fileSize: Int64
    var identityKey: String
}
