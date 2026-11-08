import Foundation

/// CPU architectures a plugin binary contains.
enum Architecture: String, Codable, CaseIterable, Identifiable, Hashable {
    case intel = "Intel"
    case appleSilicon = "Apple Silicon"
    case universal = "Universal"
    case unknown = "Unknown"

    var id: String { rawValue }
}
