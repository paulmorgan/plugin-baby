import Foundation
import AudioToolbox

/// Reads an Audio Unit's component description from its Info.plist so it can be
/// instantiated for auditioning. Only effect units can process a sample in series.
enum AudioComponentDescriptionReader {
    static func effectDescription(for plugin: Plugin) -> AudioComponentDescription? {
        guard plugin.format == .audioUnit,
              let info = PluginScanner.loadInfoPlist(bundle: plugin.path),
              let components = info["AudioComponents"] as? [[String: Any]],
              let first = components.first,
              let type = fourCharCode(first["type"]),
              let subtype = fourCharCode(first["subtype"]),
              let manufacturer = fourCharCode(first["manufacturer"]) else {
            return nil
        }

        // 'aufx' = effect, 'aumf' = music effect. Only these insert in series.
        let effectTypes: Set<FourCharCode> = [fourCC("aufx"), fourCC("aumf")]
        guard effectTypes.contains(type) else { return nil }

        return AudioComponentDescription(
            componentType: type,
            componentSubType: subtype,
            componentManufacturer: manufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    static func fourCharCode(_ any: Any?) -> FourCharCode? {
        if let string = any as? String { return fourCC(string) }
        if let number = any as? NSNumber { return FourCharCode(truncatingIfNeeded: number.intValue) }
        if let int = any as? Int { return FourCharCode(truncatingIfNeeded: int) }
        return nil
    }

    static func fourCC(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) + FourCharCode(byte)
        }
        return result
    }
}
