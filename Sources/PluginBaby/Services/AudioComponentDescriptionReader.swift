import Foundation
import AudioToolbox

/// How an Audio Unit is auditioned.
enum AUKind {
    case effect       // processes an audio sample in series ('aufx' / 'aumf')
    case instrument   // driven by MIDI notes ('aumu')
    case other        // not auditionable here
}

/// Reads an Audio Unit's component description from its Info.plist so it can be
/// instantiated for auditioning.
enum AudioComponentDescriptionReader {
    /// Full description plus how it should be auditioned.
    static func description(for plugin: Plugin) -> (desc: AudioComponentDescription, kind: AUKind)? {
        guard plugin.format == .audioUnit,
              let info = PluginScanner.loadInfoPlist(bundle: plugin.path),
              let components = info["AudioComponents"] as? [[String: Any]],
              let first = components.first,
              let type = fourCharCode(first["type"]),
              let subtype = fourCharCode(first["subtype"]),
              let manufacturer = fourCharCode(first["manufacturer"]) else {
            return nil
        }

        let desc = AudioComponentDescription(
            componentType: type,
            componentSubType: subtype,
            componentManufacturer: manufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let kind: AUKind
        if type == fourCC("aufx") || type == fourCC("aumf") {
            kind = .effect
        } else if type == fourCC("aumu") {
            kind = .instrument
        } else {
            kind = .other
        }
        return (desc, kind)
    }

    /// Convenience: an effect-only description (used by the verification harness).
    static func effectDescription(for plugin: Plugin) -> AudioComponentDescription? {
        guard let result = description(for: plugin), result.kind == .effect else { return nil }
        return result.desc
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
