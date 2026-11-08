import SwiftUI

/// A quick, offline health read derived from a plugin's own metadata — no
/// external process needed. Surfaces things macOS *does* expose: code signing
/// and CPU architecture. (Unlike licensing or update state, which no third
/// party reliably exposes.)
enum PluginHealth: Equatable {
    case ok
    case warning(String)

    var isOK: Bool { if case .ok = self { return true }; return false }

    var detail: String? {
        if case let .warning(text) = self { return text }
        return nil
    }

    var color: Color { isOK ? Color(red: 0.3, green: 0.9, blue: 0.55) : Color(red: 1.0, green: 0.72, blue: 0.2) }
    var symbol: String { isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }

    static func evaluate(_ plugin: Plugin, hostIsAppleSilicon: Bool) -> PluginHealth {
        var issues: [String] = []
        if plugin.isSigned == false { issues.append("unsigned") }
        if plugin.architecture == .intel && hostIsAppleSilicon { issues.append("Intel-only (needs Rosetta)") }
        if plugin.architecture == .unknown { issues.append("unreadable binary") }
        return issues.isEmpty ? .ok : .warning(issues.joined(separator: ", "))
    }
}
