import Foundation

/// An ordered, named group of plugins.
struct Chain: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var pluginIdentityKeys: [String] = []
    var notes: String = ""
    var createdAt: Date = Date()
}
