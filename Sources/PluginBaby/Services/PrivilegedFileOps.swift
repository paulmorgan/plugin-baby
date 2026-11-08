import Foundation

/// Runs file moves that require administrator rights (for system `/Library`
/// plugins) via a single macOS authentication prompt. No privileged helper is
/// installed; each call shows the standard admin password dialog.
enum PrivilegedFileOps {
    /// Shell-quote a path for safe interpolation.
    static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Run a shell command as administrator. Throws if it fails or is cancelled.
    static func runAdmin(_ shellCommand: String) throws {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let result = Shell.run("/usr/bin/osascript", ["-e", script])
        if result.status != 0 {
            throw PBError.unsafe("Administrator operation failed or was cancelled.")
        }
    }

    /// Move `source` to `dest` as admin, creating the destination's parent and
    /// making the moved item owned by `owner` (so later steps need no admin).
    static func move(from source: URL, to dest: URL, chownTo owner: String? = nil) throws {
        var command = "/bin/mkdir -p \(quote(dest.deletingLastPathComponent().path)) "
            + "&& /bin/mv \(quote(source.path)) \(quote(dest.path))"
        if let owner {
            command += " && /usr/sbin/chown -R \(quote(owner)) \(quote(dest.path))"
        }
        try runAdmin(command)
    }
}
