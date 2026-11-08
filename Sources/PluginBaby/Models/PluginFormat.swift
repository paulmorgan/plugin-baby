import Foundation

/// A supported audio plugin format and where macOS installs it.
enum PluginFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case audioUnit = "Audio Unit"
    case vst3 = "VST3"
    case vst = "VST"
    case clap = "CLAP"

    var id: String { rawValue }

    /// Bundle extension on disk.
    var fileExtension: String {
        switch self {
        case .audioUnit: return "component"
        case .vst3: return "vst3"
        case .vst: return "vst"
        case .clap: return "clap"
        }
    }

    /// Subfolder under ~/Library/Audio/Plug-Ins.
    var installSubdirectory: String {
        switch self {
        case .audioUnit: return "Components"
        case .vst3: return "VST3"
        case .vst: return "VST"
        case .clap: return "CLAP"
        }
    }

    /// Only Audio Units can currently be auditioned (hosted) natively.
    var canAudition: Bool { self == .audioUnit }
}
