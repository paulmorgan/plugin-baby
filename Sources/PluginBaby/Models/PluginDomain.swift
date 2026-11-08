import Foundation

/// Which plugin folder a bundle lives in.
enum PluginDomain: String, Codable, CaseIterable, Identifiable, Hashable {
    case user = "User"      // ~/Library/Audio/Plug-Ins
    case system = "System"  // /Library/Audio/Plug-Ins (needs admin to modify)

    var id: String { rawValue }

    /// System moves require administrator privileges.
    var needsPrivilege: Bool { self == .system }
}
