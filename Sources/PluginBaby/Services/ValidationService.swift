import Foundation
import AudioToolbox

/// Runs Apple's `auval` command-line validator against an Audio Unit. This is
/// the same validation Logic/GarageBand rely on, so a failure here is a real,
/// host-level problem — exactly what the dashboard's "issues" count reflects.
enum ValidationService {
    /// Validate a single Audio Unit. Returns `.passed` / `.failed`, or
    /// `.notApplicable` for non-AU formats. Blocking — call off the main actor.
    static func validate(_ plugin: Plugin) -> ValidationStatus {
        guard plugin.format == .audioUnit,
              let (desc, _) = AudioComponentDescriptionReader.description(for: plugin) else {
            return .notApplicable
        }
        let type = fourCharString(desc.componentType)
        let subtype = fourCharString(desc.componentSubType)
        let manu = fourCharString(desc.componentManufacturer)
        guard !type.isEmpty, !subtype.isEmpty, !manu.isEmpty else { return .notApplicable }

        // auval -v <type> <subtype> <manufacturer>  → exit 0 on pass.
        let result = Shell.run("/usr/bin/auval", ["-v", type, subtype, manu])
        return result.status == 0 ? .passed : .failed
    }

    /// Convert a FourCharCode back to its 4-character ASCII string for auval.
    static func fourCharString(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        // Only emit if all bytes are printable ASCII; otherwise auval can't use it.
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return "" }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
